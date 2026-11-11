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
        static let horizontalInset: CGFloat = 24
        static let verticalInset: CGFloat = 12
        static let footerHeight: CGFloat = 20
        static let fadeDuration: TimeInterval = 0.25
        static let settleDelay: UInt64 = 350_000_000
    }

    private enum JSMethod {
        case applyHorizontalPagination
        case getHorizontalPageCount
        case getPageFromCoordsHorizontal(String)
        case scrollToHorizontalPage(Int)
        case getCoordsFirstNodeOfPageHorizontal(page: Int)
        case highlightSearchOccurrence(query: String, occurrence: Int)

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
            }
        }
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
    private let footerLabel = UILabel()
    private var hasStartedLoading = false
    /// Content offset of this page's column. Any scroll away from it (e.g. selection autoscroll) is undone.
    private var pinnedOffset: CGPoint?

    init(book: DCEpubBook,
         spineIndex: Int,
         target: DCPageTarget,
         userPreferences: DCUserPreferencesProtocol,
         readerContext: any DCChapterReaderContextProtocol,
         onAction: @escaping (DCChapterViewAction) -> Void) {
        self.book = book
        self.spineIndex = spineIndex
        self.target = target
        self.userPreferences = userPreferences
        self.readerContext = readerContext
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
        case .coords, .search:
            return false
        }
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        let desktopMode = userPreferences.getDesktopMode()
        view.backgroundColor = UIColor(desktopMode.backgroundColor)

        let webView = makeWebView()
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        self.webView = webView

        footerLabel.translatesAutoresizingMaskIntoConstraints = false
        footerLabel.font = .systemFont(ofSize: 14)
        footerLabel.textColor = UIColor(desktopMode.textColor)
        footerLabel.textAlignment = .center
        footerLabel.numberOfLines = 0
        view.addSubview(footerLabel)

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: guide.topAnchor, constant: Constants.verticalInset),
            webView.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: Constants.horizontalInset),
            webView.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -Constants.horizontalInset),
            webView.bottomAnchor.constraint(equalTo: footerLabel.topAnchor, constant: -Constants.verticalInset),

            footerLabel.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: Constants.horizontalInset),
            footerLabel.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -Constants.horizontalInset),
            footerLabel.bottomAnchor.constraint(equalTo: guide.bottomAnchor),
            footerLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: Constants.footerHeight)
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
        webView.navigationDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.alpha = 0
        webView.allowsBackForwardNavigationGestures = false

        let scrollView = webView.scrollView
        scrollView.backgroundColor = .clear
        scrollView.isScrollEnabled = false
        scrollView.bounces = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.delegate = self
        return webView
    }

    // MARK: - Loading

    private func startLoadingIfNeeded() {
        guard !hasStartedLoading,
              let webView,
              webView.bounds.width > 0,
              webView.bounds.height > 0 else { return }
        hasStartedLoading = true

        guard let chapterURL else {
            footerLabel.text = "Unable to resolve chapter at spine index \(spineIndex)."
            finishLoading(page: 0, count: 1)
            return
        }
        let html = DCChapterHTMLBuilder.html(pathtofile: chapterURL.path, userPreferences: userPreferences)
        webView.loadHTMLString(html, baseURL: chapterURL.deletingLastPathComponent())
    }

    private func paginate() async {
        guard let webView else { return }

        _ = try? await webView.evaluateJavaScriptAsync(JSMethod.applyHorizontalPagination.rawValue)
        // Give fonts and columns time to settle before measuring.
        try? await Task.sleep(nanoseconds: Constants.settleDelay)

        let rawCount = try? await webView.evaluateJavaScriptAsync(JSMethod.getHorizontalPageCount.rawValue)
        let count = max(1, Int(rawCount ?? "") ?? 1)

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
            await webView.loadHighlights()
            let rawPage = try? await webView.evaluateJavaScriptAsync(
                JSMethod.highlightSearchOccurrence(query: query, occurrence: occurrence).rawValue
            )
            requestedPage = Int(rawPage ?? "") ?? 0
        }
        let page = min(max(0, requestedPage), count - 1)

        // Scroll via JS so the offset matches the `innerWidth` used by the coords math, then pin natively.
        let rawOffset = try? await webView.evaluateJavaScriptAsync(JSMethod.scrollToHorizontalPage(page).rawValue)
        let offsetX = Double(rawOffset ?? "").map { CGFloat($0) } ?? CGFloat(page) * webView.scrollView.bounds.width
        pin(to: CGPoint(x: offsetX, y: 0))

        // Search targets already loaded them before placing the search mark.
        if !target.isSearch {
            await webView.loadHighlights()
        }

        if count > 1 {
            footerLabel.text = DCReaderViewModel.pageInfo(currentPage: page + 1, totalPages: count)
        }
        finishLoading(page: page, count: count)
    }

    private func finishLoading(page: Int, count: Int) {
        pageIndex = page
        pageCount = count
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
        return .allow
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
