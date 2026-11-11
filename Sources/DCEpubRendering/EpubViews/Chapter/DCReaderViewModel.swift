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
    @Published var theme: String
    @Published var followsSystemAppearance: Bool
    /// Mirrors the system appearance (set by the view from its color scheme).
    @Published var systemIsDark: Bool = false
    @Published var orientation: String
    @Published var pageTransition: String
    @Published var lineFocus: Bool
    @Published var lineFocusStyle: String

    // Current selected spine for the pager
    @Published var currentSelection: Int
    @Published var previousSelection: Int

    @Published var totalPages: Int = 1
    @Published var currentPage: Int = 1
    @Published var canTouch: Bool = true

    @Published var showSettings: Bool = false

    @Published var showContents: Bool = false
    @Published var showShare: Bool = false
    /// What the share sheet shares: title and author, plus the selected text if any.
    @Published private(set) var shareText: String = ""
    /// Briefly replaces the "pages left" label (e.g. "Line Guide: On").
    @Published private(set) var transientStatus: String?
    /// The book's bookmarks, loaded when the reader opens and kept in sync as they are added/removed.
    @Published private(set) var bookmarks: [DCHighlight] = []
    /// Bookmarks that land on the page on screen (usually zero or one).
    @Published private(set) var currentPageBookmarkIds: [String] = []
    /// Page count per spine index from the background paginator.
    @Published private(set) var bookPageCounts: [Int: Int] = [:]
    /// False until the first page reports its position, so the labels don't flash placeholder values.
    @Published private(set) var hasPagePosition: Bool = false
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
    private let paginator: DCBookPaginator
    /// The last complete count, used to estimate page numbers while a new layout is being counted.
    private var lastCompleteBookPageCounts: [Int: Int] = [:]
    private var transientStatusTask: Task<Void, Never>?
    private var bookmarkCheckTask: Task<Void, Never>?

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
        self.theme = userPreferencesProtocol.getTheme().rawValue
        self.followsSystemAppearance = userPreferencesProtocol.getFollowsSystemAppearance()
        self.orientation = userPreferencesProtocol.getBookOrientation().rawValue
        self.pageTransition = userPreferencesProtocol.getPageTransition().rawValue
        self.lineFocus = userPreferencesProtocol.getLineFocus()
        self.lineFocusStyle = userPreferencesProtocol.getLineFocusStyle().rawValue

        // Defaults
        self.totalPages = 1
        self.currentPage = 1
        self.canTouch = true
        self.showSettings = false
        self.showContents = false
        self.paginator = DCBookPaginator(book: book, userPreferences: userPreferencesProtocol)
        paginator.onChange = { [weak self] in
            guard let self else { return }
            self.bookPageCounts = self.paginator.pageCounts
            if self.paginator.isComplete {
                self.lastCompleteBookPageCounts = self.paginator.pageCounts
            }
        }
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
        "\(idx)-\(textFont)-\(appearance.theme.fontWeight)-\(textSize)-\(orientation)-\(lineFocus)-\(lineFocusStyle)"
    }

    func initialCoords(for idx: Int) -> String? {
        guard idx == spineIndex else { return nil }
        return initialCoords
    }

    // MARK: Progress

    /// "12 pages left in chapter", shown at the top of the reader.
    var pagesLeftInChapterText: String {
        let left = max(0, totalPages - currentPage)
        switch left {
        case 0: return "Last page in chapter"
        case 1: return "1 page left in chapter"
        default: return "\(left) pages left in chapter"
        }
    }

    /// Whole-book page number and total, once every chapter has been counted. The current chapter
    /// uses the reader's own count, so the number always lines up with the page on screen.
    var bookPagePosition: (page: Int, total: Int)? {
        guard let counts = Self.estimatedPageCounts(current: bookPageCounts,
                                                    previous: lastCompleteBookPageCounts,
                                                    chapterCount: book.spine.count,
                                                    currentChapter: (currentSelection, totalPages)) else { return nil }
        let before = (0..<currentSelection).reduce(0) { $0 + (counts[$1] ?? 0) }
        let after = ((currentSelection + 1)..<book.spine.count).reduce(0) { $0 + (counts[$1] ?? 0) }
        return (before + currentPage, before + totalPages + after)
    }

    /// Page counts for every chapter: the current count when complete; otherwise, while a new layout
    /// (e.g. another text size) is being counted, chapters not counted yet are estimated from the last
    /// complete count, scaled by how the chapters counted so far changed. `nil` before any complete count.
    nonisolated static func estimatedPageCounts(current: [Int: Int],
                                                previous: [Int: Int],
                                                chapterCount: Int,
                                                currentChapter: (index: Int, pages: Int)) -> [Int: Int]? {
        guard chapterCount > 0 else { return nil }
        if current.count == chapterCount { return current }
        guard previous.count == chapterCount else { return nil }

        // The chapter on screen is always known, from the reader itself.
        var known = current
        known[currentChapter.index] = currentChapter.pages
        let newPages = known.values.reduce(0, +)
        let oldPages = known.keys.reduce(0) { $0 + (previous[$1] ?? 0) }
        let scale = oldPages > 0 ? Double(newPages) / Double(oldPages) : 1

        var estimate: [Int: Int] = [:]
        for index in 0..<chapterCount {
            estimate[index] = known[index] ?? max(1, Int((Double(previous[index] ?? 1) * scale).rounded()))
        }
        return estimate
    }

    /// Whole-book page number where a chapter starts, once every chapter has been counted.
    func bookStartPage(of spineIndex: Int) -> Int? {
        guard let counts = Self.estimatedPageCounts(current: bookPageCounts,
                                                    previous: lastCompleteBookPageCounts,
                                                    chapterCount: book.spine.count,
                                                    currentChapter: (currentSelection, totalPages)) else { return nil }
        return (0..<spineIndex).reduce(1) { $0 + (counts[$1] ?? 0) }
    }

    /// "415 of 832", or the chapter while the book is still being counted.
    var progressText: String {
        if let position = bookPagePosition {
            return "\(position.page) of \(position.total)"
        }
        return "Chapter \(currentSelection + 1) of \(max(book.spine.count, 1))"
    }

    /// Fraction of the book read, for the progress bar. Estimated from the chapter until counted.
    var readingProgress: Double {
        if let position = bookPagePosition, position.total > 0 {
            return Double(position.page) / Double(position.total)
        }
        let chapterFraction = Double(max(currentPage - 1, 0)) / Double(max(totalPages, 1))
        return (Double(currentSelection) + chapterFraction) / Double(max(book.spine.count, 1))
    }

    /// Text for the top label: a transient status if one is showing, else pages left.
    var topStatusText: String {
        transientStatus ?? pagesLeftInChapterText
    }

    /// Horizontal mode uses the `UIPageViewController` reader; vertical keeps the scrolling chapters.
    var isPagedMode: Bool {
        orientation == DCBookrOrientation.horizontal.rawValue
    }

    var lineFocusSettings: (enabled: Bool, style: DCLineFocusStyle) {
        (lineFocus, DCLineFocusStyle(rawValue: lineFocusStyle) ?? .guide)
    }

    /// Settings that require the paged reader to paginate again (or change transition style).
    /// Line focus and theme colors aren't among them: they are applied to the pages on screen.
    /// Only the theme's font weight (Bold) changes the layout.
    var pagedConfigId: String {
        "\(textFont)-\(appearance.theme.fontWeight)-\(textSize)-\(pageTransition)"
    }

    /// Coords to open `spineIndex` at: the last reported position, else the initial coords.
    func resumeCoords(for spineIndex: Int) -> String? {
        if let lastPosition, lastPosition.spineIndex == spineIndex {
            return lastPosition.coords
        }
        return initialCoords(for: spineIndex)
    }

    /// The theme's light or dark palette, depending on the system appearance and the setting.
    var appearance: DCReaderAppearance {
        DCReaderAppearance(theme: DCReaderTheme(rawValue: theme) ?? .original,
                           isDark: followsSystemAppearance && systemIsDark)
    }

    var backgroundColor: Color {
        appearance.backgroundColor
    }

    var textColor: Color {
        appearance.textColor
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
            currentPageBookmarkIds = []

        case let .pageLayout(size):
            let layout = DCBookPaginator.Layout(pageSize: size,
                                                isVertical: !isPagedMode,
                                                styleId: "\(textFont)-\(textSize)-\(appearance.theme.fontWeight)")
            paginator.paginate(layout: layout, appearance: appearance)
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

        hasPagePosition = true
        self.totalPages = totalPages
        self.currentPage = index
        checkCurrentPageBookmarks()
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
        if isBookMark {
            addBookmark(spineIndex: spineIndex, coords: coords, chapterURL: chapterURL)
        } else {
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
    // MARK: Bookmarks

    var isCurrentPageBookmarked: Bool {
        !currentPageBookmarkIds.isEmpty
    }

    /// Loads the book's bookmarks from the delegate, then checks the page on screen.
    func loadBookmarks() async {
        let marks = await delegate?.highlights(for: book) ?? []
        bookmarks = marks.filter { $0.type == .bookMark }
        checkCurrentPageBookmarks()
    }

    /// Bookmark button: removes the bookmarks on this page, or bookmarks it.
    @MainActor
    func toggleBookmark() {
        guard isCurrentPageBookmarked else {
            saveBookMark()
            return
        }
        let ids = currentPageBookmarkIds
        currentPageBookmarkIds = []
        bookmarks.removeAll { ids.contains($0.uuid) }
        Task {
            for uuid in ids {
                await delegate?.deleteHighlight(uuid: uuid, book: book)
            }
        }
    }

    /// Finds which bookmarks of this chapter land on the page on screen, by resolving their saved
    /// position in the live page (so it follows the current font, size and layout).
    func checkCurrentPageBookmarks() {
        bookmarkCheckTask?.cancel()
        let spineIndex = currentSelection
        let pageIndex = currentPage - 1
        let candidates = bookmarks.filter { $0.spineIndex == spineIndex }
        guard !candidates.isEmpty else {
            currentPageBookmarkIds = []
            return
        }
        bookmarkCheckTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var onPage: [String] = []
            for bookmark in candidates {
                if await self.pageIndex(forCoords: bookmark.coords, in: spineIndex) == pageIndex {
                    onPage.append(bookmark.uuid)
                }
            }
            guard !Task.isCancelled, spineIndex == self.currentSelection, pageIndex == self.currentPage - 1 else { return }
            self.currentPageBookmarkIds = onPage
        }
    }

    /// Page (0-based, within the chapter) that a saved position falls on in the reader on screen.
    @MainActor
    private func pageIndex(forCoords coords: String, in spineIndex: Int) async -> Int? {
        if isPagedMode {
            return await pagedNavigator?.pageIndex(forCoords: coords)
        }
        return await chapterViewModels[spineIndex]?.pageIndex(forCoords: coords)
    }

    /// Saves a bookmark for the page on screen at `coords` (the first text on the page).
    private func addBookmark(spineIndex: Int, coords: String, chapterURL: URL?) {
        if let existing = bookmarks.first(where: { $0.spineIndex == spineIndex && $0.coords == coords }) {
            currentPageBookmarkIds = [existing.uuid]
            return
        }
        let chapterId = (chapterURL ?? book.chapterURL(forSpineIndex: spineIndex))?.lastPathComponent ?? ""
        let bookmark = DCHighlight(uuid: UUID().uuidString,
                                   bookId: bookId,
                                   chapterId: chapterId,
                                   spineIndex: spineIndex,
                                   type: .bookMark,
                                   text: "",
                                   coords: coords,
                                   chapterTitle: book.chapterTitle(forSpineIndex: spineIndex) ?? "")
        bookmarks.append(bookmark)
        currentPageBookmarkIds = [bookmark.uuid]
        Task {
            await delegate?.save(highlight: bookmark)
        }
    }

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
        showContents = false
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

    /// Opens a table-of-contents entry at its chapter (and `#fragment`, if it has one).
    @MainActor
    func navigate(to entry: DCContentsEntry) {
        showContents = false
        guard let spineIndex = entry.spineIndex else { return }
        if isPagedMode {
            pagedNavigator?.show(spineIndex: spineIndex, fragment: entry.fragment)
        } else if let fragment = entry.fragment {
            navigate(to: .fragment(fragment), in: spineIndex)
        } else {
            currentSelection = spineIndex
        }
    }

    private(set) lazy var contentsEntries: [DCContentsEntry] = DCContentsEntry.entries(for: book)

    // MARK: Menu actions

    func toggleLineFocus() {
        let isOn = !lineFocus
        userPreferences.setValue(key: .lineFocus, type: isOn)
        lineFocus = isOn
        showTransientStatus("Line Guide: \(isOn ? "On" : "Off")")
    }

    /// Collects what to share (title, author and the selected text, if any) and shows the share sheet.
    @MainActor
    func share() async {
        let selection: String?
        if isPagedMode {
            selection = await pagedNavigator?.selectedText()
        } else {
            selection = await chapterViewModels[currentSelection]?.selectedText()
        }
        var byline = book.bookTitle
        if let author = book.metadata.creators.first, !author.isEmpty {
            byline += " by \(author)"
        }
        if let selection {
            shareText = "“\(selection)”\n\n\(byline)"
        } else {
            shareText = byline
        }
        showShare = true
    }

    private func showTransientStatus(_ text: String) {
        transientStatusTask?.cancel()
        transientStatus = text
        transientStatusTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            self?.transientStatus = nil
        }
    }

    func readerDidDisappear() {
        paginator.cancel()
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
        if bookmarks.contains(where: { $0.uuid == uuid }) {
            bookmarks.removeAll { $0.uuid == uuid }
            currentPageBookmarkIds.removeAll { $0 == uuid }
        }
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
