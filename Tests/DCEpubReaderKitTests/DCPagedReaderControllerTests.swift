//
//  DCPagedReaderControllerTests.swift
//  DCEpubReaderKit
//
//  Created by Liam Smith-Gales on 11/11/26.
//

import Foundation
import Testing
import UIKit
import WebKit
import DCEpubCore
@testable import DCEpubRendering

/// Drives the paged reader with real web views in a window: page turns across chapters,
/// neighbour preloading, the page-count cache and web view reuse.
extension WebKitBackedTests {

@MainActor
@Suite("DCPagedReaderController")
struct DCPagedReaderControllerTests {

    static let appearance = DCReaderAppearance(theme: .original, isDark: false)

    private final class ReaderContext: DCChapterReaderContextProtocol {
        let currentBook: DCEpubBook
        var bookId: String { "test-book" }
        init(book: DCEpubBook) { currentBook = book }
        func consumeInitialJump(for spineIndex: Int, chapterURL: URL) -> DCChapterJump? { nil }
        func showNote(highlight: DCHighlight) {}
        func save(highlight: DCHighlight) async {}
        func deleteHighlight(uuid: String) async {}
        func highlights(for chapterId: String) async -> [DCHighlight] { [] }
    }

    /// Chapter 1 is long enough for several pages; chapter 2 fits on one.
    private func makeBook() throws -> DCEpubBook {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let text = root.appendingPathComponent("OEBPS/Text", isDirectory: true)
        try FileManager.default.createDirectory(at: text, withIntermediateDirectories: true)

        let paragraph = "<p>\(String(repeating: "Call me Ishmael. Some years ago, never mind how long precisely. ", count: 12))</p>"
        let bodies = [String(repeating: paragraph, count: 20) + "<p id=\"deep\">Deep target paragraph.</p>" + String(repeating: paragraph, count: 5),
                      "<p>Short chapter.</p>"]
        var manifest: [DCManifestItem] = []
        var spine: [DCSpineItem] = []
        for (index, body) in bodies.enumerated() {
            let href = "Text/c\(index).xhtml"
            try "<html><head></head><body>\(body)</body></html>"
                .write(to: root.appendingPathComponent("OEBPS/\(href)"), atomically: true, encoding: .utf8)
            manifest.append(DCManifestItem(id: "c\(index)", href: href, mediaType: "application/xhtml+xml"))
            spine.append(DCSpineItem(idref: "c\(index)", linear: true))
        }
        return DCEpubBook(packagePath: "OEBPS/content.opf",
                          metadata: DCOPFMetadata(),
                          manifest: manifest,
                          spine: spine,
                          toc: [],
                          resourcesRoot: root)
    }

    /// Two fixed-layout pages (600 × 800, from their viewport) and a reflowable chapter between.
    private func makeFixedLayoutBook() throws -> DCEpubBook {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let text = root.appendingPathComponent("OEBPS/Text", isDirectory: true)
        try FileManager.default.createDirectory(at: text, withIntermediateDirectories: true)
        let page = { (label: String) in
            """
            <html><head><meta name="viewport" content="width=600, height=800"/></head>
            <body style="margin:0"><div id="panel" style="position:absolute; left:0; top:0; width:600px; height:800px; background:#c33">\(label)</div></body></html>
            """
        }
        let bodies = [page("One"), "<html><head></head><body><p>Reflowable.</p></body></html>", page("Two")]
        var manifest: [DCManifestItem] = []
        var spine: [DCSpineItem] = []
        for (index, body) in bodies.enumerated() {
            let href = "Text/p\(index).xhtml"
            try body.write(to: root.appendingPathComponent("OEBPS/\(href)"), atomically: true, encoding: .utf8)
            manifest.append(DCManifestItem(id: "p\(index)", href: href, mediaType: "application/xhtml+xml"))
            spine.append(DCSpineItem(idref: "p\(index)", linear: true,
                                     properties: index == 1 ? "rendition:layout-reflowable" : nil))
        }
        var metadata = DCOPFMetadata()
        metadata.renditionLayout = "pre-paginated"
        return DCEpubBook(packagePath: "OEBPS/content.opf", metadata: metadata, manifest: manifest,
                          spine: spine, toc: [], resourcesRoot: root)
    }

    @Test func fixedLayoutPagesAreOnePageScaledToFit() async throws {
        let book = try makeFixedLayoutBook()
        #expect(book.isFixedLayout(spineIndex: 0))
        #expect(!book.isFixedLayout(spineIndex: 1), "the itemref overrides the book")
        let (controller, window) = makeController(book: book)
        defer { window.isHidden = true }
        let page = try #require(controller.currentPage)
        try await waitUntil { page.isLoaded }
        #expect(page.pageCount == 1)
        let webView = try #require(webView(of: page))
        let raw = try #require(try await webView.evaluateJavaScript("""
        (function () {
            const r = document.getElementById('panel').getBoundingClientRect();
            return JSON.stringify([r.left, r.top, r.width, r.height, window.innerWidth, window.innerHeight]);
        })()
        """) as? String)
        let box = try JSONDecoder().decode([Double].self, from: Data(raw.utf8))
        let (left, top, width, height, viewWidth, viewHeight) = (box[0], box[1], box[2], box[3], box[4], box[5])
        // The whole page shows, as large as fits, keeping its 3:4 shape, centered.
        #expect(abs(width / height - 0.75) < 0.01)
        // The web view runs one column gap past the text area on the right, which isn't page.
        let pageWidth = viewWidth - DCReaderChrome.columnGap
        #expect(abs(width - pageWidth) < 1 || abs(height - viewHeight) < 1)
        #expect(width <= pageWidth + 1 && height <= viewHeight + 1)
        #expect(abs(left - (pageWidth - width) / 2) < 1 && abs(top - (viewHeight - height) / 2) < 1)
    }

    @Test func fixedLayoutPageSizeComesFromItsViewport() {
        #expect(DCChapterHTMLBuilder.fixedLayoutSize(in: #"<meta name="viewport" content="width=1200, height=1800"/>"#) == (1200, 1800))
        #expect(DCChapterHTMLBuilder.fixedLayoutSize(in: #"<meta content="width=800,height=600" name="viewport">"#) == (800, 600))
        #expect(DCChapterHTMLBuilder.fixedLayoutSize(in: #"<svg viewBox="0 0 1000 1500">"#) == (1000, 1500))
        #expect(DCChapterHTMLBuilder.fixedLayoutSize(in: "<p>none</p>") == (0, 0))
    }

    private func makeController(book: DCEpubBook,
                                spineIndex: Int = 0,
                                lineFocus: Bool = false) -> (DCPagedReaderController, UIWindow) {
        let preferences = DCUserPreferencesMock()
        preferences.lineFocus = lineFocus
        let controller = DCPagedReaderController(book: book,
                                                 spineIndex: spineIndex,
                                                 coords: nil,
                                                 configId: "test",
                                                 appearance: Self.appearance,
                                                 userPreferences: preferences,
                                                 readerContext: ReaderContext(book: book)) { _, _ in }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        return (controller, window)
    }

    /// Polls until `condition` holds (web view loads are asynchronous).
    private func waitUntil(timeout: TimeInterval = 10, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { throw WaitTimeout() }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }
    private struct WaitTimeout: Error {}

    private func page(after page: DCPageWebViewController, in controller: DCPagedReaderController) -> DCPageWebViewController? {
        guard let pvc = controller.pageViewController else { return nil }
        return controller.pageViewController(pvc, viewControllerAfter: page) as? DCPageWebViewController
    }

    private func page(before page: DCPageWebViewController, in controller: DCPagedReaderController) -> DCPageWebViewController? {
        guard let pvc = controller.pageViewController else { return nil }
        return controller.pageViewController(pvc, viewControllerBefore: page) as? DCPageWebViewController
    }

    /// Shows `page` as if a page turn completed.
    private func settle(on page: DCPageWebViewController, in controller: DCPagedReaderController) {
        guard let pvc = controller.pageViewController else { return }
        pvc.setViewControllers([page], direction: .forward, animated: false)
        controller.pageViewController(pvc, didFinishAnimating: true, previousViewControllers: [], transitionCompleted: true)
    }

    private func webView(of page: DCPageWebViewController) -> WKWebView? {
        page.view.subviews.compactMap { $0 as? WKWebView }.first
    }

    /// Columns used to be spaced (page width + gap / page count) apart, so text crept sideways
    /// page by page. Every page must now start its text at the same x as the first.
    @Test func textStartsAtTheSameXOnEveryPage() async throws {
        let (controller, window) = makeController(book: try makeBook())
        defer { window.isHidden = true }
        let page = try #require(controller.currentPage)
        try await waitUntil { page.isLoaded }
        let webView = try #require(webView(of: page))
        let count = try #require(page.pageCount)
        #expect(count > 5)

        func leftmostText(onPage index: Int) async throws -> Double {
            _ = try await webView.evaluateJavaScript("scrollToHorizontalPage(\(index))")
            let json = try await webView.evaluateJavaScript("getVisibleLineRects()") as? String ?? "{}"
            let object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
            let lines = object?["lines"] as? [[Double]] ?? []
            return try #require(lines.map { $0[0] }.min())
        }
        let first = try await leftmostText(onPage: 0)
        let later = try await leftmostText(onPage: count - 1)
        #expect(abs(first - later) < 1, "page \(count) text starts at \(later), page 1 at \(first)")
    }

    @Test func colorOnlyThemeChangeRecolorsWithoutReloading() async throws {
        let (controller, window) = makeController(book: try makeBook())
        defer { window.isHidden = true }
        let page = try #require(controller.currentPage)
        try await waitUntil { page.isLoaded }
        let webView = try #require(webView(of: page))

        let calm = DCReaderAppearance(theme: .calm, isDark: false)
        controller.apply(configId: "test", appearance: calm)

        #expect(controller.currentPage === page, "the page wasn't rebuilt")
        #expect(self.webView(of: page) === webView)
        #expect(page.view.backgroundColor == calm.uiBackgroundColor)
        var color: String?
        try await waitUntil {
            Task { color = try? await webView.evaluateJavaScript("getComputedStyle(document.body).color") as? String }
            return color == "rgb(74, 62, 44)"
        }
    }

    /// Relayouts in a row (bigger text, then smaller again) must reuse one anchor instead of
    /// re-reading it from each new layout, which drifted the position back a page.
    @Test func consecutiveRelayoutsKeepTheSameAnchor() async throws {
        let (controller, window) = makeController(book: try makeBook())
        defer { window.isHidden = true }
        let first = try #require(controller.currentPage)
        try await waitUntil { first.isLoaded }
        // Move into the chapter so the anchor isn't simply its start.
        for _ in 0..<3 {
            let current = try #require(controller.currentPage)
            let next = try #require(page(after: current, in: controller))
            settle(on: next, in: controller)
            try await waitUntil { next.isLoaded }
        }

        controller.apply(configId: "bigger", appearance: Self.appearance)
        try await waitUntil { controller.currentPage !== nil && controller.currentPage?.isLoaded == true && controller.currentPage?.target != .index(3) }
        let afterFirst = try #require(controller.currentPage)
        guard case .coords = afterFirst.target else {
            Issue.record("the relayout should open at the saved position")
            return
        }

        controller.apply(configId: "smaller", appearance: Self.appearance)
        try await waitUntil { controller.currentPage !== afterFirst && controller.currentPage?.isLoaded == true }
        #expect(controller.currentPage?.target == afterFirst.target)
    }

    /// A bookmark stores the first text of its page; coming back to that page must resolve it to the
    /// same page, which is what shows the bookmark button filled.
    @Test func bookmarkPositionResolvesToThePageItWasMadeOn() async throws {
        let (controller, window) = makeController(book: try makeBook())
        defer { window.isHidden = true }
        var current = try #require(controller.currentPage)
        try await waitUntil { current.isLoaded }
        for _ in 0..<3 {
            let next = try #require(page(after: current, in: controller))
            settle(on: next, in: controller)
            try await waitUntil { next.isLoaded }
            current = next
        }
        let coords = try #require(await current.currentPageCoords())
        #expect(await controller.pageIndex(forCoords: coords) == current.pageIndex)
    }

    /// Page numbers in Contents and the marks lists come from the background count: it must find
    /// anchors and saved positions on the same pages the reader opens them on.
    @Test func backgroundCountLocatesAnchorsAndSavedPositions() async throws {
        let book = try makeBook()
        let (controller, window) = makeController(book: book)
        defer { window.isHidden = true }
        try await waitUntil { controller.currentPage?.isLoaded == true }
        controller.show(spineIndex: 0, fragment: "deep")
        let deepPage = try #require(controller.currentPage)
        try await waitUntil { deepPage.isLoaded }
        let coords = try #require(await deepPage.currentPageCoords())
        let pageSize = try #require(webView(of: deepPage)?.bounds.size)

        let paginator = DCBookPaginator(book: book, userPreferences: DCUserPreferencesMock())
        paginator.locators = { spineIndex in spineIndex == 0 ? [.fragment("deep"), .coords(coords)] : [] }
        paginator.paginate(layout: DCBookPaginator.Layout(pageSize: pageSize, isVertical: false, styleId: "test"),
                           appearance: Self.appearance)
        try await waitUntil(timeout: 20) { paginator.isComplete }

        #expect(paginator.locatedPages[.init(spineIndex: 0, locator: .fragment("deep"))] == deepPage.pageIndex)
        #expect(paginator.locatedPages[.init(spineIndex: 0, locator: .coords(coords))] == deepPage.pageIndex)
    }

    /// Search results list exact pages: the paginator finds each match where the reader opens it.
    @Test func searchMatchesAreLocatedOnThePagesTheReaderOpens() async throws {
        let book = try makeBook()
        let (controller, window) = makeController(book: book)
        defer { window.isHidden = true }
        let first = try #require(controller.currentPage)
        try await waitUntil { first.isLoaded }
        let pageSize = try #require(webView(of: first)?.bounds.size)

        let paginator = DCBookPaginator(book: book, userPreferences: DCUserPreferencesMock())
        paginator.paginate(layout: DCBookPaginator.Layout(pageSize: pageSize, isVertical: false, styleId: "test"),
                           appearance: Self.appearance)
        // "Deep" appears once, deep in the chapter; "Ishmael" is on every page, so take a late one.
        let places: [DCBookPaginator.SearchPlace] = [
            .init(query: "Deep", spineIndex: 0, occurrence: 0),
            .init(query: "Ishmael", spineIndex: 0, occurrence: 200)
        ]
        paginator.locateSearch(places)
        try await waitUntil(timeout: 20) { paginator.searchPages.count == places.count }

        for place in places {
            controller.show(spineIndex: 0, searchQuery: place.query, occurrence: place.occurrence)
            let page = try #require(controller.currentPage)
            try await waitUntil { page.isLoaded }
            #expect(paginator.searchPages[place] == page.pageIndex, "\(place.query) #\(place.occurrence)")
        }
    }

    /// Scrolling mode counts a chapter as the screens it takes, not one page per chapter.
    @Test func scrollingLayoutCountsScreens() async throws {
        let paginator = DCBookPaginator(book: try makeBook(), userPreferences: DCUserPreferencesMock())
        paginator.paginate(layout: DCBookPaginator.Layout(pageSize: CGSize(width: 342, height: 700), isVertical: true, styleId: "test"),
                           appearance: Self.appearance)
        try await waitUntil(timeout: 20) { paginator.isComplete }
        #expect((paginator.pageCounts[0] ?? 0) > 3, "a long chapter takes several screens")
        #expect(paginator.pageCounts[1] == 1)
    }

    @Test func togglingLineFocusUpdatesTheCurrentPageWithoutReloading() async throws {
        let (controller, window) = makeController(book: try makeBook())
        defer { window.isHidden = true }
        let page = try #require(controller.currentPage)
        try await waitUntil { page.isLoaded }
        let webView = try #require(webView(of: page) as? DCWebView)
        #expect(webView.lineFocus == nil)

        controller.applyLineFocus(enabled: true, style: .guide)
        try await waitUntil { webView.lineFocus?.focusedIndex == 0 }
        #expect(controller.currentPage === page, "the page wasn't rebuilt")
        #expect(self.webView(of: page) === webView)

        controller.applyLineFocus(enabled: false, style: .guide)
        #expect(webView.lineFocus == nil)
    }

    @Test func contentsFragmentOpensThePageWithThatElement() async throws {
        let (controller, window) = makeController(book: try makeBook())
        defer { window.isHidden = true }
        try await waitUntil { controller.currentPage?.isLoaded == true }

        controller.show(spineIndex: 0, fragment: "deep")
        let page = try #require(controller.currentPage)
        try await waitUntil { page.isLoaded }
        #expect((page.pageIndex ?? 0) > 0, "the target is deep in the chapter")
        let webView = try #require(webView(of: page))
        let onScreen = try await webView.evaluateJavaScript(
            "(function(){ const r = document.getElementById('deep').getBoundingClientRect(); return String(r.left >= 0 && r.left < window.innerWidth); })()"
        ) as? String
        #expect(onScreen == "true")
    }

    @Test func backgroundPaginatorMatchesTheReadersPageCounts() async throws {
        let book = try makeBook()
        let (controller, window) = makeController(book: book)
        defer { window.isHidden = true }
        let first = try #require(controller.currentPage)
        try await waitUntil { first.isLoaded }
        let pageSize = try #require(webView(of: first)?.bounds.size)

        let paginator = DCBookPaginator(book: book, userPreferences: DCUserPreferencesMock())
        paginator.paginate(layout: DCBookPaginator.Layout(pageSize: pageSize, isVertical: false, styleId: "test"),
                           appearance: Self.appearance)
        try await waitUntil(timeout: 20) { paginator.isComplete }

        #expect(paginator.pageCounts[0] == first.pageCount)
        #expect(paginator.pageCounts[1] == 1)
    }

    @Test func lineFocusLandsOnTheFirstLineAndTheLastWhenTurningBack() async throws {
        let (controller, window) = makeController(book: try makeBook(), spineIndex: 1, lineFocus: true)
        defer { window.isHidden = true }

        let first = try #require(controller.currentPage)
        try await waitUntil { first.isLoaded }
        let firstFocus = try #require((webView(of: first) as? DCWebView)?.lineFocus)
        #expect(!firstFocus.lines.isEmpty)
        #expect(firstFocus.focusedIndex == 0)

        // Back from chapter 1's first page lands on chapter 0's last page, focused on its last line.
        let back = try #require(page(before: first, in: controller))
        settle(on: back, in: controller)
        try await waitUntil { back.isLoaded }
        let backFocus = try #require((webView(of: back) as? DCWebView)?.lineFocus)
        #expect(!backFocus.lines.isEmpty)
        #expect(backFocus.focusedIndex == backFocus.lines.count - 1)
    }

    @Test func turnsThroughAChapterIntoTheNextAndBack() async throws {
        let (controller, window) = makeController(book: try makeBook())
        defer { window.isHidden = true }

        let first = try #require(controller.currentPage)
        try await waitUntil { first.isLoaded }
        let pageCount = try #require(first.pageCount)
        #expect(first.pageIndex == 0)
        #expect(pageCount > 2, "fixture chapter should span several pages")
        #expect(page(before: first, in: controller) == nil, "nothing before the first page of the book")

        // Walk to the last page of chapter 0.
        var current = first
        for expected in 1..<pageCount {
            let next = try #require(page(after: current, in: controller))
            settle(on: next, in: controller)
            try await waitUntil { next.isLoaded }
            #expect(next.spineIndex == 0)
            #expect(next.pageIndex == expected)
            current = next
        }

        // The next turn crosses into chapter 1; going back lands on chapter 0's last page.
        let nextChapter = try #require(page(after: current, in: controller))
        settle(on: nextChapter, in: controller)
        try await waitUntil { nextChapter.isLoaded }
        #expect(nextChapter.spineIndex == 1)
        #expect(nextChapter.pageIndex == 0)
        #expect(page(after: nextChapter, in: controller) == nil, "nothing after the last page of the book")

        let back = try #require(page(before: nextChapter, in: controller))
        try await waitUntil { back.isLoaded }
        #expect(back.spineIndex == 0)
        #expect(back.pageIndex == pageCount - 1)
    }

    @Test func preloadsNeighboursOnceTheCurrentPageLoads() async throws {
        let (controller, window) = makeController(book: try makeBook())
        defer { window.isHidden = true }

        let first = try #require(controller.currentPage)
        try await waitUntil { first.isLoaded }
        // The neighbour already exists and finishes loading in the background.
        let next = try #require(page(after: first, in: controller))
        try await waitUntil { next.isLoaded }
        #expect(next.pageIndex == 1)
        // Asking again returns the same preloaded page rather than a new one.
        #expect(page(after: first, in: controller) === next)
    }

    @Test func knownPageCountsAnswerTurnsBeforeThePageFinishesLoading() async throws {
        let (controller, window) = makeController(book: try makeBook())
        defer { window.isHidden = true }

        let first = try #require(controller.currentPage)
        try await waitUntil { first.isLoaded }
        let second = try #require(page(after: first, in: controller))
        settle(on: second, in: controller)

        // Fresh page object for page 2 (not loaded): the chapter's cached count still tells us page 3 exists.
        let unloaded = DCPageWebViewController(book: try makeBook(),
                                               spineIndex: 0,
                                               target: .index(1),
                                               userPreferences: DCUserPreferencesMock(),
                                               readerContext: ReaderContext(book: try makeBook()),
                                               appearance: Self.appearance) { _ in }
        #expect(!unloaded.isLoaded)
        let third = try #require(page(after: unloaded, in: controller))
        #expect(third.spineIndex == 0)
        #expect(third.target == .index(2) || third.pageIndex == 2)
    }

    @Test func reusesWebViewsOfPagesThatLeaveTheCache() async throws {
        let (controller, window) = makeController(book: try makeBook())
        defer { window.isHidden = true }

        var seen: [ObjectIdentifier] = []
        var current = try #require(controller.currentPage)
        try await waitUntil { current.isLoaded }
        if let webView = webView(of: current) { seen.append(ObjectIdentifier(webView)) }

        var reused = false
        for _ in 0..<4 {
            let next = try #require(page(after: current, in: controller))
            settle(on: next, in: controller)
            try await waitUntil { next.isLoaded }
            if let webView = webView(of: next) {
                let id = ObjectIdentifier(webView)
                reused = reused || seen.contains(id)
                seen.append(id)
            }
            current = next
        }
        #expect(reused, "turning forward should hand dropped pages' web views to new pages")
        // Pages keep landing on the right column even with reused, already-paginated web views.
        #expect(current.pageIndex == 4)
    }
}
}
