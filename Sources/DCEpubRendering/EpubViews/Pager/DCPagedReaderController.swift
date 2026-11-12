//
//  DCPagedReaderController.swift
//  DCEpubReaderKit
//
//  Created by Liam Smith-Gales on 11/11/26.
//

import SwiftUI
import DCEpubCore

/// Commands the reader view model sends to the paged reader.
@MainActor
protocol DCPagedReaderNavigating: AnyObject {
    func show(spineIndex: Int, coords: String?)
    func show(spineIndex: Int, searchQuery: String, occurrence: Int)
    func show(spineIndex: Int, fragment: String?)
    /// Shows a page (0-based) of a chapter, clamped to the chapter's pages.
    func show(spineIndex: Int, page: Int)
    /// Text the reader has selected on the current page, if any.
    func selectedText() async -> String?
    /// Page (0-based, in its chapter) that a saved position falls on, using the page on screen.
    func pageIndex(forCoords coords: String) async -> Int?
    func saveBookmark()
}

/// Horizontal reader built on `UIPageViewController`, one `DCPageWebViewController` per page.
///
/// The pages before and after the current one are created ahead of time and parked in a hidden
/// container behind the page view controller, so their web views have loaded and paginated by the
/// time a page turn starts. The transition style can't change after init, so changing it (or any
/// layout-affecting setting) rebuilds the page view controller at the current reading position.
final class DCPagedReaderController: UIViewController {

    private enum Constants {
        /// Width of the page-turning tap zones at each edge, as a fraction of the page.
        static let edgeTapFraction: CGFloat = 0.2
    }

    private let book: DCEpubBook
    private let userPreferences: DCUserPreferencesProtocol
    private let readerContext: any DCChapterReaderContextProtocol
    private let onAction: (DCChapterViewAction, URL?) -> Void

    private(set) var pageViewController: UIPageViewController?
    /// Hosts preloaded pages off screen (behind the opaque page view controller) so they lay out and render.
    private let preloadContainer = UIView()
    /// Current page plus its preloaded neighbours.
    private var cachedPages: [DCPageWebViewController] = []
    /// Web views from pages that left the cache, reused by the next pages created.
    private var recycledWebViews: [DCPageWebViewController.RecycledWebView] = []
    private let maxRecycledWebViews = 2
    /// Page count per spine index for the current layout. Lets the data source answer page turns
    /// before the current page has finished paginating (e.g. when flipping quickly).
    private var pageCounts: [Int: Int] = [:]

    private var configId: String
    private var appearance: DCReaderAppearance
    private var lineFocusEnabled: Bool
    private var lineFocusStyle: DCLineFocusStyle
    /// Start position waiting for the first layout pass.
    private var pendingStart: (spineIndex: Int, target: DCPageTarget)?
    private var lastLayoutSize: CGSize = .zero
    private var reloadTask: Task<Void, Never>?

    init(book: DCEpubBook,
         spineIndex: Int,
         coords: String?,
         configId: String,
         appearance: DCReaderAppearance,
         userPreferences: DCUserPreferencesProtocol,
         readerContext: any DCChapterReaderContextProtocol,
         onAction: @escaping (DCChapterViewAction, URL?) -> Void) {
        self.book = book
        self.configId = configId
        self.appearance = appearance
        self.lineFocusEnabled = userPreferences.getLineFocus() && readerContext.configuration.showsLineGuide
        self.lineFocusStyle = userPreferences.getLineFocusStyle()
        self.userPreferences = userPreferences
        self.readerContext = readerContext
        self.onAction = onAction
        self.pendingStart = (spineIndex, Self.target(for: coords))
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var currentPage: DCPageWebViewController? {
        pageViewController?.viewControllers?.first as? DCPageWebViewController
    }

    private var backgroundColor: UIColor {
        appearance.uiBackgroundColor
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = backgroundColor
        preloadContainer.frame = view.bounds
        preloadContainer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        preloadContainer.isUserInteractionEnabled = false
        view.addSubview(preloadContainer)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleChromeTap(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        view.addGestureRecognizer(tap)

        // Holding a finger down selects text; it mustn't also count as a tap when it lifts.
        let press = UILongPressGestureRecognizer(target: nil, action: nil)
        press.minimumPressDuration = 0.3
        press.cancelsTouchesInView = false
        press.delegate = self
        view.addGestureRecognizer(press)
        tap.require(toFail: press)

        // Two-finger trackpad (and mouse wheel) swipes turn the page; touches are left to the pager.
        let trackpad = UIPanGestureRecognizer(target: self, action: #selector(handleTrackpadSwipe(_:)))
        trackpad.allowedScrollTypesMask = .continuous
        trackpad.allowedTouchTypes = []
        view.addGestureRecognizer(trackpad)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // So the page keys work before anything else (a selection) has taken the keyboard.
        becomeFirstResponder()
    }

    override var canBecomeFirstResponder: Bool { true }

    /// ← → space ⇧space Page Up/Down turn the page, as in Books on Mac and iPad.
    override var keyCommands: [UIKeyCommand]? {
        let keys: [(String, UIKeyModifierFlags, Selector)] = [
            (UIKeyCommand.inputRightArrow, [], #selector(nextPage)),
            (UIKeyCommand.inputLeftArrow, [], #selector(previousPage)),
            (" ", [], #selector(nextPage)),
            (" ", .shift, #selector(previousPage)),
            (UIKeyCommand.inputPageDown, [], #selector(nextPage)),
            (UIKeyCommand.inputPageUp, [], #selector(previousPage))
        ]
        return keys.map { input, modifiers, action in
            let command = UIKeyCommand(input: input, modifierFlags: modifiers, action: action)
            // Before the web view's own handling (scrolling, which pages don't use).
            command.wantsPriorityOverSystemBehavior = true
            return command
        }
    }

    @objc private func nextPage() { turnPage(forward: true) }
    @objc private func previousPage() { turnPage(forward: false) }

    @objc private func handleTrackpadSwipe(_ recognizer: UIPanGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        let translation = recognizer.translation(in: view)
        guard abs(translation.x) > max(40, abs(translation.y)) else { return }
        // Content follows the fingers: swiping left brings in the next page.
        turnPage(forward: translation.x < 0)
    }

    /// Taps near the left/right edge turn the page; a tap anywhere else toggles the reader controls.
    /// (The page view controller's own edge taps never fire: the web view takes the touch.)
    @objc private func handleChromeTap(_ recognizer: UITapGestureRecognizer) {
        let point = recognizer.location(in: view)
        Task { @MainActor [weak self] in
            guard let self else { return }
            // A tap on a highlight opens its menu; it isn't also a page tap.
            if await DCWebView.hasHighlight(at: point, in: self.view) { return }
            self.handlePageTap(at: point)
        }
    }

    private func handlePageTap(at point: CGPoint) {
        let x = point.x / max(view.bounds.width, 1)
        if x > 1 - Constants.edgeTapFraction {
            turnPage(forward: true)
        } else if x < Constants.edgeTapFraction {
            turnPage(forward: false)
        } else {
            onAction(.toggleChrome, nil)
        }
    }

    private var isTurningPage = false

    /// Turns the page with the current transition (curl or slide), like a swipe would.
    private func turnPage(forward: Bool) {
        guard !isTurningPage, let pageViewController, let current = currentPage else { return }
        let next = forward
            ? self.pageViewController(pageViewController, viewControllerAfter: current)
            : self.pageViewController(pageViewController, viewControllerBefore: current)
        guard let next else { return }
        isTurningPage = true
        pageViewController.setViewControllers([next], direction: forward ? .forward : .reverse, animated: true) { [weak self] _ in
            // Programmatic turns don't call didFinishAnimating, so settle here.
            self?.isTurningPage = false
            self?.currentPageDidSettle()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let size = view.bounds.size
        guard size.width > 0, size.height > 0, size != lastLayoutSize else { return }
        let isFirstLayout = lastLayoutSize == .zero
        lastLayoutSize = size

        if isFirstLayout, let start = pendingStart {
            pendingStart = nil
            rebuild(spineIndex: start.spineIndex, target: start.target)
        } else if !isFirstLayout {
            // Page counts depend on the page size (rotation, split view), so paginate again.
            reload()
        }
    }

    // MARK: - Configuration

    /// Rebuilds the pages when a setting that affects layout or the transition style changes, and
    /// recolors the existing pages when only the theme's colors change.
    func apply(configId: String, appearance: DCReaderAppearance) {
        let appearanceChanged = appearance != self.appearance
        self.appearance = appearance
        view.backgroundColor = backgroundColor
        pageViewController?.view.backgroundColor = backgroundColor
        if configId != self.configId {
            self.configId = configId
            reload()
        } else if appearanceChanged {
            let hosted = pageViewController?.children.compactMap { $0 as? DCPageWebViewController } ?? []
            for page in cachedPages + hosted.filter({ page in !cachedPages.contains { $0 === page } }) {
                page.updateAppearance(appearance)
            }
            // Recycled web views still carry the old colors; let new pages load fresh ones.
            recycledWebViews = []
        }
    }

    /// Turns line focus on, off or to another style on the pages that already exist, without reloading.
    func applyLineFocus(enabled: Bool, style: DCLineFocusStyle) {
        guard enabled != lineFocusEnabled || style != lineFocusStyle else { return }
        lineFocusEnabled = enabled
        lineFocusStyle = style
        let hosted = pageViewController?.children.compactMap { $0 as? DCPageWebViewController } ?? []
        for page in cachedPages + hosted.filter({ page in !cachedPages.contains { $0 === page } }) {
            page.updateLineFocus(enabled: enabled, style: style)
        }
        for recycled in recycledWebViews {
            recycled.webView.setLineFocus(enabled: enabled, appearance: appearance, style: style,
                                          textTrailingInset: DCReaderChrome.columnGap)
        }
    }

    private static func target(for coords: String?) -> DCPageTarget {
        guard let coords, !coords.isEmpty else { return .index(0) }
        return .coords(coords)
    }

    private static func transitionStyle(for transition: DCPageTransition) -> UIPageViewController.TransitionStyle {
        switch transition {
        case .curl:
            return .pageCurl
        case .slide:
            return .scroll
        }
    }

    /// Recreates the page view controller at the current reading position.
    private func reload() {
        reloadTask?.cancel()
        guard let current = currentPage else { return }
        let spineIndex = current.spineIndex
        let fallbackTarget = current.target
        reloadTask = Task { [weak self] in
            // A window being resized lays out many times; relayout once it settles.
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            // Still on the page a previous relayout opened: keep that anchor. Re-reading it from the
            // relaid-out page would drift (e.g. bigger then smaller text ending a page earlier).
            if case .coords = fallbackTarget {
                guard !Task.isCancelled else { return }
                self?.rebuild(spineIndex: spineIndex, target: fallbackTarget, invalidatesLayout: true)
                return
            }
            let coords = await current.currentPageCoords()
            guard !Task.isCancelled else { return }
            self?.rebuild(spineIndex: spineIndex,
                          target: coords.map { .coords($0) } ?? fallbackTarget,
                          invalidatesLayout: true)
        }
    }

    /// - Parameter invalidatesLayout: Settings or page size changed, so page counts and loaded web
    ///   views no longer match the new layout and must not be reused.
    private func rebuild(spineIndex: Int, target: DCPageTarget, invalidatesLayout: Bool = false) {
        guard lastLayoutSize != .zero else {
            pendingStart = (spineIndex, target)
            return
        }
        if let old = pageViewController {
            old.willMove(toParent: nil)
            old.view.removeFromSuperview()
            old.removeFromParent()
        }
        if invalidatesLayout {
            cachedPages.forEach(detachFromPreload)
            cachedPages = []
            recycledWebViews = []
            pageCounts = [:]
        } else {
            discardCachedPages()
        }

        let style = Self.transitionStyle(for: readerContext.configuration.allowsPageCurl ? userPreferences.getPageTransition() : .slide)
        let pageViewController = UIPageViewController(transitionStyle: style,
                                                      navigationOrientation: .horizontal)
        pageViewController.dataSource = self
        pageViewController.delegate = self
        // Edge taps are handled by `handleChromeTap`; the built-in ones would double-turn if they fired.
        pageViewController.gestureRecognizers
            .filter { $0 is UITapGestureRecognizer }
            .forEach { $0.isEnabled = false }
        pageViewController.view.backgroundColor = backgroundColor

        addChild(pageViewController)
        pageViewController.view.frame = view.bounds
        pageViewController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(pageViewController.view)
        pageViewController.didMove(toParent: self)
        self.pageViewController = pageViewController

        let page = makePage(spineIndex: spineIndex, target: target)
        cachedPages = [page]
        pageViewController.setViewControllers([page], direction: .forward, animated: false)
        onAction(.canTouch(enable: false), page.chapterURL)
        onAction(.spineDidChange(spineIndex: spineIndex), page.chapterURL)
    }

    // MARK: - Pages

    private func makePage(spineIndex: Int, target: DCPageTarget) -> DCPageWebViewController {
        let chapterURL = book.chapterURL(forSpineIndex: spineIndex)
        let page = DCPageWebViewController(
            book: book,
            spineIndex: spineIndex,
            target: target,
            userPreferences: userPreferences,
            readerContext: readerContext,
            appearance: appearance,
            recycled: takeRecycledWebView(preferring: spineIndex)
        ) { [weak self] action in
            self?.onAction(action, chapterURL)
        }
        page.delegate = self
        return page
    }

    /// Spine index and target of the page after `page`, or `nil` at the end of the book
    /// (or while `page` is still paginating and its chapter's page count isn't known yet).
    private func spec(after page: DCPageWebViewController) -> (spineIndex: Int, target: DCPageTarget)? {
        guard let pageCount = page.pageCount ?? pageCounts[page.spineIndex],
              let pageIndex = page.expectedPageIndex(knownPageCount: pageCount) else { return nil }
        if pageIndex + 1 < pageCount {
            return (page.spineIndex, .index(pageIndex + 1))
        }
        guard page.spineIndex + 1 < book.spine.count else { return nil }
        return (page.spineIndex + 1, .index(0))
    }

    /// Spine index and target of the page before `page`, or `nil` at the start of the book.
    private func spec(before page: DCPageWebViewController) -> (spineIndex: Int, target: DCPageTarget)? {
        guard let pageIndex = page.expectedPageIndex(knownPageCount: pageCounts[page.spineIndex]) else { return nil }
        if pageIndex > 0 {
            return (page.spineIndex, .index(pageIndex - 1))
        }
        guard page.spineIndex > 0 else { return nil }
        // A concrete index (when known) matches already-loaded pages; `.last` is resolved on load.
        let previousSpine = page.spineIndex - 1
        return (previousSpine, pageCounts[previousSpine].map { .index($0 - 1) } ?? .last)
    }

    /// Returns a cached page for the spec (detaching it from the preload container) or a new one.
    private func dequeuePage(spineIndex: Int, target: DCPageTarget) -> DCPageWebViewController {
        if let cached = cachedPages.first(where: { $0.matches(spineIndex: spineIndex, target: target) }) {
            detachFromPreload(cached)
            return cached
        }
        let page = makePage(spineIndex: spineIndex, target: target)
        cachedPages.append(page)
        return page
    }

    private func attachToPreload(_ page: DCPageWebViewController) {
        addChild(page)
        page.view.frame = preloadContainer.bounds
        page.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        preloadContainer.addSubview(page.view)
        page.didMove(toParent: self)
        // Lay out now so the page starts loading at its final size.
        page.view.layoutIfNeeded()
    }

    private func detachFromPreload(_ page: DCPageWebViewController) {
        // Pages handed to the page view controller are re-parented by it; only release our own.
        guard page.parent === self else { return }
        page.willMove(toParent: nil)
        page.view.removeFromSuperview()
        page.removeFromParent()
    }

    /// Releases every cached page, keeping their web views for reuse.
    private func discardCachedPages() {
        for page in cachedPages {
            detachFromPreload(page)
            recycle(page)
        }
        cachedPages = []
    }

    private func recycle(_ page: DCPageWebViewController) {
        guard let recycled = page.relinquishWebView() else { return }
        recycledWebViews.insert(recycled, at: 0)
        if recycledWebViews.count > maxRecycledWebViews {
            recycledWebViews.removeLast(recycledWebViews.count - maxRecycledWebViews)
        }
    }

    /// A recycled web view, preferring one already showing `spineIndex` (which skips loading entirely).
    private func takeRecycledWebView(preferring spineIndex: Int) -> DCPageWebViewController.RecycledWebView? {
        guard !recycledWebViews.isEmpty else { return nil }
        let index = recycledWebViews.firstIndex { $0.spineIndex == spineIndex } ?? 0
        return recycledWebViews.remove(at: index)
    }

    /// Preloads the neighbours of `current` and drops pages that are no longer adjacent.
    private func preloadNeighbours(of current: DCPageWebViewController) {
        var keep: [DCPageWebViewController] = [current]
        let specs = [spec(before: current), spec(after: current)].compactMap { $0 }
        for spec in specs {
            if let cached = cachedPages.first(where: { $0.matches(spineIndex: spec.spineIndex, target: spec.target) }) {
                keep.append(cached)
            } else {
                let page = makePage(spineIndex: spec.spineIndex, target: spec.target)
                attachToPreload(page)
                keep.append(page)
            }
        }

        // Pages the page view controller is still holding (e.g. scroll-style neighbours) stay alive.
        let hosted = pageViewController?.children.compactMap { $0 as? DCPageWebViewController } ?? []
        for page in hosted where !keep.contains(where: { $0 === page }) {
            keep.append(page)
        }
        for page in cachedPages where !keep.contains(where: { $0 === page }) {
            detachFromPreload(page)
            recycle(page)
        }
        cachedPages = keep
    }

    // MARK: - Reporting

    /// Reports the current page and its reading position, then preloads its neighbours.
    private func currentPageDidSettle() {
        guard let current = currentPage else { return }
        let chapterURL = current.chapterURL
        onAction(.spineDidChange(spineIndex: current.spineIndex), chapterURL)

        guard let pageIndex = current.pageIndex, let pageCount = current.pageCount else {
            // Still paginating; `pageDidLoad` finishes the job.
            onAction(.canTouch(enable: false), chapterURL)
            return
        }
        onAction(.canTouch(enable: true), chapterURL)
        onAction(.currentPage(index: pageIndex + 1, totalPages: pageCount, spineIndex: current.spineIndex),
                 chapterURL)
        preloadNeighbours(of: current)

        Task { [weak self, weak current] in
            guard let current, let coords = await current.currentPageCoords() else { return }
            self?.onAction(.coordsFirstNodeOfPage(orientation: .horizontal,
                                                  spineIndex: current.spineIndex,
                                                  coords: coords,
                                                  isBookMark: false),
                           chapterURL)
        }
    }
}

// MARK: - DCPagedReaderNavigating

extension DCPagedReaderController: DCPagedReaderNavigating {
    func show(spineIndex: Int, coords: String?) {
        reloadTask?.cancel()
        rebuild(spineIndex: spineIndex, target: Self.target(for: coords))
    }

    func show(spineIndex: Int, searchQuery: String, occurrence: Int) {
        reloadTask?.cancel()
        rebuild(spineIndex: spineIndex, target: .search(query: searchQuery, occurrence: occurrence))
    }

    func show(spineIndex: Int, fragment: String?) {
        reloadTask?.cancel()
        rebuild(spineIndex: spineIndex, target: fragment.map { .fragment($0) } ?? .index(0))
    }

    func show(spineIndex: Int, page: Int) {
        reloadTask?.cancel()
        rebuild(spineIndex: spineIndex, target: .index(max(0, page)))
    }

    func selectedText() async -> String? {
        await currentPage?.selectedText()
    }

    func pageIndex(forCoords coords: String) async -> Int? {
        await currentPage?.pageIndex(forCoords: coords)
    }

    func saveBookmark() {
        guard let current = currentPage else { return }
        let chapterURL = current.chapterURL
        Task { [weak self] in
            guard let coords = await current.currentPageCoords() else { return }
            self?.onAction(.coordsFirstNodeOfPage(orientation: .horizontal,
                                                  spineIndex: current.spineIndex,
                                                  coords: coords,
                                                  isBookMark: true),
                           chapterURL)
        }
    }
}

// MARK: - UIPageViewControllerDataSource

extension DCPagedReaderController: UIPageViewControllerDataSource {
    func pageViewController(_ pageViewController: UIPageViewController,
                            viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let page = viewController as? DCPageWebViewController,
              let spec = spec(before: page) else { return nil }
        return dequeuePage(spineIndex: spec.spineIndex, target: spec.target)
    }

    func pageViewController(_ pageViewController: UIPageViewController,
                            viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let page = viewController as? DCPageWebViewController,
              let spec = spec(after: page) else { return nil }
        return dequeuePage(spineIndex: spec.spineIndex, target: spec.target)
    }
}

// MARK: - UIPageViewControllerDelegate

extension DCPagedReaderController: UIPageViewControllerDelegate {
    func pageViewController(_ pageViewController: UIPageViewController,
                            didFinishAnimating finished: Bool,
                            previousViewControllers: [UIViewController],
                            transitionCompleted completed: Bool) {
        guard completed else { return }
        currentPageDidSettle()
    }
}

// MARK: - DCPageWebViewControllerDelegate

extension DCPagedReaderController: DCPageWebViewControllerDelegate {
    func pageDidLoad(_ page: DCPageWebViewController) {
        if let pageCount = page.pageCount {
            pageCounts[page.spineIndex] = pageCount
        }
        guard page === currentPage else { return }
        currentPageDidSettle()
        // The scroll style caches "no neighbour" answers given while the page was still paginating;
        // setting the same page again makes it ask the data source again.
        if let pageViewController, pageViewController.transitionStyle == .scroll {
            pageViewController.setViewControllers([page], direction: .forward, animated: false)
        }
    }

    func page(_ page: DCPageWebViewController, didSave highlight: DCHighlight) {
        for sibling in cachedPages where sibling !== page && sibling.spineIndex == page.spineIndex {
            sibling.applyHighlight(highlight)
        }
        // Recycled web views keep their DOM, so they must stay in sync too.
        for recycled in recycledWebViews where recycled.spineIndex == page.spineIndex {
            Task { await recycled.webView.applyHighlight(highlight) }
        }
    }

    func page(_ page: DCPageWebViewController, didDeleteHighlightWith uuid: String) {
        for sibling in cachedPages where sibling !== page && sibling.spineIndex == page.spineIndex {
            sibling.removeHighlight(uuid: uuid)
        }
        for recycled in recycledWebViews where recycled.spineIndex == page.spineIndex {
            Task { await recycled.webView.removeHighlight(uuid: uuid) }
        }
    }
}

// MARK: - UIGestureRecognizerDelegate

extension DCPagedReaderController: UIGestureRecognizerDelegate {
    // The controls tap must not block page turns, text selection, highlight taps or line focus.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}

// MARK: - SwiftUI

struct DCPagedReaderView: UIViewControllerRepresentable {

    @ObservedObject var viewModel: DCReaderViewModel

    func makeUIViewController(context: Context) -> DCPagedReaderController {
        let controller = DCPagedReaderController(
            book: viewModel.currentBook,
            spineIndex: viewModel.currentSelection,
            coords: viewModel.resumeCoords(for: viewModel.currentSelection),
            configId: viewModel.pagedConfigId,
            appearance: viewModel.appearance,
            userPreferences: viewModel.userPreferences,
            readerContext: viewModel
        ) { [weak viewModel] action, chapterURL in
            viewModel?.handle(action, chapterURL: chapterURL)
        }
        viewModel.pagedNavigator = controller
        return controller
    }

    func updateUIViewController(_ controller: DCPagedReaderController, context: Context) {
        controller.apply(configId: viewModel.pagedConfigId, appearance: viewModel.appearance)
        let lineFocus = viewModel.lineFocusSettings
        controller.applyLineFocus(enabled: lineFocus.enabled, style: lineFocus.style)
    }
}
