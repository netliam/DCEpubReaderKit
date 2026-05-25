//
//  DCReaderViewModel.swift
//  DCEpubReaderKit
//
//  Created by Josep Cerdá Penadés on 31/10/25.
//

import SwiftUI
import DCEpubCore

@MainActor
final class DCReaderViewModel: ObservableObject {

    // MARK: Config values
    @Published var textSize: CGFloat
    @Published var textFont: String
    @Published var desktopMode: String
    @Published var orientation: String

    // Current selected spine for the pager
    @Published var currentSelection: Int
    @Published var previousSelection: Int

    @Published var totalPages: Int = 1
    @Published var currentPage: Int = 1
    @Published var canTouch: Bool = true

    @Published var showSettings: Bool = false
    @Published var settingsSheetHeight: CGFloat = 0

    @Published var showMarks: Bool = false
    @Published var showNote: Bool = false
    @Published var pendingNoteHighlight: DCHighlight?

    var chapterViewModels: [Int: DCChapterWebViewModel] = [:]
    private var pendingNavigationCoordsBySpineIndex: [Int: String] = [:]

    private let book: DCEpubBook
    private let spineIndex: Int
    private let initialCoords: String?
    private let userPreferencesProtocol: DCUserPreferencesProtocol
    private let delegate: DCReaderCoordsProtocol?

    public init(book: DCEpubBook,
                spineIndex: Int,
                initialCoords: String? = nil,
                userPreferencesProtocol: DCUserPreferencesProtocol,
                delegate: DCReaderCoordsProtocol?) {
        self.book = book
        self.spineIndex = spineIndex
        self.initialCoords = initialCoords
        self.userPreferencesProtocol = userPreferencesProtocol
        self.delegate = delegate

        // Initial values
        self.currentSelection = spineIndex
        self.previousSelection = spineIndex
        self.textSize = userPreferencesProtocol.getFontSize().size
        self.textFont = userPreferencesProtocol.getFontFamily().name
        self.desktopMode = userPreferencesProtocol.getDesktopMode().mode
        self.orientation = userPreferencesProtocol.getBookOrientation().rawValue

        // Defaults
        self.totalPages = 1
        self.currentPage = 1
        self.canTouch = true
        self.showSettings = false
        self.settingsSheetHeight = 0
        self.showMarks = false
    }

    var bookId: String {
        book.uniqueIdentifier
    }

    var bookSpines: [DCSpineItem] {
        book.spine
    }

    func chapterURL(for idx: Int) -> URL? {
        book.chapterURL(forSpineIndex: idx)
    }

    var opfDirectoryURL: URL {
        book.opfDirectoryURL
    }

    func readerConfigId(for idx: Int) -> String {
        "\(idx)-\(textFont)-\(desktopMode)-\(textSize)-\(orientation)"
    }

    func initialCoords(for idx: Int) -> String? {
        guard idx == spineIndex else { return nil }
        return initialCoords
    }

    var pageInfo: String {
        "página \(currentPage) de \(totalPages)"
    }

    var backgroundColor: Color {
        userPreferences.getDesktopMode().backgroundColor
    }

    var textColor: Color {
        userPreferences.getDesktopMode().textColor
    }

    var bookTitle: String {
        book.bookTitle
    }

    var userPreferences: DCUserPreferencesProtocol {
        userPreferencesProtocol
    }

    var bookOrientation: DCBookrOrientation {
        userPreferencesProtocol.getBookOrientation()
    }

    func handle(_ action: DCChapterViewAction, chapterURL: URL?) {
        switch action {
        case let .totalPageCount(count, spineIndex):
            handleTotalPageCount(count, in: spineIndex)

        case let .currentPage(index, totalPages, spineIndex):
            handleCurrentPage(index: index, totalPages: totalPages, in: spineIndex)

        case let .canTouch(enabled):
            updateTouch(enabled)

        case let .coordsFirstNodeOfPage(_, spineIndex, coords, isBookMark):
            handleCoords(spineIndex: spineIndex, coords: coords, chapterURL: chapterURL, isBookMark: isBookMark)

        case .navigateToNextChapter:
            navigateToNextChapter()

        case .navigateToPreviousChapter:
            navigateToPreviousChapter()

        case let .showNote(highlight):
            pendingNoteHighlight = highlight
            showNote = true
        }
    }

    private func handleTotalPageCount(_ count: Int, in spineIndex: Int) {
        guard spineIndex == currentSelection else { return }

        totalPages = count
        if currentPage > count {
            currentPage = count
        }
    }

    private func handleCurrentPage(index: Int,
                                   totalPages: Int,
                                   in spineIndex: Int) {
        guard spineIndex == currentSelection else { return }

        self.totalPages = totalPages
        self.currentPage = index
    }

    @MainActor
    private func updateTouch(_ enabled: Bool) {
        Task {
            self.canTouch = enabled
        }
    }

    private func handleCoords(spineIndex: Int,
                              coords: String,
                              chapterURL: URL?,
                              isBookMark: Bool) {
        guard spineIndex == currentSelection else { return }
        if let chapterURL {
            delegate?.handleCoords(
                book: book,
                spineIndex: spineIndex,
                coords: coords,
                chapterURL: chapterURL,
                isBookMark: isBookMark
            )
        }
    }

    private func navigateToNextChapter() {
        guard currentSelection + 1 < bookSpines.count else { return }
        currentSelection += 1
    }

    private func navigateToPreviousChapter() {
        guard currentSelection > 0 else { return }
        currentSelection -= 1
    }

    var gesture: DragGesture? {
        bookOrientation == .vertical ? DragGesture() : nil
    }

    @MainActor
    func updateCurrentPage() {
        defer {
            previousSelection = currentSelection
        }
        chapterViewModels[currentSelection]?.updateCurrentPage(
            target: currentSelection < previousSelection ? currentSelection : nil
        )
    }

    @MainActor
    func handleSelectionDidChange() {
        defer {
            previousSelection = currentSelection
        }

        // Only consume the pending coord when the chapter viewModel is already available.
        // If the chapter has not yet registered its viewModel (first-time load), the coord
        // stays in pendingNavigationCoordsBySpineIndex so that restoreInitialPositionIfNeeded
        // can consume it once the WebView finishes loading.
        if let chapterViewModel = chapterViewModels[currentSelection],
           let coords = pendingNavigationCoordsBySpineIndex[currentSelection] {
            pendingNavigationCoordsBySpineIndex.removeValue(forKey: currentSelection)
            chapterViewModel.scrollToHighlight(coords: coords)
            return
        }

        chapterViewModels[currentSelection]?.updateCurrentPage(
            target: currentSelection < previousSelection ? currentSelection : nil
        )
    }

    @MainActor
    func saveBookMark() {
        chapterViewModels[currentSelection]?.saveBookmark()
    }

    func allHighlights() async -> [DCHighlight] {
        let highlights = await delegate?.highlights(for: book) ?? []
        return highlights.sorted { $0.dateUpdated > $1.dateUpdated }
    }

    @MainActor
    func navigate(to highlight: DCHighlight) {
        showMarks = false

        if highlight.spineIndex == currentSelection {
            chapterViewModels[currentSelection]?.scrollToHighlight(coords: highlight.coords)
            return
        }

        pendingNavigationCoordsBySpineIndex[highlight.spineIndex] = highlight.coords
        currentSelection = highlight.spineIndex
    }

    func registerChapterViewModel(_ viewModel: DCChapterWebViewModel, for index: Int) {
        if let existing = chapterViewModels[index], existing === viewModel {
            return
        }
        chapterViewModels[index] = viewModel
    }
}

extension DCReaderViewModel: DCChapterReaderContextProtocol {
    var currentBook: DCEpubBook { book }

    func consumeInitialCoords(for spineIndex: Int, chapterURL: URL) -> String? {
        if let coords = pendingNavigationCoordsBySpineIndex.removeValue(forKey: spineIndex) {
            return coords
        }
        guard spineIndex == self.spineIndex else { return nil }
        guard chapterURL == book.chapterURL(forSpineIndex: spineIndex) else { return nil }
        return initialCoords
    }

    func showNote(highlight: DCHighlight) {
        pendingNoteHighlight = highlight
        showNote = true
    }

    func save(highlight: DCHighlight) async {
        await delegate?.save(highlight: highlight)
    }

    func deleteHighlight(uuid: String) async {
        await delegate?.deleteHighlight(uuid: uuid, book: book)
    }

    func highlights(for chapterId: String) async -> [DCHighlight] {
        if let chapterHighlights = await delegate?.highlights(for: book, chapterId: chapterId) {
            return chapterHighlights
        }

        if let allHighlights = await delegate?.highlights(for: book) {
            return allHighlights.filter { $0.chapterId == chapterId }
        }

        return []
    }
}
