//
//  DCSelectionMenuTests.swift
//  DCEpubReaderKit
//
//  Created by Liam Smith-Gales on 11/11/26.
//

import Foundation
import Testing
import UIKit
import WebKit
import DCEpubCore
import DCEpubParser
@testable import DCEpubRendering

/// Highlight styles and the Books-style selection menu.
@Suite("Selection menu")
struct DCSelectionMenuTests {

    @Test func highlightsSavedBeforeStylesKeepTheirLook() throws {
        // A highlight and a note as stored before `style` existed.
        let json = """
        [{"uuid":"a","bookId":"b","chapterId":"c","spineIndex":0,"type":"H","text":"t","coords":"1|0",
          "note":"","chapterTitle":"","dateCreated":0,"dateUpdated":0},
         {"uuid":"n","bookId":"b","chapterId":"c","spineIndex":0,"type":"N","text":"t","coords":"1|0",
          "note":"x","chapterTitle":"","dateCreated":0,"dateUpdated":0}]
        """
        let marks = try JSONDecoder().decode([DCHighlight].self, from: Data(json.utf8))
        #expect(marks.map(\.style) == [nil, nil])
        #expect(marks.map(\.displayStyle) == [.yellow, .underline])
    }

    @Test func styleSurvivesEncoding() throws {
        let highlight = DCHighlight(uuid: "a", bookId: "b", chapterId: "c", spineIndex: 0,
                                    type: .highlight, text: "t", coords: "1|0", style: .purple)
        let decoded = try JSONDecoder().decode(DCHighlight.self, from: JSONEncoder().encode(highlight))
        #expect(decoded.style == .purple)
        #expect(decoded.displayStyle.cssClass == "highlight-purple")
    }

    @Test func everyStyleHasAStylesheetClass() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Sources/DCEpubRendering/Resources/Style.css")
        let css = try String(contentsOf: url, encoding: .utf8)
        for style in DCHighlightStyle.allCases {
            #expect(css.contains(".\(style.cssClass)"), "Missing \(style.cssClass)")
        }
    }

    @Test @MainActor func lookUpKeepsSystemCommandsExceptWebSearch() {
        let lookUp = UICommand(title: "Look Up", action: NSSelectorFromString("_define:"))
        let translate = UICommand(title: "Translate", action: NSSelectorFromString("_translate:"))
        let searchWeb = UICommand(title: "Search Web", action: NSSelectorFromString("_searchWeb:"))
        let menu = UIMenu(children: [lookUp, translate, searchWeb])
        let kept = DCWebView.lookUpCommands(in: menu).compactMap { ($0 as? UICommand)?.title }
        #expect(kept == ["Look Up", "Translate"])
    }

    @Test @MainActor func searchFromTheMenuOpensTheBookSearch() throws {
        let url = try #require(Bundle.module.url(forResource: "MinimalEPUB", withExtension: nil, subdirectory: "Fixtures"))
        let book = try DCEpubParser.parse(from: url)
        let reader = DCReaderViewModel(book: book,
                                       spineIndex: 0,
                                       userPreferencesProtocol: DCUserPreferencesMock(),
                                       delegate: nil)
        reader.handle(.searchBook(query: "chapter"), chapterURL: nil)
        #expect(reader.showSearch)
        #expect(reader.searchViewModel.query == "chapter")
    }
}

extension WebKitBackedTests {

    @MainActor
    @Suite("Selection menu layout")
    struct DCSelectionMenuLayoutTests {

        @Test func menuMatchesBooks() {
            let webView = DCWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 480),
                                    configuration: WKWebViewConfiguration())
            let translate = UICommand(title: "Translate", action: NSSelectorFromString("_translate:"))
            let sections = webView.selectionMenuElements(systemLookUp: [translate]).compactMap { $0 as? UIMenu }
            #expect(sections.count == 4)
            // Swatches are image-only, named for VoiceOver.
            #expect(sections[0].children.allSatisfy { $0.title.isEmpty && $0.image != nil })
            #expect(sections[0].children.map(\.accessibilityLabel) == ["Yellow", "Green", "Blue", "Pink", "Purple", "Underline"])
            let titles = sections.dropFirst().map { $0.children.map(\.title) }
            #expect(titles == [
                ["Add Note"],
                ["Translate", "Search", "Copy"],
                ["Share…"]
            ])
            #expect(sections.allSatisfy { $0.options.contains(.displayInline) })
            if #available(iOS 17.0, *) {
                #expect(sections[0].options.contains(.displayAsPalette))
            }
        }

        @Test func lookUpFallsBackWhenTheSystemHasNone() {
            let webView = DCWebView(frame: .zero, configuration: WKWebViewConfiguration())
            let sections = webView.selectionMenuElements(systemLookUp: []).compactMap { $0 as? UIMenu }
            #expect(sections[2].children.map(\.title) == ["Look Up", "Search", "Copy"])
        }
    }
}

extension WebKitBackedTests {

    /// Saved highlights are redrawn from coordinates taken while other highlights were already in
    /// the page; colored ones must be skipped like yellow ones, or later coords point elsewhere.
    @MainActor
    @Suite("Highlight colors JS")
    struct DCHighlightColorsJSTests {

        private static let resources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Sources/DCEpubRendering/Resources")
            .standardizedFileURL

        private static let simpleBody = "<p>Alpha beta gamma delta epsilon.</p>"

        /// A section of the accessibility test book, where the bug was seen on device.
        private static let bookBody = """
        <section>
          <h2>Performing the tests </h2>
          <p>The Reading Systems will be evaluated by various testers using different combinations of platforms and assistive technologies. There will be different sets of test results for each combination. Testers may perform the tests given in this
            book using keyboard, mouse or touch/gestures as input.</p>
          <p>Each test includes a description of its purpose.</p>
        </section>
        """

        private func loadPage(body: String = simpleBody) async throws -> WKWebView {
            let helper = try String(contentsOf: Self.resources.appendingPathComponent("EpubHelper.js"), encoding: .utf8)
            let util = try String(contentsOf: Self.resources.appendingPathComponent("EpubUtil.js"), encoding: .utf8)
            // Like an EPUB chapter: the XML declaration (parsed as a comment) and doctype come before <html>.
            let html = """
            <?xml version="1.0" encoding="utf-8"?>
            <!DOCTYPE html>
            <html><head><script>\(helper)</script><script>\(util)</script></head><body>\(body)</body></html>
            """
            let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
            let loader = NavigationWaiter()
            webView.navigationDelegate = loader
            try await loader.load(html, in: webView)
            return webView
        }

        /// Selects `word` in whichever text node holds it, as the reader does before highlighting.
        private func select(_ word: String, in webView: WKWebView) async throws {
            _ = try await webView.evaluateJavaScript("""
            (function () {
                const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
                let node;
                while ((node = walker.nextNode())) {
                    const start = node.nodeValue.indexOf('\(word)');
                    if (start < 0) continue;
                    const range = document.createRange();
                    range.setStart(node, start);
                    range.setEnd(node, start + \(word.count));
                    const selection = window.getSelection();
                    selection.removeAllRanges();
                    selection.addRange(range);
                    return 'ok';
                }
                return 'missing';
            })()
            """)
        }

        private struct Saved {
            let uuid: String
            let coords: String
            let cssClass: String
            let text: String
        }

        private func highlight(_ word: String, style: DCHighlightStyle, in webView: WKWebView) async throws -> Saved {
            try await select(word, in: webView)
            let coords = try #require(try await webView.evaluateJavaScript("getCoordsFromSelection()") as? String)
            let uuid = try #require(try await webView.evaluateJavaScript("highlightString('\(style.cssClass)')") as? String)
            _ = try await webView.evaluateJavaScript("window.getSelection().removeAllRanges(); 'ok'")
            return Saved(uuid: uuid, coords: coords, cssClass: style.cssClass, text: word)
        }

        private func drawn(_ uuid: String, in webView: WKWebView) async throws -> String? {
            try await webView.evaluateJavaScript("""
            (function () {
                const el = document.getElementById('\(uuid)');
                return el ? el.className + ':' + el.textContent : null;
            })()
            """) as? String
        }

        @Test func colorsAndNotesRedrawWhereTheyWereMade() async throws {
            let live = try await loadPage()
            let green = try await highlight("beta", style: .green, in: live)
            let note = try await highlight("delta", style: .underline, in: live)
            let purple = try await highlight("Alpha", style: .purple, in: live)

            // Reopen the chapter and redraw from the saved coords, last first, like `loadHighlights`.
            let reopened = try await loadPage()
            for saved in [green, note, purple].sorted(by: { $0.coords > $1.coords }) {
                let js = "highlightCoords('\(saved.coords)', '\(saved.cssClass)', '\(saved.uuid)', '\(saved.text)')"
                _ = try await reopened.evaluateJavaScript(js)
            }
            #expect(try await drawn(green.uuid, in: reopened) == "highlight-green:beta")
            #expect(try await drawn(note.uuid, in: reopened) == "highlight-underline:delta")
            #expect(try await drawn(purple.uuid, in: reopened) == "highlight-purple:Alpha")
        }

        @Test func severalMarksInOneBookParagraphRedrawInPlace() async throws {
            let live = try await loadPage(body: Self.bookBody)
            let marks = [
                try await highlight("testers", style: .green, in: live),
                try await highlight("platforms", style: .purple, in: live),
                try await highlight("assistive", style: .underline, in: live)
            ]
            let reopened = try await loadPage(body: Self.bookBody)
            for saved in marks.sorted(by: { $0.coords > $1.coords }) {
                let js = "highlightCoords('\(saved.coords)', '\(saved.cssClass)', '\(saved.uuid)', '\(saved.text)')"
                _ = try await reopened.evaluateJavaScript(js)
            }
            for saved in marks {
                #expect(try await drawn(saved.uuid, in: reopened) == "\(saved.cssClass):\(saved.text)", "\(saved.text) at \(saved.coords)")
            }

        }
    }
}
