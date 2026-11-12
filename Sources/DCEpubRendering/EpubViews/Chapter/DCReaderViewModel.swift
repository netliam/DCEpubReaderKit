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
    /// Line spacing, margins and justification.
    @Published var textLayout: DCTextLayout
    /// Custom theme colors, by theme and palette (see `DCThemeColorStore`).
    @Published var themeColors: [String: DCThemeColors]
    /// Rotation lock (see `DCReaderOrientationLock`); applied when it changes and while the reader is open.
    @Published var rotationLock: Bool {
        didSet { if rotationLock != oldValue { DCReaderOrientationLock.setLocked(rotationLock, scene: windowScene) } }
    }
    /// The window the reader is in (set by the view), for the rotation lock and brightness. Several
    /// windows can be open on iPad and Mac, so "the first scene" may be another one.
    weak var windowScene: UIWindowScene? {
        didSet {
            guard windowScene !== oldValue else { return }
            if rotationLock { DCReaderOrientationLock.setLocked(true, scene: windowScene) }
        }
    }
    let configuration: DCReaderConfiguration
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

    /// Whether the full reader controls are showing. Like Books, they're hidden while reading and
    /// toggled by tapping the page; turning the page hides them again.
    @Published var isChromeVisible: Bool = false
    @Published var showContents: Bool = false
    @Published var showShare: Bool = false
    /// What the share sheet shares: title and author, plus the selected text if any.
    @Published private(set) var shareText: String = ""
    /// Briefly replaces the "pages left" label (e.g. "Line Guide: On").
    @Published private(set) var transientStatus: String?
    /// The book's bookmarks, loaded when the reader opens and kept in sync as they are added/removed.
    @Published private(set) var bookmarks: [DCHighlight] = []
    /// Page (0-based, within its chapter) of TOC anchors and saved marks, from the background count.
    @Published private(set) var locatedPages: [DCBookPaginator.LocatedPlace: Int] = [:]
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
    /// Set when a jump changes the chapter, so `handleSelectionDidChange` leaves its position alone.
    private var selectionChangeIsJump = false
    /// Paged (horizontal) reader, set when it is created.
    weak var pagedNavigator: DCPagedReaderNavigating?
    /// Created lazily so books that are never searched don't pay for text extraction. Kept for the
    /// reader's lifetime so the query and results survive closing the search sheet.
    private(set) lazy var searchViewModel: DCSearchViewModel = {
        let searchViewModel = DCSearchViewModel(
            engine: DCEpubSearchEngine(book: book),
            pageNumber: { [weak self] result in self?.bookPage(for: result) }
        ) { [weak self] result, query in
            self?.navigate(to: result, query: query)
        }
        searchViewModel.onResults = { [weak self] results, query in
            self?.paginator.locateSearch(results.map {
                DCBookPaginator.SearchPlace(query: query, spineIndex: $0.spineIndex, occurrence: $0.occurrence)
            })
        }
        createdSearchViewModel = searchViewModel
        return searchViewModel
    }()
    /// The search view model once it exists, so page updates don't create it.
    private weak var createdSearchViewModel: DCSearchViewModel?
    /// Exact pages of the last search's matches (see `DCBookPaginator.locateSearch`).
    private var searchPages: [DCBookPaginator.SearchPlace: Int] = [:]
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
    /// Every highlight, note and bookmark, so the background count can find their pages.
    private var allMarks: [DCHighlight] = []
    /// Pages of marks made since the last count (on the page on screen), keyed by uuid.
    private var recentMarkPages: [String: (spineIndex: Int, page: Int)] = [:]
    /// The background count waits for the marks, so it can locate them while laying out each chapter.
    private var marksLoaded = false
    private var pendingLayout: DCBookPaginator.Layout?

    public init(book: DCEpubBook,
                spineIndex: Int,
                initialCoords: String? = nil,
                userPreferencesProtocol: DCUserPreferencesProtocol,
                delegate: DCReaderCoordsProtocol?,
                configuration: DCReaderConfiguration = DCReaderConfiguration()) {
        self.configuration = configuration
        self.book = book
        self.spineIndex = spineIndex
        self.initialCoords = initialCoords
        self.userPreferencesProtocol = userPreferencesProtocol
        self.delegate = delegate

        // Initial values
        self.currentSelection = spineIndex
        self.previousSelection = spineIndex
        self.textSize = userPreferencesProtocol.getFontSize().size
        self.textFont = userPreferencesProtocol.getFontChoice()
        self.themeColors = userPreferencesProtocol.getThemeColors()
        self.textLayout = userPreferencesProtocol.getTextLayout()
        self.rotationLock = userPreferencesProtocol.getRotationLock()
        self.theme = userPreferencesProtocol.getTheme().rawValue
        self.followsSystemAppearance = userPreferencesProtocol.getFollowsSystemAppearance()
        self.orientation = userPreferencesProtocol.getBookOrientation().rawValue
        self.pageTransition = userPreferencesProtocol.getPageTransition().rawValue
        self.lineFocus = userPreferencesProtocol.getLineFocus() && configuration.showsLineGuide
        self.lineFocusStyle = userPreferencesProtocol.getLineFocusStyle().rawValue

        // Defaults
        self.totalPages = 1
        self.currentPage = 1
        self.canTouch = true
        self.showSettings = false
        self.showContents = false
        self.paginator = DCBookPaginator(book: book, userPreferences: userPreferencesProtocol,
                                         fonts: configuration.fonts)
        paginator.locators = { [weak self] spineIndex in
            self?.locators(in: spineIndex) ?? []
        }
        paginator.onChange = { [weak self] in
            guard let self else { return }
            self.bookPageCounts = self.paginator.pageCounts
            self.locatedPages = self.paginator.locatedPages
            if self.searchPages != self.paginator.searchPages {
                self.searchPages = self.paginator.searchPages
                self.createdSearchViewModel?.pagesDidChange()
            }
            if self.paginator.isComplete {
                self.lastCompleteBookPageCounts = self.paginator.pageCounts
            }
        }
    }

    var bookId: String {
        configuration.bookId ?? book.uniqueIdentifier
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
        "\(idx)-\(textFont)-\(appearance.theme.fontWeight)-\(textSize)-\(textLayout.id)-\(orientation)-\(lineFocus)-\(lineFocusStyle)"
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
        case 0: return L("Last page in chapter")
        case 1: return L("1 page left in chapter")
        default: return String(format: L("%lld pages left in chapter"), left)
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

    // MARK: Scrubber

    /// Where the progress scrubber points: a page of a chapter, and the whole-book page once counted.
    struct ScrubTarget: Equatable {
        let spineIndex: Int
        /// 0-based, in the chapter.
        let pageIndex: Int
        let bookPage: Int?
        let bookTotal: Int?
    }

    /// The page at `fraction` (0...1) of the book. Until every chapter is counted, the scrubber
    /// moves by chapter, to the start of each.
    nonisolated static func scrubTarget(fraction: Double, counts: [Int: Int]?, chapterCount: Int) -> ScrubTarget {
        let fraction = min(max(fraction, 0), 1)
        let lastChapter = max(chapterCount - 1, 0)
        let total = counts.map { counts in (0..<chapterCount).reduce(0) { $0 + max(counts[$1] ?? 0, 0) } } ?? 0
        guard let counts, total > 0 else {
            let spineIndex = min(Int(fraction * Double(chapterCount)), lastChapter)
            return ScrubTarget(spineIndex: spineIndex, pageIndex: 0, bookPage: nil, bookTotal: nil)
        }
        let page = 1 + Int((fraction * Double(total - 1)).rounded())
        var remaining = page
        for index in 0..<chapterCount {
            let pages = max(counts[index] ?? 0, 0)
            if remaining <= pages {
                return ScrubTarget(spineIndex: index, pageIndex: remaining - 1, bookPage: page, bookTotal: total)
            }
            remaining -= pages
        }
        return ScrubTarget(spineIndex: lastChapter, pageIndex: max((counts[lastChapter] ?? 1) - 1, 0),
                           bookPage: total, bookTotal: total)
    }

    /// The scrubber's position for the page on screen; `scrubTarget` maps it back to this page.
    var scrubberFraction: Double {
        if let position = bookPagePosition {
            return position.total > 1 ? Double(position.page - 1) / Double(position.total - 1) : 0
        }
        return readingProgress
    }

    func scrubTarget(at fraction: Double) -> ScrubTarget {
        Self.scrubTarget(fraction: fraction,
                         counts: Self.estimatedPageCounts(current: bookPageCounts,
                                                          previous: lastCompleteBookPageCounts,
                                                          chapterCount: book.spine.count,
                                                          currentChapter: (currentSelection, totalPages)),
                         chapterCount: book.spine.count)
    }

    /// The chapter title shown above the scrubber while dragging.
    func scrubTitle(for target: ScrubTarget) -> String {
        book.chapterTitle(forSpineIndex: target.spineIndex) ?? String(format: L("Chapter %lld"), target.spineIndex + 1)
    }

    /// "Page 415 of 832", or the chapter while the book is still being counted.
    func scrubDetail(for target: ScrubTarget) -> String {
        if let page = target.bookPage, let total = target.bookTotal {
            return String(format: L("Page %lld of %lld"), page, total)
        }
        return String(format: L("Chapter %lld of %lld"), target.spineIndex + 1, max(book.spine.count, 1))
    }

    /// Opens the page the scrubber was released on.
    @MainActor
    func jump(to target: ScrubTarget) {
        if target.spineIndex == currentSelection, target.pageIndex == currentPage - 1 { return }
        rememberPositionBeforeJump()
        if isPagedMode {
            pagedNavigator?.show(spineIndex: target.spineIndex, page: target.pageIndex)
        } else {
            navigate(to: .page(target.pageIndex), in: target.spineIndex)
        }
    }

    // MARK: Back

    /// The page the reader was on before the last jump (scrubber, Contents, a mark or a search
    /// result), for the "Back to Page N" button.
    struct BackPosition: Equatable {
        let spineIndex: Int
        /// The saved position of that page, which survives a relayout; else its page index.
        let coords: String?
        /// 0-based, in the chapter.
        let pageIndex: Int
        let bookPage: Int?
        /// The layout `bookPage` was counted in.
        var layoutId: String = ""
    }

    @Published private(set) var backPosition: BackPosition?

    private func rememberPositionBeforeJump() {
        guard hasPagePosition else { return }
        let coords = lastPosition?.spineIndex == currentSelection ? lastPosition?.coords : nil
        backPosition = BackPosition(spineIndex: currentSelection,
                                    coords: coords,
                                    pageIndex: max(currentPage - 1, 0),
                                    bookPage: bookPagePosition?.page,
                                    layoutId: pagedConfigId + orientation)
    }

    /// "Back to Page 12", or to the chapter while the book is being counted. `nil` when there's
    /// nowhere to go back to, or the reader is already on that page.
    var backButtonTitle: String? {
        guard let back = backPosition else { return nil }
        // After a relayout the page number it was saved with is stale; name the chapter instead.
        let isSameLayout = back.layoutId == pagedConfigId + orientation
        let isOnBackPage = back.spineIndex == currentSelection && back.pageIndex == currentPage - 1
        if isSameLayout, isOnBackPage { return nil }
        if let page = back.bookPage, isSameLayout {
            return String(format: L("Back to Page %lld"), page)
        }
        return String(format: L("Back to %@"), book.chapterTitle(forSpineIndex: back.spineIndex) ?? String(format: L("Chapter %lld"), back.spineIndex + 1))
    }

    /// Returns to the page before the last jump.
    @MainActor
    func goBack() {
        guard let back = backPosition else { return }
        backPosition = nil
        if let coords = back.coords {
            if isPagedMode {
                pagedNavigator?.show(spineIndex: back.spineIndex, coords: coords)
            } else {
                navigate(to: .coords(coords), in: back.spineIndex)
            }
        } else if isPagedMode {
            pagedNavigator?.show(spineIndex: back.spineIndex, page: back.pageIndex)
        } else {
            navigate(to: .page(back.pageIndex), in: back.spineIndex)
        }
    }

    /// VoiceOver's adjustable action on the scrubber: the start of the next or previous chapter.
    @MainActor
    func jumpChapter(by offset: Int) {
        let spineIndex = min(max(currentSelection + offset, 0), max(book.spine.count - 1, 0))
        jump(to: ScrubTarget(spineIndex: spineIndex, pageIndex: 0, bookPage: nil, bookTotal: nil))
    }

    /// "415 of 832", or the chapter while the book is still being counted.
    var progressText: String {
        if let position = bookPagePosition {
            return "\(position.page) of \(position.total)"
        }
        return String(format: L("Chapter %lld of %lld"), currentSelection + 1, max(book.spine.count, 1))
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

    /// Shown at the top while reading (controls hidden): a transient status, else the chapter title.
    var readingTitle: String {
        transientStatus ?? book.chapterTitle(forSpineIndex: currentSelection) ?? bookTitle
    }

    /// Shown at the bottom while reading: just the whole-book page number, once known.
    var readingPageText: String {
        bookPagePosition.map { "\($0.page)" } ?? ""
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
        "\(textFont)-\(appearance.theme.fontWeight)-\(textSize)-\(textLayout.id)-\(pageTransition)"
    }

    /// Coords to open `spineIndex` at: the last reported position, else the initial coords.
    func resumeCoords(for spineIndex: Int) -> String? {
        if let lastPosition, lastPosition.spineIndex == spineIndex {
            return lastPosition.coords
        }
        return initialCoords(for: spineIndex)
    }

    /// The theme's light or dark palette, depending on the system appearance and the setting, with
    /// any custom colors set in Customize.
    var appearance: DCReaderAppearance {
        let theme = DCReaderTheme(rawValue: theme) ?? .original
        let isDark = followsSystemAppearance && systemIsDark
        return DCReaderAppearance(theme: theme, isDark: isDark,
                                  custom: themeColors[DCThemeColorStore.key(theme, isDark: isDark)])
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

    /// "Title by Author", as Share uses it.
    var bookByline: String {
        book.shareText(quoting: nil)
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

        case let .searchBook(query):
            searchBook(for: query)

        case let .spineDidChange(spineIndex):
            guard currentSelection != spineIndex else { return }
            currentSelection = spineIndex
            isChromeVisible = false
            currentPageBookmarkIds = []

        case .toggleChrome:
            isChromeVisible.toggle()

        case let .openLink(url):
            openLink(url)

        case let .pageLayout(size):
            pendingLayout = DCBookPaginator.Layout(pageSize: size,
                                                   isVertical: !isPagedMode,
                                                   styleId: "\(textFont)-\(textSize)-\(appearance.theme.fontWeight)-\(textLayout.id)")
            startCountingIfReady()
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

        // Turning the page puts the reader back into reading mode.
        if hasPagePosition, index != currentPage || totalPages != self.totalPages {
            isChromeVisible = false
        }
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
            if !isBookMark {
                delegate?.handleProgress(book: book, progress: progress(coords: coords))
            }
        }
    }

    /// The whole-book place for the page on screen, as the progress bar shows it.
    func progress(coords: String) -> DCReaderProgress {
        let position = bookPagePosition
        return DCReaderProgress(spineIndex: currentSelection, coords: coords,
                                fraction: min(max(readingProgress, 0), 1),
                                page: position?.page, totalPages: position?.total)
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
        // A jump positions the chapter itself; only scrolling into the previous chapter should
        // land on its last page.
        let isJump = selectionChangeIsJump
        selectionChangeIsJump = false

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
        guard !isJump else { return }

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
        allMarks = marks
        bookmarks = marks.filter { $0.type == .bookMark }
        checkCurrentPageBookmarks()
        marksLoaded = true
        startCountingIfReady()
    }

    // MARK: Page numbers

    private func startCountingIfReady() {
        guard marksLoaded, let layout = pendingLayout else { return }
        paginator.paginate(layout: layout, appearance: appearance)
    }

    /// Places in a chapter whose page the background count should find: TOC anchors and saved marks.
    private func locators(in spineIndex: Int) -> [DCBookPaginator.Locator] {
        let fragments = contentsEntries.filter { $0.spineIndex == spineIndex }.compactMap(\.fragment)
        let marks = allMarks.filter { $0.spineIndex == spineIndex && !$0.coords.isEmpty }
        return fragments.map { .fragment($0) } + marks.map { .coords($0.coords) }
    }

    /// Whole-book page of a page index in a chapter.
    private func bookPage(spineIndex: Int, pageIndex: Int) -> Int? {
        bookStartPage(of: spineIndex).map { $0 + pageIndex }
    }

    /// Page number of a Contents entry (its anchor's page, or the chapter's first page).
    func bookPage(for entry: DCContentsEntry) -> Int? {
        guard let spineIndex = entry.spineIndex else { return nil }
        guard let fragment = entry.fragment else { return bookPage(spineIndex: spineIndex, pageIndex: 0) }
        let place = DCBookPaginator.LocatedPlace(spineIndex: spineIndex, locator: .fragment(fragment))
        return locatedPages[place].flatMap { bookPage(spineIndex: spineIndex, pageIndex: $0) }
    }

    /// Page number of a bookmark, highlight or note.
    func bookPage(for mark: DCHighlight) -> Int? {
        if let recent = recentMarkPages[mark.uuid] {
            return bookPage(spineIndex: recent.spineIndex, pageIndex: recent.page)
        }
        let place = DCBookPaginator.LocatedPlace(spineIndex: mark.spineIndex, locator: .coords(mark.coords))
        return locatedPages[place].flatMap { bookPage(spineIndex: mark.spineIndex, pageIndex: $0) }
    }

    /// Page number of a search match: exact once the paginator has found it, estimated from where
    /// it falls in its chapter's text until then.
    func bookPage(for result: DCSearchResult) -> Int? {
        let place = DCBookPaginator.SearchPlace(query: searchViewModel.searchedQuery,
                                                spineIndex: result.spineIndex,
                                                occurrence: result.occurrence)
        if let page = searchPages[place] {
            return bookPage(spineIndex: result.spineIndex, pageIndex: page)
        }
        let pages = result.spineIndex == currentSelection ? totalPages : (estimatedChapterPageCount(result.spineIndex) ?? 0)
        guard pages > 0 else { return nil }
        let index = min(pages - 1, Int(result.chapterFraction * Double(pages)))
        return bookPage(spineIndex: result.spineIndex, pageIndex: index)
    }

    private func estimatedChapterPageCount(_ spineIndex: Int) -> Int? {
        Self.estimatedPageCounts(current: bookPageCounts,
                                 previous: lastCompleteBookPageCounts,
                                 chapterCount: book.spine.count,
                                 currentChapter: (currentSelection, totalPages))?[spineIndex]
    }

    /// Records the page of a mark made on the page on screen (it isn't in the last count yet).
    private func noteNewMark(_ mark: DCHighlight) {
        allMarks.removeAll { $0.uuid == mark.uuid }
        allMarks.append(mark)
        if recentMarkPages[mark.uuid] == nil, mark.spineIndex == currentSelection {
            recentMarkPages[mark.uuid] = (mark.spineIndex, currentPage - 1)
        }
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
        allMarks.removeAll { ids.contains($0.uuid) }
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
        noteNewMark(bookmark)
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
        rememberPositionBeforeJump()
        if isPagedMode {
            pagedNavigator?.show(spineIndex: highlight.spineIndex, coords: highlight.coords)
            return
        }
        navigate(to: .coords(highlight.coords), in: highlight.spineIndex)
    }

    @MainActor
    func navigate(to result: DCSearchResult, query: String) {
        showSearch = false
        rememberPositionBeforeJump()
        if isPagedMode {
            pagedNavigator?.show(spineIndex: result.spineIndex, searchQuery: query, occurrence: result.occurrence)
            return
        }
        navigate(to: .search(query: query, occurrence: result.occurrence), in: result.spineIndex)
    }

    /// Vertical reader: jump now if the chapter is loaded (the one on screen, or a neighbour the
    /// TabView keeps loaded), else once it loads (see `consumeInitialJump`).
    @MainActor
    private func navigate(to jump: DCChapterJump, in spineIndex: Int) {
        if spineIndex != currentSelection {
            selectionChangeIsJump = true
        }
        if let chapter = chapterViewModels[spineIndex], spineIndex == currentSelection || chapter.isLaidOut {
            pendingJumpsBySpineIndex[spineIndex] = nil
            chapter.jump(to: jump)
        } else {
            pendingJumpsBySpineIndex[spineIndex] = jump
        }
        currentSelection = spineIndex
    }

    /// Follows a link in the book: to its chapter and `#fragment`, with Back to return. Links out
    /// of the book open in the browser.
    @MainActor
    func openLink(_ url: URL) {
        guard url.isFileURL else {
            if ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") {
                if let open = configuration.onOpenExternalURL { open(url) } else { UIApplication.shared.open(url) }
            }
            return
        }
        guard let spineIndex = book.spineIndex(forChapterURL: url) else { return }
        let fragment = url.fragment.flatMap { $0.isEmpty ? nil : $0 }
        rememberPositionBeforeJump()
        if isPagedMode {
            pagedNavigator?.show(spineIndex: spineIndex, fragment: fragment)
        } else {
            navigate(to: fragment.map { .fragment($0) } ?? .page(0), in: spineIndex)
        }
    }

    /// Opens a table-of-contents entry at its chapter (and `#fragment`, if it has one).
    @MainActor
    func navigate(to entry: DCContentsEntry) {
        showContents = false
        guard let spineIndex = entry.spineIndex else { return }
        rememberPositionBeforeJump()
        if isPagedMode {
            pagedNavigator?.show(spineIndex: spineIndex, fragment: entry.fragment)
        } else {
            // The start of the chapter, even when it's an earlier one.
            navigate(to: entry.fragment.map { .fragment($0) } ?? .page(0), in: spineIndex)
        }
    }

    private(set) lazy var contentsEntries: [DCContentsEntry] = DCContentsEntry.entries(for: book)

    // MARK: Menu actions

    func toggleLineFocus() {
        let isOn = !lineFocus
        userPreferences.setValue(key: .lineFocus, type: isOn)
        lineFocus = isOn
        showTransientStatus(isOn ? L("Line Guide: On") : L("Line Guide: Off"))
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
        shareText = book.shareText(quoting: selection)
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

    func readerDidAppear() {
        if rotationLock {
            DCReaderOrientationLock.setLocked(true, scene: windowScene)
        }
    }

    func readerDidDisappear() {
        paginator.cancel()
        // The lock is for reading; the rest of the app turns freely.
        DCReaderOrientationLock.setLocked(false, scene: windowScene)
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
        // The chapter on screen reloads after a layout change (mode, text size, spacing): resume at
        // the last reported position, as the paged reader does, else where the book was opened.
        guard spineIndex == currentSelection else { return nil }
        guard chapterURL == book.chapterURL(forSpineIndex: spineIndex) else { return nil }
        guard let coords = resumeCoords(for: spineIndex), !coords.isEmpty else { return nil }
        return .coords(coords)
    }

    func showNote(highlight: DCHighlight) {
        pendingNoteHighlight = highlight
        showNote = true
    }

    /// Opens the search sheet already searching for `query`.
    func searchBook(for query: String) {
        searchViewModel.query = query
        searchViewModel.queryDidChange()
        showSearch = true
    }

    func save(highlight: DCHighlight) async {
        var highlight = highlight
        // Highlights are created by the page, which doesn't know the chapter's title; lists show it.
        if highlight.chapterTitle.isEmpty {
            highlight.chapterTitle = book.chapterTitle(forSpineIndex: highlight.spineIndex) ?? ""
        }
        noteNewMark(highlight)
        NotificationCenter.default.post(name: .dcHighlightDidChange, object: self,
                                        userInfo: [DCHighlight.notificationKey: highlight])
        await delegate?.save(highlight: highlight)
    }

    func deleteHighlight(uuid: String) async {
        await delegate?.deleteHighlight(uuid: uuid, book: book)
        allMarks.removeAll { $0.uuid == uuid }
        recentMarkPages[uuid] = nil
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

extension DCEpubBook {
    /// What Share sends: the quoted passage, if any, then "Title by Author".
    func shareText(quoting passage: String?) -> String {
        var byline = bookTitle
        if let author = metadata.creators.first, !author.isEmpty {
            byline += " by \(author)"
        }
        guard let passage, !passage.isEmpty else { return byline }
        return "“\(passage)”\n\n\(byline)"
    }
}
