//
//  DCPageWebViewController.swift
//  DCEpubReaderKit
//
//  Created by Liam Smith-Gales on 11/11/26.
//

import SwiftUI
import WebKit
import DCEpubCore

/// Where a page should land inside its chapter once the chapter has been paginated.
enum DCPageTarget: Equatable {
    case index(Int)
    case last
    case coords(String)
    /// The n-th match of a search query, which is also highlighted.
    case search(query: String, occurrence: Int)
    /// The element with this id, from a table-of-contents link.
    case fragment(String)

    var isSearch: Bool {
        if case .search = self { return true }
        return false
    }
}

@MainActor
protocol DCPageWebViewControllerDelegate: AnyObject {
    func pageDidLoad(_ page: DCPageWebViewController)
    func page(_ page: DCPageWebViewController, didSave highlight: DCHighlight)
    func page(_ page: DCPageWebViewController, didDeleteHighlightWith uuid: String)
}

/// A single book page for `UIPageViewController`.
///
/// Each page owns a web view with its whole chapter laid out in CSS columns (see
/// `applyHorizontalPagination` in EpubUtil.js). User scrolling is disabled and the scroll view is
/// pinned to the page's column, so page turns are driven entirely by the page view controller.
final class DCPageWebViewController: UIViewController {

    private enum Constants {
        static let fadeDuration: TimeInterval = 0.25
    }

    private enum JSMethod {
        case applyHorizontalPagination
        case getHorizontalPageCount
        case getPageFromCoordsHorizontal(String)
        case scrollToHorizontalPage(Int)
        case getCoordsFirstNodeOfPageHorizontal(page: Int)
        case highlightSearchOccurrence(query: String, occurrence: Int)
        case getPageForElementId(String)

        var rawValue: String {
            switch self {
            case .applyHorizontalPagination:
                return "applyHorizontalPagination()"
            case .getHorizontalPageCount:
                return "getHorizontalPageCount()"
            case .getPageFromCoordsHorizontal(let coords):
                return "getPageFromCoordsHorizontal(\(coords.jsStringLiteral))"
            case .scrollToHorizontalPage(let page):
                return "scrollToHorizontalPage(\(page))"
            case .getCoordsFirstNodeOfPageHorizontal(let page):
                return "getCoordsFirstNodeOfPageHorizontal(\(page))"
            case let .highlightSearchOccurrence(query, occurrence):
                return "highlightSearchOccurrence(\(query.jsStringLiteral), \(occurrence), false)"
            case .getPageForElementId(let id):
                return "getPageForElementId(\(id.jsStringLiteral), false)"
            }
        }
    }

    /// A loaded web view handed over by a page that left the cache, so the next page can skip
    /// creating a web view and, for the same chapter at the same size, loading and paginating.
    struct RecycledWebView {
        let webView: DCWebView
        let spineIndex: Int
        let pageCount: Int
        let layoutSize: CGSize
    }

    let spineIndex: Int
    let target: DCPageTarget
    /// 0-based page within the chapter. `nil` until the chapter has been paginated.
    private(set) var pageIndex: Int?
    private(set) var pageCount: Int?
    var isLoaded: Bool { pageIndex != nil }

    weak var delegate: DCPageWebViewControllerDelegate?

    private let book: DCEpubBook
    private let userPreferences: DCUserPreferencesProtocol
    private let readerContext: any DCChapterReaderContextProtocol
    private let onAction: (DCChapterViewAction) -> Void

    private var webView: DCWebView?
    private var recycled: RecycledWebView?
    private var appearance: DCReaderAppearance
    /// Shown instead of the page when the chapter can't be resolved.
    private let messageLabel = UILabel()
    private var hasStartedLoading = false
    /// Content offset of this page's column. Any scroll away from it (e.g. selection autoscroll) is undone.
    private var pinnedOffset: CGPoint?

    init(book: DCEpubBook,
         spineIndex: Int,
         target: DCPageTarget,
         userPreferences: DCUserPreferencesProtocol,
         readerContext: any DCChapterReaderContextProtocol,
         appearance: DCReaderAppearance,
         recycled: RecycledWebView? = nil,
         onAction: @escaping (DCChapterViewAction) -> Void) {
        self.book = book
        self.appearance = appearance
        self.spineIndex = spineIndex
        self.target = target
        self.userPreferences = userPreferences
        self.readerContext = readerContext
        self.recycled = recycled
        self.onAction = onAction
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var chapterURL: URL? {
        book.chapterURL(forSpineIndex: spineIndex)
    }

    /// The page index this page will show, if it can be known before loading finishes.
    /// `knownPageCount` is the chapter's page count from another page, when available.
    func expectedPageIndex(knownPageCount: Int?) -> Int? {
        if let pageIndex { return pageIndex }
        switch target {
        case .index(let index):
            return knownPageCount.map { min(index, $0 - 1) } ?? index
        case .last:
            return knownPageCount.map { $0 - 1 }
        case .coords, .search, .fragment:
            return nil
        }
    }

    /// Whether this page satisfies a request for `target` in `spineIndex`.
    func matches(spineIndex: Int, target: DCPageTarget) -> Bool {
        guard spineIndex == self.spineIndex else { return false }
        if target == self.target { return true }
        guard let pageIndex, let pageCount else { return false }
        switch target {
        case .index(let index):
            return index == pageIndex
        case .last:
            return pageIndex == pageCount - 1
        case .coords, .search, .fragment:
            return false
        }
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        // The page (and so the page curl) covers the whole screen; only the text is inset.
        view.backgroundColor = appearance.uiBackgroundColor

        let webView = recycled?.webView ?? makeWebView()
        attach(webView)
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        self.webView = webView

        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.font = .preferredFont(forTextStyle: .body)
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.textColor = appearance.uiTextColor
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        view.addSubview(messageLabel)

        let guide = view.safeAreaLayoutGuide
        let margin = userPreferences.getTextLayout().margins.inset
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: guide.topAnchor, constant: DCReaderChrome.topInset),
            webView.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: margin),
            webView.trailingAnchor.constraint(equalTo: guide.trailingAnchor,
                                              constant: -margin + DCReaderChrome.columnGap),
            webView.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -DCReaderChrome.bottomInset),

            messageLabel.centerYAnchor.constraint(equalTo: guide.centerYAnchor),
            messageLabel.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: DCReaderChrome.horizontalInset),
            messageLabel.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -DCReaderChrome.horizontalInset)
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Pagination depends on the web view's final size, so only load once it has been laid out.
        startLoadingIfNeeded()
    }

    private func makeWebView() -> DCWebView {
        let config = WKWebViewConfiguration()
        config.allowsAirPlayForMediaPlayback = false
        config.allowsInlineMediaPlayback = true
        // Like Books: the selection grows by character, across paragraphs, instead of snapping to whole blocks.
        config.selectionGranularity = .character
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = DCWebViewBuilder().build(frame: .zero,
                                               configuration: config,
                                               router: DCPageRouter(page: self))
        #if DEBUG
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
        #endif
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.allowsBackForwardNavigationGestures = false

        let scrollView = webView.scrollView
        scrollView.backgroundColor = .clear
        scrollView.isScrollEnabled = false
        scrollView.bounces = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        return webView
    }

    /// Points a new or recycled web view's callbacks at this page.
    private func attach(_ webView: DCWebView) {
        webView.viewModel = DCWebViewModel(router: DCPageRouter(page: self))
        webView.navigationDelegate = self
        webView.scrollView.delegate = self
        webView.alpha = 0
        webView.setLineFocus(enabled: userPreferences.getLineFocus() && readerContext.configuration.showsLineGuide,
                             appearance: appearance,
                             style: userPreferences.getLineFocusStyle(),
                             textTrailingInset: DCReaderChrome.columnGap)
    }

    /// Hands the web view over for reuse. Only loaded pages give one up, so no pagination task can
    /// still be driving it. The page must not be shown again afterwards.
    func relinquishWebView() -> RecycledWebView? {
        guard let webView, let pageCount, chapterURL != nil else { return nil }
        let recycled = RecycledWebView(webView: webView,
                                       spineIndex: spineIndex,
                                       pageCount: pageCount,
                                       layoutSize: webView.bounds.size)
        webView.navigationDelegate = nil
        webView.scrollView.delegate = nil
        webView.removeFromSuperview()
        self.webView = nil
        return recycled
    }

    // MARK: - Loading

    private func startLoadingIfNeeded() {
        guard !hasStartedLoading,
              let webView,
              webView.bounds.width > 0,
              webView.bounds.height > 0 else { return }
        hasStartedLoading = true

        guard let chapterURL else {
            messageLabel.text = String(format: L("Unable to open section %lld."), spineIndex + 1)
            finishLoading(page: 0, count: 1)
            return
        }
        // Same chapter, same size: the DOM is already paginated and highlighted, just move to our page.
        if let recycled, recycled.spineIndex == spineIndex, recycled.layoutSize == webView.bounds.size {
            self.recycled = nil
            Task { [weak self] in
                await self?.showPage(count: recycled.pageCount, highlightsLoaded: true)
            }
            return
        }
        recycled = nil
        let html = DCChapterHTMLBuilder.html(pathtofile: chapterURL.path,
                                             userPreferences: userPreferences,
                                             appearance: appearance,
                                             fixedLayout: readerContext.currentBook.isFixedLayout(spineIndex: spineIndex),
                                             fonts: readerContext.configuration.fonts)
        webView.loadHTMLString(html, baseURL: chapterURL.deletingLastPathComponent())
    }

    private func paginate() async {
        guard let webView else { return }

        // Pagination measures the body height, so web fonts must be in place first.
        await webView.waitForLayout()
        _ = try? await webView.evaluateJavaScriptAsync(JSMethod.applyHorizontalPagination.rawValue)
        await webView.waitForLayout()

        let rawCount = try? await webView.evaluateJavaScriptAsync(JSMethod.getHorizontalPageCount.rawValue)
        let count = max(1, Int(rawCount ?? "") ?? 1)
        await showPage(count: count, highlightsLoaded: false)
    }

    /// Resolves the target page in an already paginated chapter, pins to it and finishes loading.
    private func showPage(count: Int, highlightsLoaded: Bool) async {
        guard let webView else { return }

        let requestedPage: Int
        switch target {
        case .index(let index):
            requestedPage = index
        case .last:
            requestedPage = count - 1
        case .coords(let coords):
            let rawPage = try? await webView.evaluateJavaScriptAsync(
                JSMethod.getPageFromCoordsHorizontal(coords).rawValue
            )
            requestedPage = Int(rawPage ?? "") ?? 0
        case let .search(query, occurrence):
            // User highlights go in first so their coords resolve against the untouched DOM.
            if !highlightsLoaded {
                await webView.loadHighlights()
            }
            let rawPage = try? await webView.evaluateJavaScriptAsync(
                JSMethod.highlightSearchOccurrence(query: query, occurrence: occurrence).rawValue
            )
            requestedPage = Int(rawPage ?? "") ?? 0
        case .fragment(let id):
            let rawPage = try? await webView.evaluateJavaScriptAsync(JSMethod.getPageForElementId(id).rawValue)
            requestedPage = Int(rawPage ?? "") ?? 0
        }
        let page = min(max(0, requestedPage), count - 1)

        // Scroll via JS so the offset matches the `innerWidth` used by the coords math, then pin natively.
        let rawOffset = try? await webView.evaluateJavaScriptAsync(JSMethod.scrollToHorizontalPage(page).rawValue)
        let offsetX = Double(rawOffset ?? "").map { CGFloat($0) } ?? CGFloat(page) * webView.scrollView.bounds.width
        pin(to: CGPoint(x: offsetX, y: 0))

        // Search targets already loaded them before placing the search mark.
        if !highlightsLoaded && !target.isSearch {
            await webView.loadHighlights()
        }

        // The guide appears together with the page. The blur is a snapshot of the page, which is
        // only drawn once the page is visible, so it's applied right after the page fades in.
        let isBlur = webView.lineFocus?.style == .blur
        if !isBlur {
            await webView.lineFocus?.refresh(anchor: lineFocusAnchor)
        }
        finishLoading(page: page, count: count)
        if isBlur {
            await webView.lineFocus?.refresh(anchor: lineFocusAnchor)
        }
    }

    /// Turning back into a chapter lands on its last page, so reading continues from its last line.
    private var lineFocusAnchor: DCLineFocusController.Anchor {
        switch target {
        case .last:
            return .last
        case .search:
            return .searchMatch
        case .index, .coords, .fragment:
            return .first
        }
    }

    private func finishLoading(page: Int, count: Int) {
        pageIndex = page
        pageCount = count
        if let size = webView?.bounds.size {
            onAction(.pageLayout(size: size))
        }
        UIView.animate(withDuration: Constants.fadeDuration) { [weak self] in
            self?.webView?.alpha = 1
        }
        delegate?.pageDidLoad(self)
    }

    private func pin(to offset: CGPoint) {
        pinnedOffset = offset
        webView?.scrollView.contentOffset = offset
    }

    // MARK: - Reader actions

    /// Recolors this page for another theme of the same font weight, without reloading it.
    func updateAppearance(_ appearance: DCReaderAppearance) {
        guard appearance != self.appearance else { return }
        self.appearance = appearance
        view.backgroundColor = appearance.uiBackgroundColor
        messageLabel.textColor = appearance.uiTextColor
        guard let webView else { return }
        let lineFocusStyle = webView.lineFocus?.style
        Task { [weak self, weak webView] in
            guard let webView else { return }
            await webView.applyTheme(appearance)
            // The line focus effect is drawn in the page colors, so it is rebuilt with the new ones.
            if let lineFocusStyle, let self {
                webView.setLineFocus(enabled: true, appearance: appearance, style: lineFocusStyle,
                                     textTrailingInset: DCReaderChrome.columnGap)
                if self.isLoaded {
                    await webView.lineFocus?.refresh(anchor: .first)
                }
            }
        }
    }

    /// Switches line focus on this page without reloading it.
    func updateLineFocus(enabled: Bool, style: DCLineFocusStyle) {
        guard let webView else { return }
        webView.setLineFocus(enabled: enabled, appearance: appearance, style: style,
                             textTrailingInset: DCReaderChrome.columnGap)
        guard enabled, isLoaded else { return }
        Task { [weak webView] in
            await webView?.lineFocus?.refresh(anchor: .first)
        }
    }

    /// Page (0-based) of this chapter that a saved position falls on.
    func pageIndex(forCoords coords: String) async -> Int? {
        guard let webView, isLoaded, !coords.isEmpty else { return nil }
        let raw = try? await webView.evaluateJavaScriptAsync(JSMethod.getPageFromCoordsHorizontal(coords).rawValue)
        return Int(raw ?? "")
    }

    /// The reader's current text selection on this page, if any.
    func selectedText() async -> String? {
        await webView?.selectedText()
    }

    /// Coords of the first visible node on this page, used for reading position and bookmarks.
    func currentPageCoords() async -> String? {
        guard let webView, let pageIndex else { return nil }
        let coords = try? await webView.evaluateJavaScriptAsync(
            JSMethod.getCoordsFirstNodeOfPageHorizontal(page: pageIndex).rawValue
        )
        guard let coords, !coords.isEmpty else { return nil }
        return coords
    }

    /// Mirrors a highlight created on a sibling page of the same chapter.
    func applyHighlight(_ highlight: DCHighlight) {
        guard isLoaded else { return }
        Task { [weak self] in
            await self?.webView?.applyHighlight(highlight)
        }
    }

    /// Mirrors a highlight deleted on a sibling page of the same chapter.
    func removeHighlight(uuid: String) {
        guard isLoaded else { return }
        Task { [weak self] in
            await self?.webView?.removeHighlight(uuid: uuid)
        }
    }
}

// MARK: - WKNavigationDelegate

extension DCPageWebViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !isLoaded else { return }
        Task { [weak self] in
            await self?.paginate()
        }
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        // highlight:// is handled via postMessage (highlightTapped); cancel the fallback navigation.
        guard let url = navigationAction.request.url, url.scheme != "highlight" else {
            return .cancel
        }
        // Links are posted as `linkTapped`; a page must never navigate away from its chapter.
        return navigationAction.navigationType == .linkActivated ? .cancel : .allow
    }
}

// MARK: - UIScrollViewDelegate

extension DCPageWebViewController: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard let pinnedOffset, scrollView.contentOffset != pinnedOffset else { return }
        scrollView.contentOffset = pinnedOffset
    }
}

// MARK: - Router

extension DCPageWebViewController {
    func showNote(highlight: DCHighlight) {
        onAction(.showNote(highlight: highlight))
    }

    func searchBook(for text: String) {
        onAction(.searchBook(query: text))
    }

    func openLink(_ url: URL) {
        onAction(.openLink(url))
    }

    func saveHighlight(_ highlight: DCHighlight) async {
        await readerContext.save(highlight: highlight)
        delegate?.page(self, didSave: highlight)
    }

    func loadHighlights() async -> [DCHighlight] {
        await readerContext.highlights(for: currentChapterId)
    }

    func deleteHighlight(uuid: String) async {
        await readerContext.deleteHighlight(uuid: uuid)
        delegate?.page(self, didDeleteHighlightWith: uuid)
    }

    var currentBookId: String { readerContext.bookId }
    var currentBook: DCEpubBook? { readerContext.currentBook }
    var configuration: DCReaderConfiguration { readerContext.configuration }
    var currentChapterId: String { chapterURL?.lastPathComponent ?? "" }
}

/// Forwards `DCWebView` callbacks to its page. Holds the page weakly because the page owns the
/// web view, which owns its view model, which owns the router.
@MainActor
private final class DCPageRouter: DCWebViewRouterProtocol {
    private weak var page: DCPageWebViewController?
    private let spineIndex: Int

    init(page: DCPageWebViewController) {
        self.page = page
        self.spineIndex = page.spineIndex
    }

    func showNoote(highlight: DCHighlight) {
        page?.showNote(highlight: highlight)
    }

    func searchBook(for text: String) {
        page?.searchBook(for: text)
    }

    func openLink(_ url: URL) {
        page?.openLink(url)
    }

    func saveHighlight(_ highlight: DCHighlight) async {
        await page?.saveHighlight(highlight)
    }

    func loadHighlights() async -> [DCHighlight] {
        await page?.loadHighlights() ?? []
    }

    func deleteHighlight(uuid: String) async {
        await page?.deleteHighlight(uuid: uuid)
    }

    var currentBookId: String { page?.currentBookId ?? "" }
    var currentChapterId: String { page?.currentChapterId ?? "" }
    var currentSpineIndex: Int { spineIndex }
    var currentBook: DCEpubBook? { page?.currentBook }
    var configuration: DCReaderConfiguration { page?.configuration ?? DCReaderConfiguration() }
}

private extension String {
    var jsStringLiteral: String {
        guard let data = try? JSONSerialization.data(withJSONObject: [self]),
              let literal = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return String(literal.dropFirst().dropLast())
    }
}
