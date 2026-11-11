//
//  DCBookPaginator.swift
//  DCEpubReaderKit
//
//  Created by Liam Smith-Gales on 11/11/26.
//

import WebKit
import DCEpubCore

/// Counts the pages of every chapter in the background, so the reader can show a whole-book
/// page number ("415 of 832").
///
/// Chapters are laid out one at a time in an off-screen web view with the same HTML, scripts and
/// page size as the reader, so the counts match what the reader shows. Starting again with a
/// different layout (font, size, theme, page size) discards the previous counts.
@MainActor
final class DCBookPaginator {

    /// Everything that affects how many pages a chapter has.
    struct Layout: Equatable {
        let pageSize: CGSize
        let isVertical: Bool
        /// Font, text size and theme (weight).
        let styleId: String
    }

    private(set) var pageCounts: [Int: Int] = [:]
    /// Called after each chapter is counted.
    var onChange: (() -> Void)?

    private let book: DCEpubBook
    private let userPreferences: DCUserPreferencesProtocol
    private var layout: Layout?
    private var task: Task<Void, Never>?

    init(book: DCEpubBook, userPreferences: DCUserPreferencesProtocol) {
        self.book = book
        self.userPreferences = userPreferences
    }

    var isComplete: Bool {
        !book.spine.isEmpty && pageCounts.count == book.spine.count
    }

    func paginate(layout: Layout, appearance: DCReaderAppearance) {
        guard layout != self.layout, layout.pageSize.width > 0, layout.pageSize.height > 0 else { return }
        task?.cancel()
        self.layout = layout
        pageCounts = [:]
        onChange?()
        task = Task { [weak self] in
            await self?.run(layout: layout, appearance: appearance)
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    private func run(layout: Layout, appearance: DCReaderAppearance) async {
        let webView = WKWebView(frame: CGRect(origin: .zero, size: layout.pageSize),
                                configuration: WKWebViewConfiguration())
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        let loader = DCPageLoader()
        webView.navigationDelegate = loader

        for spineIndex in book.spine.indices {
            guard !Task.isCancelled else { return }
            guard let chapterURL = book.chapterURL(forSpineIndex: spineIndex) else {
                record(1, for: spineIndex)
                continue
            }
            let html = DCChapterHTMLBuilder.html(pathtofile: chapterURL.path,
                                                 userPreferences: userPreferences,
                                                 appearance: appearance)
            guard await loader.load(html, baseURL: chapterURL.deletingLastPathComponent(), in: webView) else {
                record(1, for: spineIndex)
                continue
            }
            // Same sequence as the readers: fonts in place, paginate, let columns settle, measure.
            await webView.waitForLayout()
            let rawCount: String?
            if layout.isVertical {
                // Returns a number; the bridge only reads strings.
                rawCount = try? await webView.evaluateJavaScriptAsync("String(applyVerticalPagination())")
            } else {
                _ = try? await webView.evaluateJavaScriptAsync("applyHorizontalPagination()")
                await webView.waitForLayout()
                rawCount = try? await webView.evaluateJavaScriptAsync("getHorizontalPageCount()")
            }
            guard !Task.isCancelled else { return }
            record(Int(rawCount ?? "") ?? 1, for: spineIndex)
        }
    }

    private func record(_ count: Int, for spineIndex: Int) {
        pageCounts[spineIndex] = max(1, count)
        onChange?()
    }
}

/// Awaits a web view's `loadHTMLString`.
@MainActor
private final class DCPageLoader: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Bool, Never>?

    func load(_ html: String, baseURL: URL, in webView: WKWebView) async -> Bool {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            webView.loadHTMLString(html, baseURL: baseURL)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finish(true)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(false)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(false)
    }

    private func finish(_ success: Bool) {
        continuation?.resume(returning: success)
        continuation = nil
    }
}
