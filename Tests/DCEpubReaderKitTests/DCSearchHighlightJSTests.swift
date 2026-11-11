//
//  DCSearchHighlightJSTests.swift
//  DCEpubReaderKit
//
//  Created by Liam Smith-Gales on 11/11/26.
//

import Foundation
import Testing
import WebKit
import DCEpubCore

/// Checks that `highlightSearchOccurrence` in EpubUtil.js marks the same match the Swift search
/// engine reported, since the reader relies on both sides numbering matches identically.
@MainActor
@Suite("Search highlight JS")
struct DCSearchHighlightJSTests {

    private static let epubUtilURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("../../Sources/DCEpubRendering/Resources/EpubUtil.js")
        .standardizedFileURL

    /// Returns the text inside the current search marks, then removes them so the next lookup starts clean.
    private static let takeMarkedText = """
    (function () {
        const spans = Array.from(document.querySelectorAll('.highlight_search'));
        const text = spans.map(function (s) { return s.textContent; }).join('');
        spans.forEach(function (s) { s.replaceWith.apply(s, Array.from(s.childNodes)); });
        document.body.normalize();
        return text;
    })()
    """

    private func loadPage(body: String) async throws -> WKWebView {
        let script = try String(contentsOf: Self.epubUtilURL, encoding: .utf8)
        let html = "<html><head><script>\(script)</script></head><body>\(body)</body></html>"
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let loader = NavigationWaiter()
        webView.navigationDelegate = loader
        try await loader.load(html, in: webView)
        return webView
    }

    @Test func marksEverySwiftMatchInOrder() async throws {
        let body = """
        <p>The whale. A <i>Wh</i>ale!</p>
        <script>var whale = "not text";</script>
        <style>.whale { color: red; }</style>
        <p>Tom &amp; whale &mdash; <span class="highlight-yellow">wHaLe</span> end</p>
        """
        let swiftText = DCHTMLText.bodyText(fromHTML: "<body>\(body)</body>")
        let swiftMatches = Self.matches(of: "whale", in: swiftText)
        #expect(swiftMatches == ["whale", "Whale", "whale", "wHaLe"])

        let webView = try await loadPage(body: body)
        for (occurrence, expected) in swiftMatches.enumerated() {
            let page = try await webView.evaluateJavaScript("highlightSearchOccurrence('whale', \(occurrence), false)") as? String
            #expect(page == "0")
            let marked = try await webView.evaluateJavaScript(Self.takeMarkedText) as? String
            #expect(marked == expected, "occurrence \(occurrence)")
        }
    }

    @Test func reportsMissingOccurrences() async throws {
        let webView = try await loadPage(body: "<p>one match</p>")
        let page = try await webView.evaluateJavaScript("highlightSearchOccurrence('match', 1, false)") as? String
        #expect(page == "-1")
    }

    private static func matches(of query: String, in text: String) -> [String] {
        var matches: [String] = []
        var range = text.startIndex..<text.endIndex
        while let found = text.range(of: query, options: .caseInsensitive, range: range) {
            matches.append(String(text[found]))
            range = found.upperBound..<text.endIndex
        }
        return matches
    }
}

@MainActor
private final class NavigationWaiter: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    func load(_ html: String, in webView: WKWebView) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume()
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
