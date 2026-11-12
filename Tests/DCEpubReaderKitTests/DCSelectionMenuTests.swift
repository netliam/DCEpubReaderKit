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

    @Test @MainActor func mergedHighlightsKeepTheirNotesInOrder() {
        func mark(_ note: String) -> DCHighlight {
            DCHighlight(uuid: UUID().uuidString, bookId: "b", chapterId: "c", spineIndex: 0,
                        type: .note, text: "t", coords: "1|0", note: note)
        }
        #expect(DCWebView.mergedNote([mark("First."), mark("  "), mark("Second.")]) == "First.\n\nSecond.")
        #expect(DCWebView.mergedNote([]) == "")
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

        @Test func tappedHighlightMenuMatchesBooks() {
            let webView = DCWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 480),
                                    configuration: WKWebViewConfiguration())
            var highlight = DCHighlight(uuid: "h", bookId: "b", chapterId: "c", spineIndex: 0,
                                        type: .highlight, text: "t", coords: "1|0", style: .green)
            var sections = webView.highlightMenuElements(for: highlight).compactMap { $0 as? UIMenu }
            #expect(sections.count == 4)
            // The current color is marked (with a checked swatch, and for VoiceOver).
            #expect(sections[0].children.map(\.accessibilityLabel) == ["Yellow", "Green, current", "Blue", "Pink", "Purple", "Underline"])
            #expect(sections.dropFirst().map { $0.children.map(\.title) } == [
                ["Add Note"],
                ["Copy", "Share…"],
                ["Delete Highlight"]
            ])

            highlight.note = "Thought"
            sections = webView.highlightMenuElements(for: highlight).compactMap { $0 as? UIMenu }
            #expect(sections[1].children.map(\.title) == ["Edit Note"])
            #expect(sections[3].children.map(\.title) == ["Delete Highlight and Note"])
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
            return try await highlightSelection(style: style, in: webView)
        }

        /// Highlights the current selection like `DCWebView.saveSelection`: coords, text, then draw.
        private func highlightSelection(style: DCHighlightStyle, in webView: WKWebView) async throws -> Saved {
            let coords = try #require(try await webView.evaluateJavaScript("getCoordsFromSelection()") as? String)
            let text = try #require(try await webView.evaluateJavaScript("window.getSelection().toString()") as? String)
            let id = UUID().uuidString
            let uuid = try #require(try await webView.evaluateJavaScript("highlightSelectionInPlace('\(style.cssClass)', '\(id)')") as? String)
            _ = try await webView.evaluateJavaScript("window.getSelection().removeAllRanges(); 'ok'")
            return Saved(uuid: uuid, coords: coords, cssClass: style.cssClass,
                         text: text.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        private func redraw(_ marks: [Saved], in webView: WKWebView) async throws {
            for saved in marks.sorted(by: { $0.coords > $1.coords }) {
                let text = saved.text.replacingOccurrences(of: "\n", with: "\\n")
                let js = "highlightCoords('\(saved.coords)', '\(saved.cssClass)', '\(saved.uuid)', '\(text)')"
                _ = try await webView.evaluateJavaScript(js)
            }
        }

        /// The highlight's class and text across all its parts, as "class:text".
        private func drawn(_ uuid: String, in webView: WKWebView) async throws -> String? {
            try await webView.evaluateJavaScript("""
            (function () {
                const parts = Array.from(document.querySelectorAll('[data-dc-highlight="\(uuid)"]'));
                if (!parts.length) return null;
                const classes = Array.from(new Set(parts.map(function (p) { return p.className; })));
                return classes.join('|') + ':' + parts.map(function (p) { return p.textContent; }).join(' ');
            })()
            """) as? String
        }

        /// Selects from `start` to `end`, which may be in different paragraphs.
        private func select(from start: String, to end: String, in webView: WKWebView) async throws {
            _ = try await webView.evaluateJavaScript("""
            (function () {
                function find(word, fromEnd) {
                    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
                    let node;
                    while ((node = walker.nextNode())) {
                        const at = node.nodeValue.indexOf(word);
                        if (at >= 0) return [node, fromEnd ? at + word.length : at];
                    }
                    return null;
                }
                const a = find('\(start)', false), b = find('\(end)', true);
                const range = document.createRange();
                range.setStart(a[0], a[1]);
                range.setEnd(b[0], b[1]);
                const selection = window.getSelection();
                selection.removeAllRanges();
                selection.addRange(range);
                return 'ok';
            })()
            """)
        }

        private func text(of webView: WKWebView) async throws -> String? {
            try await webView.evaluateJavaScript("document.body.innerHTML") as? String
        }

        @Test func colorsAndNotesRedrawWhereTheyWereMade() async throws {
            let live = try await loadPage()
            let green = try await highlight("beta", style: .green, in: live)
            let note = try await highlight("delta", style: .underline, in: live)
            let purple = try await highlight("Alpha", style: .purple, in: live)

            // Reopen the chapter and redraw from the saved coords, last first, like `loadHighlights`.
            let reopened = try await loadPage()
            try await redraw([green, note, purple], in: reopened)
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
            try await redraw(marks, in: reopened)
            for saved in marks {
                #expect(try await drawn(saved.uuid, in: reopened) == "\(saved.cssClass):\(saved.text)", "\(saved.text) at \(saved.coords)")
            }
        }

        @Test func highlightAcrossParagraphsKeepsThemApartAndRedraws() async throws {
            let live = try await loadPage(body: Self.bookBody)
            let before = try await live.evaluateJavaScript("document.querySelectorAll('p').length") as? Int
            try await select(from: "combination.", to: "Each test", in: live)
            let saved = try await highlightSelection(style: .blue, in: live)
            #expect(saved.text.contains("\n"))
            #expect(try await live.evaluateJavaScript("document.querySelectorAll('p').length") as? Int == before)
            // The text after the selection isn't highlighted.
            let livePart = try #require(try await drawn(saved.uuid, in: live))
            #expect(livePart.hasPrefix("highlight-blue:combination."))
            #expect(livePart.hasSuffix("Each test"))

            // A highlight in a later paragraph, made after the long one, still lands in place.
            let later = try await highlight("purpose", style: .yellow, in: live)

            let reopened = try await loadPage(body: Self.bookBody)
            try await redraw([saved, later], in: reopened)
            #expect(try await drawn(saved.uuid, in: reopened) == livePart)
            #expect(try await drawn(later.uuid, in: reopened) == "highlight-yellow:purpose")
        }

        @Test func overlappingSelectionIsRefused() async throws {
            let webView = try await loadPage()
            _ = try await highlight("beta", style: .green, in: webView)
            try await select(from: "Alpha", to: "gamma", in: webView)
            let result = try await webView.evaluateJavaScript("highlightSelectionInPlace('highlight-yellow', 'x')")
            #expect(result as? String == nil)
            #expect(try await drawn("x", in: webView) == nil)
        }

        @Test func overlappingSelectionMergesWithTheHighlightsItTouches() async throws {
            let webView = try await loadPage()
            let beta = try await highlight("beta", style: .green, in: webView)
            let gammaDelta = try await { () async throws -> Saved in
                try await select(from: "gamma", to: "delta", in: webView)
                return try await highlightSelection(style: .pink, in: webView)
            }()

            // A selection from "Alpha" into "gamma" touches both.
            try await select(from: "Alpha", to: "gam", in: webView)
            let raw = try #require(try await webView.evaluateJavaScript("expandSelectionOverHighlights()") as? String)
            let removed = try JSONDecoder().decode([String].self, from: Data(raw.utf8))
            #expect(Set(removed) == [beta.uuid, gammaDelta.uuid])
            let merged = try await highlightSelection(style: .yellow, in: webView)
            #expect(merged.text == "Alpha beta gamma delta", "widened to cover both")
            #expect(try await drawn(merged.uuid, in: webView) == "highlight-yellow:Alpha beta gamma delta")
            #expect(try await drawn(beta.uuid, in: webView) == nil)
            #expect(try await drawn(gammaDelta.uuid, in: webView) == nil)

            // It redraws in place from its saved coords.
            let reopened = try await loadPage()
            try await redraw([merged], in: reopened)
            #expect(try await drawn(merged.uuid, in: reopened) == "highlight-yellow:Alpha beta gamma delta")
        }

        @Test func selectionWithoutHighlightsIsLeftAlone() async throws {
            let webView = try await loadPage()
            try await select(from: "beta", to: "gamma", in: webView)
            #expect(try await webView.evaluateJavaScript("expandSelectionOverHighlights()") as? String == "[]")
            #expect(try await webView.evaluateJavaScript("window.getSelection().toString()") as? String == "beta gamma")
        }

        @Test func deletingRestoresThePageForLaterCoords() async throws {
            let webView = try await loadPage(body: Self.bookBody)
            let original = try await text(of: webView)
            try await select(from: "different", to: "Each", in: webView)
            let long = try await highlightSelection(style: .pink, in: webView)
            _ = try await webView.evaluateJavaScript("removeHighlightById('\(long.uuid)')")
            #expect(try await drawn(long.uuid, in: webView) == nil)
            #expect(try await text(of: webView) == original)
            #expect(try await webView.evaluateJavaScript("""
            (function () {
                const p = document.querySelector('p');
                return Array.from(p.childNodes).filter(function (n) { return n.nodeType === 3; }).length;
            })()
            """) as? Int == 1)

            // Coords taken now match a freshly opened chapter.
            let later = try await highlight("assistive", style: .underline, in: webView)
            let reopened = try await loadPage(body: Self.bookBody)
            try await redraw([later], in: reopened)
            #expect(try await drawn(later.uuid, in: reopened) == "highlight-underline:assistive")
        }

        @Test func restyleAndNoteMarkerApplyToEveryPart() async throws {
            let webView = try await loadPage(body: Self.bookBody)
            try await select(from: "combination.", to: "Each test", in: webView)
            let saved = try await highlightSelection(style: .yellow, in: webView)
            _ = try await webView.evaluateJavaScript("setHighlightStyleById('\(saved.uuid)', 'highlight-green')")
            #expect(try await drawn(saved.uuid, in: webView)?.hasPrefix("highlight-green:") == true)

            let markers = """
            (function () {
                const parts = Array.from(document.querySelectorAll('[data-dc-highlight="\(saved.uuid)"]'));
                return parts.map(function (p) { return p.hasAttribute('data-dc-note') ? '1' : '0'; }).join('');
            })()
            """
            _ = try await webView.evaluateJavaScript("setHighlightNoteById('\(saved.uuid)', true)")
            let marked = try #require(try await webView.evaluateJavaScript(markers) as? String)
            #expect(marked.hasSuffix("1") && marked.dropLast().allSatisfy { $0 == "0" })
            _ = try await webView.evaluateJavaScript("setHighlightNoteById('\(saved.uuid)', false)")
            #expect(try await webView.evaluateJavaScript(markers) as? String == String(repeating: "0", count: marked.count))
        }

        @Test func redrawingAHighlightAlreadyShownChangesNothing() async throws {
            let webView = try await loadPage()
            let saved = try await highlight("gamma", style: .purple, in: webView)
            let html = try await text(of: webView)
            try await redraw([saved], in: webView)
            #expect(try await text(of: webView) == html)
        }

        @Test func tapsOnAHighlightAreRecognized() async throws {
            let webView = try await loadPage()
            let saved = try await highlight("gamma", style: .purple, in: webView)
            let point = try #require(try await webView.evaluateJavaScript("""
            (function () {
                const r = document.getElementById('\(saved.uuid)').getBoundingClientRect();
                return [r.left + r.width / 2, r.top + r.height / 2];
            })()
            """) as? [Double])
            #expect(try await webView.evaluateJavaScript("isHighlightAtPoint(\(point[0]), \(point[1]))") as? String == "true")
            #expect(try await webView.evaluateJavaScript("isHighlightAtPoint(\(point[0]), 400)") as? String == "false")
        }
    }
}

/// Add Note highlights in the last color used, like Books, instead of always underlining.
@Suite("Note colors", .serialized)
struct DCNoteColorTests {

    @Test @MainActor func lastUsedColorIsRememberedAndStartsYellow() throws {
        let defaults = try #require(UserDefaults(suiteName: "DCNoteColorTests-\(UUID().uuidString)"))
        let previous = DCHighlightStyle.store
        DCHighlightStyle.store = defaults
        defer { DCHighlightStyle.store = previous }

        #expect(DCHighlightStyle.lastUsed == .yellow)
        DCHighlightStyle.lastUsed = .purple
        #expect(DCHighlightStyle.lastUsed == .purple)
        DCHighlightStyle.lastUsed = .underline
        #expect(DCHighlightStyle.lastUsed == .underline)
    }

    @Test func notesSavedAsUnderlinesKeepThem() {
        // Notes made before this change were stored with the underline style.
        let old = DCHighlight(uuid: "n", bookId: "b", chapterId: "c", spineIndex: 0, type: .note,
                              text: "t", coords: "1|0", style: .underline)
        #expect(old.displayStyle == .underline)
        let colored = DCHighlight(uuid: "m", bookId: "b", chapterId: "c", spineIndex: 0, type: .note,
                                  text: "t", coords: "1|0", style: .green)
        #expect(colored.displayStyle == .green)
    }
}

/// Share from a selection or a highlight sends the passage with the book's title, like ⋯ → Share.
@Suite("Sharing a passage")
struct DCShareTextTests {
    @Test func quotesThePassageThenTitleAndAuthor() throws {
        let url = try #require(Bundle.module.url(forResource: "MinimalEPUB", withExtension: nil, subdirectory: "Fixtures"))
        let book = try DCEpubParser.parse(from: url)
        var byline = book.bookTitle
        if let author = book.metadata.creators.first, !author.isEmpty { byline += " by \(author)" }
        #expect(book.shareText(quoting: "Call me Ishmael.") == "“Call me Ishmael.”\n\n\(byline)")
        #expect(book.shareText(quoting: nil) == byline)
        #expect(book.shareText(quoting: "") == byline)
    }
}
