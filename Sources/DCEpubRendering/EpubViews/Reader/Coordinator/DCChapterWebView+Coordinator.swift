//
//  DCChapterWebView+Coordinator.swift
//  DCEpubReaderKit
//
//  Created by Josep Cerdá Penadés on 6/11/25.
//

import SwiftUI
import WebKit

extension DCChapterWebView {

    enum Constants {
        static let spineIndex = "spineIndex"
        static let fadeDuration: TimeInterval = 0.25
    }

    private enum JSMethod {
        case applyHorizontalPagination
        case applyVerticalPagination
        case scrollToLastHorizontalPage
        case scrollToLastVerticalPage
        case scrollToFirstPage
        case getCoordsFirstNodeOfPageHorizontal(page: Int)
        case getCoordsFirstNodeOfPageVertical(page: Int)
        case scrollToCoordsHorizontal(String)
        case scrollToCoordsVertical(String)
        case highlightSearchOccurrence(query: String, occurrence: Int, vertical: Bool)
        case scrollToHorizontalPage(Int)
        case scrollToVerticalPage(Int)
        case getPageForElementId(String, vertical: Bool)
        case clearTextSelection

        var rawValue: String {
            switch self {
            case .applyHorizontalPagination:
                return "applyHorizontalPagination()"
            case .applyVerticalPagination:
                return "applyVerticalPagination()"
            case .scrollToLastHorizontalPage:
                return "scrollToLastHorizontalPage()"
            case .scrollToLastVerticalPage:
                return "scrollToLastVerticalPage()"
            case .scrollToFirstPage:
                return "scrollToFirstPage()"
            case .getCoordsFirstNodeOfPageHorizontal(let page):
                return "getCoordsFirstNodeOfPageHorizontal(\(page))"
            case .getCoordsFirstNodeOfPageVertical(let page):
                return "getCoordsFirstNodeOfPageVertical(\(page))"
            case .scrollToCoordsHorizontal(let coords):
                return "scrollToCoordsHorizontal(\(coords.jsStringLiteral))"
            case .scrollToCoordsVertical(let coords):
                return "scrollToCoordsVertical(\(coords.jsStringLiteral))"
            case let .highlightSearchOccurrence(query, occurrence, vertical):
                return "highlightSearchOccurrence(\(query.jsStringLiteral), \(occurrence), \(vertical))"
            case .scrollToHorizontalPage(let page):
                return "scrollToHorizontalPage(\(page))"
            case .scrollToVerticalPage(let page):
                return "scrollToVerticalPage(\(page))"
            case let .getPageForElementId(id, vertical):
                return "getPageForElementId(\(id.jsStringLiteral), \(vertical))"
            case .clearTextSelection:
                return "clearTextSelection()"
            }
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {

        var currentChapterURL: URL?
        var readAccessURL: URL?
        weak var lazyWebView: DCWebView?
        /// Theme the loaded chapter is drawn in, to recolor it in place when only colors change.
        var appliedAppearance: DCReaderAppearance?
        weak var viewModel: DCChapterWebViewModel?

        private var cachedTotalPages: Int = 0
        private var currentPageOneBased: Int = 0
        /// Overrides the line focused after the next page settle (e.g. a search match, or the last line
        /// when landing on a chapter's last page). Otherwise it follows the paging direction.
        private var pendingFocusAnchor: DCLineFocusController.Anchor?

        let opensExternalLinks: Bool
        let spineIndex: Int
        let userPreferences: DCUserPreferencesProtocol
        let onAction: (DCChapterViewAction) -> Void

        init(opensExternalLinks: Bool = true,
             spineIndex: Int,
             userPreferences: DCUserPreferencesProtocol,
             onAction: @escaping (DCChapterViewAction) -> Void) {
            self.opensExternalLinks = opensExternalLinks
            self.spineIndex = spineIndex
            self.userPreferences = userPreferences
            self.onAction = onAction
            super.init()
        }

        private var orientation: DCBookrOrientation {
            userPreferences.getBookOrientation()
        }

        @MainActor
        private func setInteractivity(_ enabled: Bool, on webView: WKWebView?, animated: Bool = true) {
            guard let webView else { return }
            onAction(.canTouch(enable: enabled))
            let duration = animated ? Constants.fadeDuration : 0
            UIView.animate(withDuration: duration) {
                webView.alpha = enabled ? 1 : 0
            }
        }

        /// Lets the fade-out finish so the jump that follows isn't visible.
        private func waitForFadeOut() async {
            try? await Task.sleep(nanoseconds: UInt64(Constants.fadeDuration * 1_000_000_000))
        }

        @MainActor
        private func scrollAndReport(_ method: JSMethod, webView: WKWebView) async {
            _ = try? await webView.evaluateJavaScriptAsync(method.rawValue)
            scrollViewDidEndDecelerating(webView.scrollView)
        }

        private func applyPagination(_ webView: WKWebView) async -> String? {
            await orientation == .horizontal ?
            applyHorizontalPagination(webView) :
            applyVerticalPagination(webView)
        }

        private func scrollToLastPageWihtOrientagtion(_ webView: WKWebView) async {
            await scrollAndReport(
                orientation == .horizontal ?.scrollToLastHorizontalPage : .scrollToLastVerticalPage,
                webView: webView
            )
        }

        @MainActor
        private func restoreInitialPositionIfNeeded(on webView: WKWebView) async {
            guard let jump = viewModel?.consumeInitialJump() else { return }
            if case .search = jump { pendingFocusAnchor = .searchMatch }
            #if DEBUG
            print("[Nav] restoreInitialPosition spineIndex=\(spineIndex) orientation=\(orientation) jump=\(jump)")
            #endif
            await perform(jump, on: webView)
        }

        /// Scrolls to a saved location, or highlights a search match and scrolls to its page.
        @MainActor
        private func perform(_ jump: DCChapterJump, on webView: WKWebView) async {
            let isHorizontal = orientation == .horizontal
            switch jump {
            case .coords(let coords):
                guard !coords.isEmpty else { return }
                let method: JSMethod = isHorizontal ? .scrollToCoordsHorizontal(coords) : .scrollToCoordsVertical(coords)
                _ = try? await webView.evaluateJavaScriptAsync(method.rawValue)
            case let .search(query, occurrence):
                let rawPage = try? await webView.evaluateJavaScriptAsync(
                    JSMethod.highlightSearchOccurrence(query: query, occurrence: occurrence, vertical: !isHorizontal).rawValue
                )
                guard let page = Int(rawPage ?? ""), page >= 0 else { return }
                let method: JSMethod = isHorizontal ? .scrollToHorizontalPage(page) : .scrollToVerticalPage(page)
                _ = try? await webView.evaluateJavaScriptAsync(method.rawValue)
            case .fragment(let id):
                let rawPage = try? await webView.evaluateJavaScriptAsync(
                    JSMethod.getPageForElementId(id, vertical: !isHorizontal).rawValue
                )
                guard let page = Int(rawPage ?? ""), page >= 0 else { return }
                let method: JSMethod = isHorizontal ? .scrollToHorizontalPage(page) : .scrollToVerticalPage(page)
                _ = try? await webView.evaluateJavaScriptAsync(method.rawValue)
            case .page(let index):
                let page = min(max(0, index), max(cachedTotalPages - 1, 0))
                let method: JSMethod = isHorizontal ? .scrollToHorizontalPage(page) : .scrollToVerticalPage(page)
                _ = try? await webView.evaluateJavaScriptAsync(method.rawValue)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor [weak self] in
                guard let self else { return }

                self.onAction(.pageLayout(size: webView.bounds.size))
                // Pagination measures the body height, so web fonts must be in place first.
                await webView.waitForLayout()
                if let result = await applyPagination(webView),
                   let totalPages = Int(result) {
                    self.cachedTotalPages = max(1, totalPages)
                    self.onAction(.currentPage(index: 1,
                                               totalPages: self.cachedTotalPages,
                                               spineIndex: self.spineIndex))
                }

                await webView.waitForLayout()
                await self.restoreInitialPositionIfNeeded(on: webView)
                await self.lazyWebView?.loadHighlights()
                await webView.waitForLayout()
                self.scrollViewDidEndDecelerating(webView.scrollView)
                self.setInteractivity(true, on: webView, animated: true)
            }
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel); return
            }
            // highlight:// is handled via postMessage (highlightTapped); cancel the fallback navigation.
            if url.scheme == "highlight" {
                decisionHandler(.cancel)
                return
            }
            // Links are posted as `linkTapped`; the chapter must never navigate away.
            decisionHandler(navigationAction.navigationType == .linkActivated ? .cancel : .allow)
        }

        @MainActor
        func updateCurrentPageInternal(target: Int?) {
            guard let webView = lazyWebView else { return }
            Task { @MainActor [weak self, weak webView] in
                guard let self, let webView else { return }
                if target == self.spineIndex {
                    self.setInteractivity(false, on: webView, animated: true)
                    await self.waitForFadeOut()
                    self.pendingFocusAnchor = .last
                    await self.scrollToLastPageWihtOrientagtion(webView)
                } else {
                    await self.scrollAndReport(.scrollToFirstPage, webView: webView)
                }
                await webView.waitForLayout()
                self.scrollViewDidEndDecelerating(webView.scrollView)
                self.setInteractivity(true, on: webView, animated: true)
            }
        }

        func saveBookMark() {
            Task { @MainActor in
                if let coords = await getCoordsFirstNodeOfPage(
                    lazyWebView,
                    currentPage: currentPageOneBased
                ) {
                    onAction(.coordsFirstNodeOfPage(
                        orientation: orientation,
                        spineIndex: spineIndex,
                        coords: coords,
                        isBookMark: true)
                    )
                }
            }
        }

        func jump(to jump: DCChapterJump) {
            Task { @MainActor [weak self] in
                guard let self, let webView = self.lazyWebView else { return }
                #if DEBUG
                print("[Nav] jump spineIndex=\(self.spineIndex) orientation=\(self.orientation) jump=\(jump)")
                #endif
                self.setInteractivity(false, on: webView, animated: true)
                await self.waitForFadeOut()
                if case .search = jump { self.pendingFocusAnchor = .searchMatch }
                await self.perform(jump, on: webView)
                await webView.waitForLayout()
                self.scrollViewDidEndDecelerating(webView.scrollView)
                self.setInteractivity(true, on: webView, animated: true)
            }
        }
    }
}

// MARK: - Webview Scroll listener

extension DCChapterWebView.Coordinator: UIScrollViewDelegate {
    func scrollViewWillEndDragging(_ scrollView: UIScrollView,
                                   withVelocity velocity: CGPoint,
                                   targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        guard orientation == .vertical else { return }
        let atTop = scrollView.contentOffset.y <= 0.0
        let visibleHeight = scrollView.bounds.size.height
        let contentHeight = scrollView.contentSize.height
        let atBottom = contentHeight > 0 && (scrollView.contentOffset.y + visibleHeight) >= (contentHeight - 1.0)

        // Threshold velocity to avoid accidental triggers
        let threshold: CGFloat = 0.5

        if atBottom && velocity.y > threshold {
            // Ask container to move to next chapter
            onAction(.navigateToNextChapter)
        } else if atTop && velocity.y < -threshold {
            // Ask container to move to previous chapter
            onAction(.navigateToPreviousChapter)
            viewModel?.updateCurrentPage(target: spineIndex)
        }
    }
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        // The focus band can't follow the text while it moves; it comes back when scrolling settles.
        lazyWebView?.lineFocus?.suspend()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            scrollViewDidEndDecelerating(scrollView)
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        let isHorizontal = orientation == .horizontal
        let pageLength = isHorizontal ? scrollView.frame.size.width : scrollView.frame.size.height
        guard pageLength > 0 else { return }

        // Use JS-reported total pages when available to avoid rounding drift vs CSS sizing
        let contentLength = isHorizontal ? scrollView.contentSize.width : scrollView.contentSize.height
        // Include a tiny epsilon to avoid ceil jitter when the content length is extremely close to an exact multiple
        let computedTotal = Int(ceil(((contentLength / max(1, pageLength)) - 1e-6)))
        let totalPages = max(1, cachedTotalPages > 0 ? cachedTotalPages : computedTotal)

        // Normalize offset accounting for insets (on iOS, initial contentOffset can be -inset)
        let rawOffset = isHorizontal ? scrollView.contentOffset.x : scrollView.contentOffset.y
        let insetTop = isHorizontal ? scrollView.adjustedContentInset.left : scrollView.adjustedContentInset.top
        let insetBottom = isHorizontal ? scrollView.adjustedContentInset.right : scrollView.adjustedContentInset.bottom
        let effectiveOffset = max(0, rawOffset + insetTop)

        // Indexing strategy:
        //  - Horizontal (paged): round to nearest page (snap)
        //  - Vertical (continuous): floor to the current page to avoid skipping ahead at half pages
        let zeroBased: Int
        if isHorizontal {
            zeroBased = Int((effectiveOffset / pageLength).rounded())
        } else {
            // epsilon to avoid bouncing rounding up when almost at the next page
            let epsilon: CGFloat = 0.0001
            zeroBased = Int(floor((effectiveOffset / pageLength) + epsilon))
        }

        var clampedZeroBased = min(max(0, zeroBased), max(0, totalPages - 1))

        // Strong clamp when at (or beyond) the bottom in vertical mode:
        if !isHorizontal {
            let visibleExtent = pageLength
            let nearBottom = (effectiveOffset + visibleExtent) >= (contentLength - insetBottom - 0.5)
            if nearBottom { clampedZeroBased = max(0, totalPages - 1) }
        }

        let previousPage = currentPageOneBased
        currentPageOneBased = clampedZeroBased + 1
        refreshLineFocus(previousPage: previousPage)

        onAction(.currentPage(index: currentPageOneBased,
                              totalPages: totalPages,
                              spineIndex: spineIndex))

        Task { @MainActor in
            if let coords = await getCoordsFirstNodeOfPage(
                lazyWebView,
                currentPage: currentPageOneBased
            ) {
                onAction(.coordsFirstNodeOfPage(
                    orientation: orientation,
                    spineIndex: spineIndex,
                    coords: coords,
                    isBookMark: false)
                )
            }
        }
    }
}

// MARK: - Reader controls

extension DCChapterWebView.Coordinator: UIGestureRecognizerDelegate {
    /// A tap on the page shows or hides the reader controls, unless it's on a highlight (which
    /// opens the highlight's menu instead).
    @objc func handleChromeTap(_ recognizer: UITapGestureRecognizer) {
        guard let view = recognizer.view else { return }
        let point = recognizer.location(in: view)
        Task { @MainActor [weak self] in
            if await DCWebView.hasHighlight(at: point, in: view) { return }
            self?.onAction(.toggleChrome)
        }
    }

    // Don't block scrolling, text selection, highlight taps or line focus.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}

// MARK: - Line focus

private extension DCChapterWebView.Coordinator {
    func refreshLineFocus(previousPage: Int) {
        guard let lineFocus = lazyWebView?.lineFocus else { return }
        let anchor: DCLineFocusController.Anchor
        if let pendingFocusAnchor {
            anchor = pendingFocusAnchor
        } else if currentPageOneBased == previousPage {
            anchor = .keep
        } else {
            // Paging back continues from the bottom of the previous page.
            anchor = currentPageOneBased < previousPage ? .last : .first
        }
        pendingFocusAnchor = nil
        Task { await lineFocus.refresh(anchor: anchor) }
    }
}

// MARK: - DCChapterWebView.Coordinator JS Methods

private extension DCChapterWebView.Coordinator {
    func applyHorizontalPagination(_ webView: WKWebView) async -> String? {
        try? await webView.evaluateJavaScriptAsync(
            DCChapterWebView.JSMethod.applyHorizontalPagination.rawValue
        ) as? String
    }

    func applyVerticalPagination(_ webView: WKWebView) async -> String? {
        try? await webView.evaluateJavaScriptAsync(
            DCChapterWebView.JSMethod.applyVerticalPagination.rawValue
        ) as? String
    }

    func getCoordsFirstNodeOfPage(_ webView: DCWebView?, currentPage: Int) async -> String? {
        let coordsFirstNodeOfPage = userPreferences.getBookOrientation() == .horizontal ?
        DCChapterWebView.JSMethod.getCoordsFirstNodeOfPageHorizontal :
        DCChapterWebView.JSMethod.getCoordsFirstNodeOfPageVertical
        // currentPage is 1-based (UI convention); JS functions use 0-based page indices.
        let zeroBasedPage = max(0, currentPage - 1)
        #if DEBUG
        print("[Nav] getCoordsFirstNodeOfPage spineIndex=\(spineIndex) currentPage(1-based)=\(currentPage) → zeroBasedPage=\(zeroBasedPage)")
        #endif
        return try? await webView?.evaluateJavaScriptAsync(
            coordsFirstNodeOfPage(zeroBasedPage).rawValue
        ) as? String
    }

    func removeSelectedText(_ webView: DCWebView?) {
        Task { @MainActor in
            _ = try? await webView?.evaluateJavaScriptAsync(
                DCChapterWebView.JSMethod.clearTextSelection.rawValue
            )
        }
    }
}

private extension String {
    var jsStringLiteral: String {
        guard JSONSerialization.isValidJSONObject([self]),
              let data = try? JSONSerialization.data(withJSONObject: [self]),
              let literal = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return String(literal.dropFirst().dropLast())
    }
}
