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

    /// A place in a chapter whose page should be found while the chapter is laid out.
    enum Locator: Hashable {
        /// An element id, from a table-of-contents link (`chapter.xhtml#id`).
        case fragment(String)
        /// A saved position (bookmark, highlight or note).
        case coords(String)
    }

    struct LocatedPlace: Hashable {
        let spineIndex: Int
        let locator: Locator
    }

    /// A search match: the n-th match of `query` in a chapter, as the search engine numbers them.
    struct SearchPlace: Hashable {
        let query: String
        let spineIndex: Int
        let occurrence: Int
    }

    private(set) var pageCounts: [Int: Int] = [:]
    /// Page (0-based, within its chapter) of every place `locators` asked for, for the current layout.
    private(set) var locatedPages: [LocatedPlace: Int] = [:]
    /// Page (0-based, within its chapter) of the matches of the last search, for the current layout.
    /// Found after the search, in a web view of its own (see `locateSearch`).
    private(set) var searchPages: [SearchPlace: Int] = [:]
    /// Places to find in a chapter; asked when that chapter is laid out.
    var locators: ((Int) -> [Locator])?
    /// Called after each chapter is counted.
    var onChange: (() -> Void)?

    private let book: DCEpubBook
    private let userPreferences: DCUserPreferencesProtocol
    private var layout: Layout?
    private var appearance: DCReaderAppearance?
    private var task: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    /// The matches `locateSearch` was last asked for, located again after a relayout.
    private var lastSearch: [SearchPlace] = []

    private let fonts: [DCReaderFont]

    init(book: DCEpubBook, userPreferences: DCUserPreferencesProtocol, fonts: [DCReaderFont] = []) {
        self.book = book
        self.userPreferences = userPreferences
        self.fonts = fonts
    }

    var isComplete: Bool {
        !book.spine.isEmpty && pageCounts.count == book.spine.count
    }

    func paginate(layout: Layout, appearance: DCReaderAppearance) {
        guard layout != self.layout, layout.pageSize.width > 0, layout.pageSize.height > 0 else { return }
        task?.cancel()
        self.layout = layout
        self.appearance = appearance
        pageCounts = [:]
        locatedPages = [:]
        searchPages = [:]
        onChange?()
        task = Task { [weak self] in
            await self?.run(layout: layout, appearance: appearance)
        }
        locateSearch(lastSearch)
    }

    func cancel() {
        task?.cancel()
        task = nil
        searchTask?.cancel()
        searchTask = nil
    }

    /// Finds the exact page of each search match, replacing the estimate from where the match falls
    /// in its chapter's text (which is off when images, headings or spacing aren't spread evenly).
    func locateSearch(_ places: [SearchPlace]) {
        searchTask?.cancel()
        lastSearch = places
        searchPages = [:]
        guard let layout, let appearance, !places.isEmpty else {
            onChange?()
            return
        }
        searchTask = Task { [weak self] in
            await self?.runSearch(places, layout: layout, appearance: appearance)
        }
    }

    private func runSearch(_ places: [SearchPlace], layout: Layout, appearance: DCReaderAppearance) async {
        let webView = WKWebView(frame: CGRect(origin: .zero, size: layout.pageSize),
                                configuration: WKWebViewConfiguration())
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        let loader = DCPageLoader()
        webView.navigationDelegate = loader

        let byChapter = Dictionary(grouping: places, by: \.spineIndex)
        for spineIndex in byChapter.keys.sorted() {
            guard !Task.isCancelled, let chapterURL = book.chapterURL(forSpineIndex: spineIndex) else { continue }
            let html = DCChapterHTMLBuilder.html(pathtofile: chapterURL.path,
                                                 userPreferences: userPreferences,
                                                 appearance: appearance,
                                                 fixedLayout: book.isFixedLayout(spineIndex: spineIndex),
                                                 fonts: fonts)
            guard await loader.load(html, baseURL: chapterURL.deletingLastPathComponent(), in: webView) else { continue }
            await webView.waitForLayout()
            if layout.isVertical {
                _ = try? await webView.evaluateJavaScriptAsync("String(applyVerticalPagination())")
            } else {
                _ = try? await webView.evaluateJavaScriptAsync("applyHorizontalPagination()")
                await webView.waitForLayout()
            }
            // One call per chapter and query: the page of every match at once.
            for (query, places) in Dictionary(grouping: byChapter[spineIndex] ?? [], by: \.query) {
                let occurrences = places.map(\.occurrence)
                let script = "searchOccurrencePages(\(Self.jsLiteral(query)), \(occurrences), \(layout.isVertical))"
                guard let raw = try? await webView.evaluateJavaScriptAsync(script),
                      let pages = try? JSONDecoder().decode([Int].self, from: Data(raw.utf8)) else { continue }
                for (place, page) in zip(places, pages) where page >= 0 {
                    searchPages[place] = page
                }
            }
            guard !Task.isCancelled else { return }
            onChange?()
        }
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
                                                 appearance: appearance,
                                                 fixedLayout: book.isFixedLayout(spineIndex: spineIndex),
                                                 fonts: fonts)
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
            await locate(locators?(spineIndex) ?? [], in: spineIndex, webView: webView, isVertical: layout.isVertical)
            guard !Task.isCancelled else { return }
            record(Int(rawCount ?? "") ?? 1, for: spineIndex)
        }
    }

    private func locate(_ places: [Locator], in spineIndex: Int, webView: WKWebView, isVertical: Bool) async {
        for place in Set(places) {
            let script: String
            switch place {
            case .fragment(let id):
                script = "getPageForElementId(\(Self.jsLiteral(id)), \(isVertical))"
            case .coords(let coords):
                script = isVertical
                    ? "String(Math.max(0, getPageFromCoordsVertical(\(Self.jsLiteral(coords)))))"
                    : "getPageFromCoordsHorizontal(\(Self.jsLiteral(coords)))"
            }
            let raw = try? await webView.evaluateJavaScriptAsync(script)
            if let page = Int(raw ?? ""), page >= 0 {
                locatedPages[LocatedPlace(spineIndex: spineIndex, locator: place)] = page
            }
        }
    }

    private static func jsLiteral(_ string: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [string]),
              let array = String(data: data, encoding: .utf8) else { return "\"\"" }
        return String(array.dropFirst().dropLast())
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
