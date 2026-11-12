//
//  DCFootnoteTests.swift
//  DCEpubReaderKit
//
//  Created by Liam Smith-Gales on 11/11/26.
//

import Foundation
import Testing
import WebKit
import DCEpubCore
import DCEpubParser
@testable import DCEpubRendering

/// Footnotes shown in a popover, and links followed inside the book.
@Suite("Footnotes and links")
struct DCFootnoteTests {

    private static let endnotes = """
    <?xml version="1.0" encoding="utf-8"?>
    <!DOCTYPE html>
    <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
    <body>
      <section epub:type="endnotes">
        <aside epub:type="endnote" id="n1">
          <p>First   paragraph of the
             note.</p>
          <p>Second paragraph. <a epub:type="backlink" href="c1.xhtml#r1">↩</a></p>
        </aside>
        <aside epub:type="endnote" id="n2"><p>Another note.</p></aside>
      </section>
    </body>
    </html>
    """

    @Test func readsANoteFromAnotherChapter() {
        let text = DCFootnoteText.text(ofElementWithId: "n1", inXHTML: Data(Self.endnotes.utf8))
        #expect(text == "First paragraph of the note.\n\nSecond paragraph.")
        #expect(DCFootnoteText.text(ofElementWithId: "n2", inXHTML: Data(Self.endnotes.utf8)) == "Another note.")
        #expect(DCFootnoteText.text(ofElementWithId: "missing", inXHTML: Data(Self.endnotes.utf8)) == nil)
    }

    @Test func readsTheNoteALinkPointsAt() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("notes-\(UUID().uuidString).xhtml")
        try Data(Self.endnotes.utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let link = try #require(URL(string: file.absoluteString + "#n2"))
        #expect(DCFootnoteText.text(forLinkTo: link) == "Another note.")
        #expect(DCFootnoteText.text(forLinkTo: file) == nil)
    }

    @Test func findsTheChapterALinkGoesTo() throws {
        let url = try #require(Bundle.module.url(forResource: "MinimalEPUB", withExtension: nil, subdirectory: "Fixtures"))
        let book = try DCEpubParser.parse(from: url)
        let last = book.spine.count - 1
        let chapter = try #require(book.chapterURL(forSpineIndex: last))
        let withFragment = try #require(URL(string: chapter.absoluteString + "#section-2"))
        #expect(book.spineIndex(forChapterURL: withFragment) == last)
        #expect(book.spineIndex(forChapterURL: chapter.deletingLastPathComponent().appendingPathComponent("nope.xhtml")) == nil)
    }
}

extension WebKitBackedTests {

    /// How EpubUtil.js classifies a tapped link (`linkAction`).
    @MainActor
    @Suite("Link taps JS")
    struct DCLinkJSTests {

        private static let util = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Sources/DCEpubRendering/Resources/EpubUtil.js")
            .standardizedFileURL

        private static let chapterURL = "file:///book/OEBPS/text/c1.xhtml"

        private static let body = """
        <p>Text<a id="r1" epub:type="noteref" href="#fn1">1</a>,
           <a id="r2" href="#fn2">2</a>,
           <a id="r3" epub:type="noteref" href="notes.xhtml#n1">3</a>,
           <a id="r4" href="c2.xhtml#start">next</a>,
           <a id="r5" href="#later">later</a>,
           <a id="r6" href="c1.xhtml#fn1">self</a>,
           <a id="r7" href="https://example.com/">web</a>.</p>
        <p id="later">Later.</p>
        <aside epub:type="footnote" id="fn1"><p>A footnote. <a epub:type="backlink" href="#r1">↩</a></p></aside>
        <aside role="doc-footnote" id="fn2"><p>One.</p><p>Two.</p></aside>
        """

        private func load() async throws -> WKWebView {
            let script = try String(contentsOf: Self.util, encoding: .utf8)
            let html = """
            <html xmlns:epub="http://www.idpf.org/2007/ops"><head>
            <script>window.dcChapterURL = '\(Self.chapterURL)';</script><script>\(script)</script>
            </head><body>\(Self.body)</body></html>
            """
            let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
            let loader = NavigationWaiter()
            webView.navigationDelegate = loader
            try await loader.load(html, in: webView)
            return webView
        }

        private func action(_ id: String, in webView: WKWebView) async throws -> [String: String] {
            let raw = try await webView.evaluateJavaScript("""
            (function () {
                const a = linkAction(document.getElementById('\(id)'));
                return a ? JSON.stringify({ kind: a.kind, text: a.text || '', url: a.url || '' }) : '';
            })()
            """) as? String
            let data = Data((raw ?? "").utf8)
            return (try? JSONSerialization.jsonObject(with: data) as? [String: String]) ?? [:]
        }

        @Test func classifiesLinks() async throws {
            let webView = try await load()
            #expect(try await action("r1", in: webView) == ["kind": "footnote", "text": "A footnote.", "url": ""])
            // A link to a footnote aside counts even without noteref, paragraphs kept apart.
            #expect(try await action("r2", in: webView)["text"] == "One.\n\nTwo.")
            #expect(try await action("r3", in: webView) == ["kind": "noteref", "text": "", "url": "file:///book/OEBPS/text/notes.xhtml#n1"])
            #expect(try await action("r4", in: webView) == ["kind": "link", "text": "", "url": "file:///book/OEBPS/text/c2.xhtml#start"])
            #expect(try await action("r5", in: webView)["kind"] == "link")
            // The chapter's own file name is the same chapter.
            #expect(try await action("r6", in: webView)["kind"] == "footnote")
            #expect(try await action("r7", in: webView) == ["kind": "link", "text": "", "url": "https://example.com/"])
        }

        @Test func headingSplitAcrossPagesOpensOnItsFirstPage() async throws {
            let script = try String(contentsOf: Self.util, encoding: .utf8)
            // A long heading that pagination splits over pages 0 and 1.
            let filler = String(repeating: "<p>Filler line of text.</p>", count: 18)
            let heading = "<h2 id=\"target\">" + String(repeating: "Heading words ", count: 40) + "</h2>"
            let viewport = "<meta name='viewport' content='width=device-width, initial-scale=1.0'>"
            let html = "<html><head>\(viewport)<script>\(script)</script></head><body>\(filler)\(heading)<p>After.</p></body></html>"
            let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
            let loader = NavigationWaiter()
            webView.navigationDelegate = loader
            try await loader.load(html, in: webView)
            _ = try await webView.evaluateJavaScript("applyHorizontalPagination(); 'ok'")
            let boxes = try #require(try await webView.evaluateJavaScript("""
            (function () {
                const rects = Array.from(document.getElementById('target').getClientRects());
                return JSON.stringify(rects.map(function (r) { return Math.floor((r.left + window.scrollX) / window.innerWidth); }));
            })()
            """) as? String)
            let pages = try JSONDecoder().decode([Int].self, from: Data(boxes.utf8))
            #expect(Set(pages).count > 1, "the heading should span pages: \(pages)")
            let page = try await webView.evaluateJavaScript("getPageForElementId('target', false)") as? String
            #expect(page == String(pages.min() ?? -1))
        }
    }
}
