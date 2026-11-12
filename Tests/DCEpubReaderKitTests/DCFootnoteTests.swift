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
        <p><img id="pic" src="../images/fig1.png" alt="A figure"/>
           <a id="r8" href="#later"><img id="linked" src="../images/fig2.png" alt=""/></a></p>
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

        @Test func picturesOpenFullScreenUnlessTheyAreLinks() async throws {
            let webView = try await load()
            let raw = try #require(try await webView.evaluateJavaScript("""
            JSON.stringify(imageAction(document.getElementById('pic')))
            """) as? String)
            let image = try #require(try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
            #expect(image["kind"] as? String == "image")
            #expect(image["url"] as? String == "file:///book/OEBPS/images/fig1.png")
            #expect(image["alt"] as? String == "A figure")
            // A picture inside a link follows the link (the click listener checks links first).
            #expect(try await action("r8", in: webView)["kind"] == "link")
        }

        /// Wide landscape pages show two columns (a spread); pages stay one screen apart.
        @Test func landscapePagesShowTwoColumnsWhenAllowed() async throws {
            let script = try String(contentsOf: Self.util, encoding: .utf8)
            let viewport = "<meta name='viewport' content='width=device-width, initial-scale=1.0'>"
            let text = String(repeating: "<p>A line of text that goes on for a while to fill the columns of the page.</p>", count: 60)
            func layout(allow: Bool) async throws -> [String: Double] {
                let html = "<html><head>\(viewport)<script>window.dcAllowSpreads = \(allow);</script><script>\(script)</script></head><body>\(text)</body></html>"
                let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 400))
                let loader = NavigationWaiter()
                webView.navigationDelegate = loader
                try await loader.load(html, in: webView)
                let raw = try #require(try await webView.evaluateJavaScript("""
                (function () {
                    const pages = Number(applyHorizontalPagination());
                    const lefts = Array.from(document.querySelectorAll('p')).map(function (p) { return p.getClientRects()[0].left; });
                    const onFirstPage = lefts.filter(function (l) { return l < window.innerWidth; });
                    return JSON.stringify({ pages: pages, perPage: columnsPerPage(), columns: Number(document.body.style.webkitColumnCount),
                                            secondColumn: Math.max.apply(null, onFirstPage), width: window.innerWidth,
                                            scrollWidth: document.scrollingElement.scrollWidth });
                })()
                """) as? String)
                return try JSONDecoder().decode([String: Double].self, from: Data(raw.utf8))
            }
            let spread = try await layout(allow: true)
            #expect(spread["perPage"] == 2)
            #expect(spread["columns"] == (spread["pages"] ?? 0) * 2)
            #expect(abs((spread["secondColumn"] ?? 0) - (spread["width"] ?? 0) / 2) < 2, "\(spread)")
            #expect(abs((spread["scrollWidth"] ?? 0) - (spread["pages"] ?? 0) * (spread["width"] ?? 0)) < 2, "\(spread)")

            let single = try await layout(allow: false)
            #expect(single["perPage"] == 1)
            #expect((single["pages"] ?? 0) > (spread["pages"] ?? 0))
        }

        /// Note markers sit in the margin beside a noted passage's last line, outside the text.
        @Test func noteMarkersSitInTheMarginWithoutMovingText() async throws {
            let script = try String(contentsOf: Self.util, encoding: .utf8)
            // The reader's stylesheet too: its rules (e.g. `div { max-width }`) apply to the markers.
            let css = try String(contentsOf: Self.util.deletingLastPathComponent().appendingPathComponent("Style.css"), encoding: .utf8)
            let viewport = "<meta name='viewport' content='width=device-width, initial-scale=1.0'><style>\(css)</style>"
            let text = String(repeating: "<p>Some words to fill a line or two of the page here.</p>", count: 40)
                + "<p id='p'>The noted passage is here.</p>"
            func load(width: CGFloat, paged: Bool) async throws -> WKWebView {
                let html = "<html><head>\(viewport)<script>window.dcAllowSpreads = true;</script><script>\(script)</script></head><body>\(text)</body></html>"
                let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: width, height: 480))
                let loader = NavigationWaiter()
                webView.navigationDelegate = loader
                try await loader.load(html, in: webView)
                _ = try await webView.evaluateJavaScript(paged ? "applyHorizontalPagination(); 'ok'" : "applyVerticalPagination(); 'ok'")
                _ = try await webView.evaluateJavaScript("""
                (function () {
                    const t = document.getElementById('p').firstChild;
                    const r = document.createRange(); r.setStart(t, 4); r.setEnd(t, 10);
                    const s = window.getSelection(); s.removeAllRanges(); s.addRange(r);
                    highlightSelectionInPlace('highlight-yellow', 'n1');
                    return 'ok';
                })()
                """)
                return webView
            }
            let measure = """
            (function () {
                const before = document.getElementById('p').getBoundingClientRect();
                setHighlightNoteById('n1', true);
                const after = document.getElementById('p').getBoundingClientRect();
                const m = document.querySelector('.dc-note-marker');
                const part = document.querySelector('[data-dc-highlight="n1"]').getBoundingClientRect();
                return JSON.stringify({
                    moved: before.left !== after.left || before.top !== after.top || before.height !== after.height ? 1 : 0,
                    markerLeft: m ? parseFloat(m.style.left) - window.scrollX : -1,
                    markerTop: m ? parseFloat(m.style.top) - window.scrollY : -1,
                    lineTop: part.top, lineBottom: part.bottom, width: window.innerWidth,
                    inBody: m && document.body.contains(m) ? 1 : 0, text: m ? m.textContent.length : -1,
                    markerWidth: m ? m.getBoundingClientRect().width : -1
                });
            })()
            """
            func run(_ webView: WKWebView) async throws -> [String: Double] {
                let raw = try #require(try await webView.evaluateJavaScript(measure) as? String)
                return try JSONDecoder().decode([String: Double].self, from: Data(raw.utf8))
            }

            // Paged: in the column gap at the right of the page.
            let paged = try await load(width: 320, paged: true)
            let pageIndex = try #require(try await paged.evaluateJavaScript(
                "String(Math.floor((document.getElementById('p').getClientRects()[0].left + window.scrollX) / window.innerWidth))") as? String)
            _ = try await paged.evaluateJavaScript("scrollToHorizontalPage(\(pageIndex)); 'ok'")
            let p = try await run(paged)
            #expect(p["moved"] == 0, "the marker doesn't move the text")
            #expect(p["inBody"] == 0 && p["text"] == 0)
            #expect(p["markerWidth"] == 10, "drawn at its size")
            #expect(abs((p["markerLeft"] ?? 0) - (320 - 20 + 5)) < 1, "\(p)")
            #expect((p["markerTop"] ?? 0) >= (p["lineTop"] ?? 0) - 1 && (p["markerTop"] ?? 0) <= (p["lineBottom"] ?? 0), "\(p)")

            // Scrolling: the right margin.
            let scrolling = try await load(width: 320, paged: false)
            let v = try await run(scrolling)
            #expect(abs((v["markerLeft"] ?? 0) - (320 - 10)) < 1, "\(v)")

            // Removing the note or the highlight removes the marker.
            #expect(try await paged.evaluateJavaScript("setHighlightNoteById('n1', false); String(document.querySelectorAll('.dc-note-marker').length)") as? String == "0")
            _ = try await paged.evaluateJavaScript("setHighlightNoteById('n1', true); 'ok'")
            #expect(try await paged.evaluateJavaScript("removeHighlightById('n1'); String(document.querySelectorAll('.dc-note-marker').length)") as? String == "0")
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

/// Fixed-layout (pre-paginated) books: the layout is read from the package.
@Suite("Fixed layout parsing")
struct DCFixedLayoutParsingTests {
    @Test func readsRenditionLayoutFromMetadataAndItemrefs() throws {
        let fixture = try #require(Bundle.module.url(forResource: "MinimalEPUB", withExtension: nil, subdirectory: "Fixtures"))
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.copyItem(at: fixture, to: copy)
        defer { try? FileManager.default.removeItem(at: copy) }
        let opf = copy.appendingPathComponent("OEBPS/content.opf")
        var package = try String(contentsOf: opf, encoding: .utf8)
        package = package
            .replacingOccurrences(of: "<dc:language>en</dc:language>",
                                  with: "<dc:language>en</dc:language><meta property=\"rendition:layout\">pre-paginated</meta>")
            .replacingOccurrences(of: "<itemref idref=\"chapter-one\"/>",
                                  with: "<itemref idref=\"chapter-one\" properties=\"page-spread-right\"/>")
        try package.write(to: opf, atomically: true, encoding: .utf8)

        let book = try DCEpubParser.parse(from: copy)
        #expect(book.metadata.renditionLayout == "pre-paginated")
        #expect(book.spine.first?.properties == "page-spread-right")
        #expect(book.isFixedLayout(spineIndex: 0))

        let reflowable = try DCEpubParser.parse(from: fixture)
        #expect(reflowable.metadata.renditionLayout == nil)
        #expect(!reflowable.isFixedLayout(spineIndex: 0))
    }
}

/// A book's own scripts must not run in the reader (they'd reach its message handlers).
@Suite("Book scripts")
struct DCBookScriptTests {
    @Test func scriptsAndInlineHandlersAreRemoved() {
        let html = """
        <html><head><script src="evil.js"/><SCRIPT type="text/javascript">
        window.webkit.messageHandlers.linkTapped.postMessage({kind: 'link', url: 'https://x'});
        </SCRIPT></head><body onload="go()"><p>Free online=yes, and onset.</p>
        <img src="a.png" onerror='go()' alt="A"/><a href="#n" onClick=go()>n</a></body></html>
        """
        let clean = DCChapterHTMLBuilder.withoutBookScripts(html)
        #expect(!clean.lowercased().contains("<script"))
        #expect(!clean.contains("postMessage"))
        #expect(!clean.lowercased().contains("onload") && !clean.contains("onerror") && !clean.contains("onClick"))
        #expect(clean.contains("<body>"))
        #expect(clean.contains(#"<img src="a.png" alt="A"/>"#))
        #expect(clean.contains("Free online=yes, and onset."), "text is untouched")
    }
}
