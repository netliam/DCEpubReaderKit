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
    @Published var pageTransition: String

    // Current selected spine for the pager
    @Published var currentSelection: Int
    @Published var previousSelection: Int

    @Published var totalPages: Int = 1
    @Published var currentPage: Int = 1
    @Published var canTouch: Bool = true

    @Published var showSettings: Bool = false
    @Published var settingsSheetHeight: CGFloat = 0

    @Published var showMarks: Bool = false
    @Published var showSearch: Bool = false
    @Published var showNote: Bool = false
    @Published var pendingNoteHighlight: DCHighlight?

    var chapterViewModels: [Int: DCChapterWebViewModel] = [:]
    private var pendingJumpsBySpineIndex: [Int: DCChapterJump] = [:]
    /// Paged (horizontal) reader, set when it is created.
    weak var pagedNavigator: DCPagedReaderNavigating?
    /// Created lazily so books that are never searched don't pay for text extraction. Kept for the
    /// reader's lifetime so the query and results survive closing the search sheet.
    private(set) lazy var searchViewModel = DCSearchViewModel(
        engine: DCEpubSearchEngine(book: book)
    ) { [weak self] result, query in
        self?.navigate(to: result, query: query)
    }
    /// Last reported reading position, used to resume when the reader is rebuilt.
    private var lastPosition: (spineIndex: Int, coords: String)?

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
        self.pageTransition = userPreferencesProtocol.getPageTransition().rawValue

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
        Self.pageInfo(currentPage: currentPage, totalPages: totalPages)
    }

    static func pageInfo(currentPage: Int, totalPages: Int) -> String {
        "página \(currentPage) de \(totalPages)"
    }

    /// Horizontal mode uses the `UIPageViewController` reader; vertical keeps the scrolling chapters.
    var isPagedMode: Bool {
        orientation == DCBookrOrientation.horizontal.rawValue
    }

    /// Settings that require the paged reader to paginate again (or change transition style).
    var pagedConfigId: String {
        "\(textFont)-\(desktopMode)-\(textSize)-\(pageTransition)"
    }

    /// Coords to open `spineIndex` at: the last reported position, else the initial coords.
    func resumeCoords(for spineIndex: Int) -> String? {
        if let lastPosition, lastPosition.spineIndex == spineIndex {
            return lastPosition.coords
        }
        return initialCoords(for: spineIndex)
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

        case let .spineDidChange(spineIndex):
            guard currentSelection != spineIndex else { return }
            currentSelection = spineIndex
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
        if !isBookMark {
            lastPosition = (spineIndex, coords)
        }
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
        // The paged reader drives `currentSelection` itself and positions its own pages.
        guard !isPagedMode else { return }

        // Only consume the pending coord when the chapter viewModel is already available.
        // If the chapter has not yet registered its viewModel (first-time load), the coord
        // stays in pendingJumpsBySpineIndex so that restoreInitialPositionIfNeeded
        // can consume it once the WebView finishes loading.
        if let chapterViewModel = chapterViewModels[currentSelection],
           let jump = pendingJumpsBySpineIndex[currentSelection] {
            pendingJumpsBySpineIndex.removeValue(forKey: currentSelection)
            chapterViewModel.jump(to: jump)
            return
        }

        chapterViewModels[currentSelection]?.updateCurrentPage(
            target: currentSelection < previousSelection ? currentSelection : nil
        )
    }

    @MainActor
    func saveBookMark() {
        if isPagedMode {
            pagedNavigator?.saveBookmark()
            return
        }
        chapterViewModels[currentSelection]?.saveBookmark()
    }

    func allHighlights() async -> [DCHighlight] {
        let highlights = await delegate?.highlights(for: book) ?? []
        return highlights.sorted { $0.dateUpdated > $1.dateUpdated }
    }

    @MainActor
    func navigate(to highlight: DCHighlight) {
        showMarks = false
        if isPagedMode {
            pagedNavigator?.show(spineIndex: highlight.spineIndex, coords: highlight.coords)
            return
        }
        navigate(to: .coords(highlight.coords), in: highlight.spineIndex)
    }

    @MainActor
    func navigate(to result: DCSearchResult, query: String) {
        showSearch = false
        if isPagedMode {
            pagedNavigator?.show(spineIndex: result.spineIndex, searchQuery: query, occurrence: result.occurrence)
            return
        }
        navigate(to: .search(query: query, occurrence: result.occurrence), in: result.spineIndex)
    }

    /// Vertical reader: jump now if the chapter is current, else once it loads (see `consumeInitialJump`).
    @MainActor
    private func navigate(to jump: DCChapterJump, in spineIndex: Int) {
        if spineIndex == currentSelection {
            chapterViewModels[currentSelection]?.jump(to: jump)
            return
        }
        pendingJumpsBySpineIndex[spineIndex] = jump
        currentSelection = spineIndex
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

    func consumeInitialJump(for spineIndex: Int, chapterURL: URL) -> DCChapterJump? {
        if let jump = pendingJumpsBySpineIndex.removeValue(forKey: spineIndex) {
            return jump
        }
        guard spineIndex == self.spineIndex else { return nil }
        guard chapterURL == book.chapterURL(forSpineIndex: spineIndex) else { return nil }
        guard let initialCoords, !initialCoords.isEmpty else { return nil }
        return .coords(initialCoords)
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
