//
//  DCEpubSearchTests.swift
//  DCEpubReaderKit
//
//  Created by Liam Smith-Gales on 11/11/26.
//

import Foundation
import Testing
import DCEpubCore

@Suite("DCHTMLText")
struct DCHTMLTextTests {

    @Test func keepsOnlyBodyTextAndDropsScriptsStylesAndComments() {
        let html = """
        <html><head><title>Ignored title</title><style>p { color: red; }</style></head>
        <body class="x"><p>One <b>bold</b> word.</p><!-- hidden --><script>var t = "<p>no</p>";</script><p>Two</p></body></html>
        """
        #expect(DCHTMLText.bodyText(fromHTML: html) == "One bold word.Two")
    }

    @Test func decodesNamedAndNumericEntities() {
        let html = "<body>Tom &amp; Jerry &mdash; caf&#233; &#x2014; 5&nbsp;&lt;&gt; &unknown;</body>"
        #expect(DCHTMLText.bodyText(fromHTML: html) == "Tom & Jerry — café — 5\u{00A0}<> &unknown;")
    }

    @Test func selfClosingScriptDoesNotSwallowTheChapter() {
        let html = "<body><script src=\"a.js\"/><p>Visible</p></body>"
        #expect(DCHTMLText.bodyText(fromHTML: html) == "Visible")
    }

    @Test func documentWithoutBodyIsUsedWhole() {
        #expect(DCHTMLText.bodyText(fromHTML: "<p>Fragment</p>") == "Fragment")
    }
}

@Suite("DCEpubSearchEngine")
struct DCEpubSearchEngineTests {

    /// Builds an unzipped book with one chapter per HTML body in a temporary folder.
    private func makeBook(chapters: [String]) throws -> DCEpubBook {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let textDirectory = root.appendingPathComponent("OEBPS/Text", isDirectory: true)
        try FileManager.default.createDirectory(at: textDirectory, withIntermediateDirectories: true)

        var manifest: [DCManifestItem] = []
        var spine: [DCSpineItem] = []
        var toc: [DCTocNode] = []
        for (index, body) in chapters.enumerated() {
            let href = "Text/chapter\(index + 1).xhtml"
            let html = "<html><head><title>Search me in head</title></head><body>\(body)</body></html>"
            try html.write(to: root.appendingPathComponent("OEBPS/\(href)"), atomically: true, encoding: .utf8)
            manifest.append(DCManifestItem(id: "c\(index + 1)", href: href, mediaType: "application/xhtml+xml"))
            spine.append(DCSpineItem(idref: "c\(index + 1)", linear: true))
            toc.append(DCTocNode(label: "Chapter \(index + 1)", href: href, children: []))
        }
        return DCEpubBook(packagePath: "OEBPS/content.opf",
                          metadata: DCOPFMetadata(),
                          manifest: manifest,
                          spine: spine,
                          toc: toc,
                          resourcesRoot: root)
    }

    @Test func findsCaseInsensitiveMatchesInReadingOrderWithOccurrences() async throws {
        let book = try makeBook(chapters: [
            "<p>The whale. A <i>Whale</i>!</p>",
            "<p>No match here.</p>",
            "<p>Last WHALE.</p>"
        ])
        let results = await DCEpubSearchEngine(book: book).search("whale")

        #expect(results.map(\.spineIndex) == [0, 0, 2])
        #expect(results.map(\.occurrence) == [0, 1, 0])
        #expect(results.map(\.match) == ["whale", "Whale", "WHALE"])
        #expect(results.first?.chapterTitle == "Chapter 1")
    }

    @Test func matchesAcrossInlineTagsAndIgnoresTheHead() async throws {
        let book = try makeBook(chapters: ["<p>Moby <b>Di</b>ck</p>"])
        let engine = DCEpubSearchEngine(book: book)

        #expect(await engine.search("Moby Dick").count == 1)
        #expect(await engine.search("search me").isEmpty)
    }

    @Test func snippetsCollapseWhitespaceAndEllipsiseLongContext() async throws {
        let body = "<p>\(String(repeating: "a ", count: 50))needle\n\n   tail \(String(repeating: "b ", count: 50))</p>"
        let book = try makeBook(chapters: [body])
        let result = try #require(await DCEpubSearchEngine(book: book, contextLength: 10).search("needle").first)

        #expect(result.prefix.hasPrefix("…"))
        #expect(result.prefix.hasSuffix("a "))
        #expect(result.suffix.hasPrefix(" tail"))
        #expect(result.suffix.hasSuffix("…"))
        #expect(!result.suffix.contains("\n"))
    }

    @Test func respectsTheLimitAndIgnoresBlankQueries() async throws {
        let book = try makeBook(chapters: ["<p>x x x x x</p>"])
        let engine = DCEpubSearchEngine(book: book)

        #expect(await engine.search("x", limit: 2).count == 2)
        #expect(await engine.search("   ").isEmpty)
    }
}
