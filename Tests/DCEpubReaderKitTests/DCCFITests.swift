//
//  DCCFITests.swift
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

extension WebKitBackedTests {

    /// coords ↔ EPUB CFI, for syncing with CFI readers.
    @MainActor
    @Suite("CFI")
    struct DCCFITests {

        private static let util = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Sources/DCEpubRendering/Resources/EpubUtil.js").standardizedFileURL

        // body is /4; first <p> /2 (id "one"), second <p> /4.
        private static let body = """
        <p id="one">Hello <b>big</b> world.</p>
        <p>Second paragraph here.</p>
        """

        private func load() async throws -> WKWebView {
            let script = try String(contentsOf: Self.util, encoding: .utf8)
            let html = "<!DOCTYPE html><html><head><script>\(script)</script></head><body>\(Self.body)</body></html>"
            let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
            let loader = NavigationWaiter()
            webView.navigationDelegate = loader
            try await loader.load(html, in: webView)
            return webView
        }

        /// coords of the character `offset` into the text node containing `text`.
        private func coords(of text: String, offset: Int, in webView: WKWebView) async throws -> String {
            try #require(try await webView.evaluateJavaScript("""
            (function () {
                const w = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
                let n; while ((n = w.nextNode())) if (n.nodeValue.indexOf('\(text)') >= 0) return getCoordFromNode(n, \(offset));
                return null;
            })()
            """) as? String)
        }

        private func js(_ script: String, _ webView: WKWebView) async throws -> String? {
            try await webView.evaluateJavaScript(script) as? String
        }

        @Test func pointsMatchHandWorkedCFIs() async throws {
            let webView = try await load()
            // "world." is the text after <b>: run 3 of the first <p>; offset 2 is "r".
            let world = try await coords(of: " world.", offset: 3, in: webView)
            #expect(try await js("coordsToCFI('\(world)')", webView) == "/4/2[one]/3:3")
            let hello = try await coords(of: "Hello", offset: 0, in: webView)
            #expect(try await js("coordsToCFI('\(hello)')", webView) == "/4/2[one]/1:0")
            let second = try await coords(of: "Second", offset: 7, in: webView)
            #expect(try await js("coordsToCFI('\(second)')", webView) == "/4/4/1:7")

            // And back.
            #expect(try await js("cfiToCoords('/4/2[one]/3:3')", webView) == world)
            #expect(try await js("cfiToCoords('/4/4/1:7')", webView) == second)
        }

        @Test func rangesUseTheCommonParent() async throws {
            let webView = try await load()
            let start = try await coords(of: "Hello", offset: 2, in: webView)
            let end = try await coords(of: " world.", offset: 3, in: webView)
            let range = try #require(try await js("coordsToCFI('\(start),\(end)')", webView))
            #expect(range == "/4/2[one],/1:2,/3:3")
            #expect(try await js("cfiToCoords('\(range)')", webView) == "\(start),\(end)")
        }

        @Test func highlightWrappersDoNotChangeTheCFI() async throws {
            let webView = try await load()
            let world = try await coords(of: " world.", offset: 3, in: webView)
            // Highlight "wor" across part of the run; the CFI of the same character stays the same.
            _ = try await js("""
            (function () {
                const t = document.querySelector('#one').lastChild;
                const r = document.createRange(); r.setStart(t, 1); r.setEnd(t, 4);
                const s = window.getSelection(); s.removeAllRanges(); s.addRange(r);
                return highlightSelectionInPlace('highlight-highlight', 'h1');
            })()
            """, webView)
            // "r" is now inside the highlight; coords skip wrappers, so they're unchanged, and so is the CFI.
            let marked = try #require(try await js("""
            (function () { const t = document.getElementById('h1').firstChild; return getCoordFromNode(t, 2); })()
            """, webView))
            #expect(marked == world)
            #expect(try await js("cfiToCoords('/4/2[one]/3:3')", webView) == world)
        }

        @Test func converterRoundTripsOnABook() async throws {
            let url = try #require(Bundle.module.url(forResource: "MinimalEPUB", withExtension: nil, subdirectory: "Fixtures"))
            let book = try DCEpubParser.parse(from: url)
            let converter = DCCFIConverter(book: book)
            let idref = book.spine[0].idref
            let cfi = "epubcfi(/6/2[\(idref)]!/4/2/1:3)"
            let place = try #require(await converter.coords(fromCFI: cfi))
            #expect(place.spineIndex == 0)
            #expect(await converter.cfi(fromCoords: place.coords, spineIndex: 0) == cfi)

            // Without the idref, the step number finds the chapter.
            #expect(await converter.coords(fromCFI: "epubcfi(/6/2!/4/2/1:3)")?.coords == place.coords)
            #expect(await converter.coords(fromCFI: "epubcfi(/6/40!/4/2/1:3)") == nil)
        }
    }
}

/// The CFI's spine step comes from where `<spine>` really is in the package, as other readers take it.
@Suite("CFI spine step")
struct DCCFISpineStepTests {

    private func spineStep(packageChildren: String) throws -> Int {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).opf")
        defer { try? FileManager.default.removeItem(at: url) }
        try """
        <?xml version="1.0"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0">\(packageChildren)</package>
        """.write(to: url, atomically: true, encoding: .utf8)
        return try DCOPFParser(opfURL: url).parse().spineStep
    }

    @Test func thirdElementIsSix() throws {
        #expect(try spineStep(packageChildren: "<metadata/><manifest/><spine><itemref idref='a'/></spine>") == 6)
    }

    @Test func elementsBeforeTheSpineMoveIt() throws {
        let children = "<metadata/><manifest/><bindings/><collection role='x'><link href='a'/></collection><spine/>"
        #expect(try spineStep(packageChildren: children) == 10)
    }

    @Test @MainActor func converterUsesTheBooksStep() throws {
        let book = DCEpubBook(packagePath: "", metadata: DCOPFMetadata(), manifest: [],
                              spine: [DCSpineItem(idref: "ch1", linear: true, properties: nil)],
                              toc: [], resourcesRoot: URL(fileURLWithPath: "/"), spineStep: 8)
        #expect(DCCFIConverter.spineStep(0, in: book) == "/8/2[ch1]")
    }
}
