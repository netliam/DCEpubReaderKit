//
//  DCCFIConverter.swift
//  DCEpubReaderKit
//
//  Created by Liam Smith-Gales on 11/11/26.
//

import WebKit
import DCEpubCore

/// Converts the reader's positions (`coords`, as in `DCReadingPosition` and `DCHighlight`) to EPUB
/// CFIs and back, to sync with readers that use CFIs (epub.js and others).
///
/// It lays the chapter out off screen, so it works without a reader open. It keeps the last
/// chapter loaded: convert a book's highlights chapter by chapter, with one converter.
///
/// ```swift
/// let converter = DCCFIConverter(book: book)
/// let cfi = await converter.cfi(fromCoords: highlight.coords, spineIndex: highlight.spineIndex)
/// let place = await converter.coords(fromCFI: "epubcfi(/6/4[ch1]!/4/2/1:5)")
/// ```
@MainActor
public final class DCCFIConverter {

    private let book: DCEpubBook
    private var webView: WKWebView?
    private var loadedSpineIndex: Int?
    private let loader = DCPageLoader()

    public init(book: DCEpubBook) {
        self.book = book
    }

    /// `epubcfi(/6/N[idref]!…)` for a position (`"a"`) or a highlight range (`"a,b"`).
    public func cfi(fromCoords coords: String, spineIndex: Int) async -> String? {
        guard book.spine.indices.contains(spineIndex), await load(spineIndex),
              let path = try? await webView?.evaluateJavaScriptAsync("coordsToCFI(\(Self.jsLiteral(coords)))"),
              !path.isEmpty else { return nil }
        return "epubcfi(\(Self.spineStep(spineIndex, idref: book.spine[spineIndex].idref))!\(path))"
    }

    /// The chapter and coords a CFI points to (a point, or a range as `"a,b"`).
    public func coords(fromCFI cfi: String) async -> (spineIndex: Int, coords: String)? {
        guard let (spineIndex, path) = Self.split(cfi, in: book), await load(spineIndex),
              let coords = try? await webView?.evaluateJavaScriptAsync("cfiToCoords(\(Self.jsLiteral(path)))"),
              !coords.isEmpty else { return nil }
        return (spineIndex, coords)
    }

    // MARK: Package part

    // shortcut: assumes <spine> is the package's third element (/6), as epub.js writes it; read
    // the package's own order if a sync partner writes something else.
    static func spineStep(_ spineIndex: Int, idref: String) -> String {
        "/6/\(2 * (spineIndex + 1))[\(idref)]"
    }

    /// The spine index (from the idref assertion, else the step number) and the chapter path.
    static func split(_ cfi: String, in book: DCEpubBook) -> (Int, String)? {
        var body = cfi.trimmingCharacters(in: .whitespaces)
        if body.hasPrefix("epubcfi("), body.hasSuffix(")") {
            body = String(body.dropFirst("epubcfi(".count).dropLast())
        }
        guard let bang = body.firstIndex(of: "!") else { return nil }
        let packagePart = body[..<bang]
        let path = String(body[body.index(after: bang)...])
        guard let last = packagePart.split(separator: "/").last else { return nil }
        if let open = last.firstIndex(of: "["), let close = last.firstIndex(of: "]") {
            let idref = String(last[last.index(after: open)..<close])
            if let index = book.spine.firstIndex(where: { $0.idref == idref }) { return (index, path) }
        }
        let number = Int(last.prefix { $0.isNumber }) ?? 0
        let index = number / 2 - 1
        return book.spine.indices.contains(index) ? (index, path) : nil
    }

    // MARK: Loading

    private func load(_ spineIndex: Int) async -> Bool {
        if loadedSpineIndex == spineIndex { return true }
        guard let chapterURL = book.chapterURL(forSpineIndex: spineIndex) else { return false }
        let webView = webView ?? WKWebView(frame: CGRect(x: 0, y: 0, width: 400, height: 600))
        webView.navigationDelegate = loader
        self.webView = webView
        // Same HTML as the reader, so coords mean the same nodes; layout doesn't matter here.
        let html = DCChapterHTMLBuilder.html(pathtofile: chapterURL.path,
                                             userPreferences: DCUserPreferencesMock(),
                                             appearance: DCReaderAppearance(theme: .original, isDark: false),
                                             fixedLayout: book.isFixedLayout(spineIndex: spineIndex))
        guard await loader.load(html, baseURL: chapterURL.deletingLastPathComponent(), in: webView) else {
            loadedSpineIndex = nil
            return false
        }
        loadedSpineIndex = spineIndex
        return true
    }

    private static func jsLiteral(_ string: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [string]),
              let array = String(data: data, encoding: .utf8) else { return "\"\"" }
        return String(array.dropFirst().dropLast())
    }
}
