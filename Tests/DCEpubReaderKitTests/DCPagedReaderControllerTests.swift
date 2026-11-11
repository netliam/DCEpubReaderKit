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
        let bodies = [String(repeating: paragraph, count: 25), "<p>Short chapter.</p>"]
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

    private func makeController(book: DCEpubBook, spineIndex: Int = 0) -> (DCPagedReaderController, UIWindow) {
        let controller = DCPagedReaderController(book: book,
                                                 spineIndex: spineIndex,
                                                 coords: nil,
                                                 configId: "test",
                                                 userPreferences: DCUserPreferencesMock(),
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
                                               readerContext: ReaderContext(book: try makeBook())) { _ in }
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
