//
//  DCEpubSearchEngine.swift
//  DCEpubReaderKit
//
//  Created by Liam Smith-Gales on 11/11/26.
//

import Foundation

/// One match of a full-text search.
public struct DCSearchResult: Sendable, Hashable, Identifiable {
    public let spineIndex: Int
    /// 0-based index of this match among the matches in its chapter. The reader uses it to find the
    /// same match in the rendered chapter.
    public let occurrence: Int
    public let chapterTitle: String
    /// Text before the match, whitespace collapsed (ellipsised when truncated).
    public let prefix: String
    /// The matched text with the book's original casing.
    public let match: String
    /// Text after the match, whitespace collapsed (ellipsised when truncated).
    public let suffix: String

    public var id: String { "\(spineIndex)-\(occurrence)" }

    public init(spineIndex: Int,
                occurrence: Int,
                chapterTitle: String,
                prefix: String,
                match: String,
                suffix: String) {
        self.spineIndex = spineIndex
        self.occurrence = occurrence
        self.chapterTitle = chapterTitle
        self.prefix = prefix
        self.match = match
        self.suffix = suffix
    }
}

/// Case-insensitive full-text search over a book's spine.
///
/// Runs on its own actor, so searches never block the main thread. Chapter text is extracted on
/// first use and cached, so later queries on the same book only scan memory.
public actor DCEpubSearchEngine {

    public static let defaultResultLimit = 500

    private let book: DCEpubBook
    private var chapterTexts: [Int: String] = [:]
    private let contextLength: Int

    /// - Parameter contextLength: Characters of context to keep on each side of a match.
    public init(book: DCEpubBook, contextLength: Int = 40) {
        self.book = book
        self.contextLength = contextLength
    }

    /// Returns matches in reading order. Stops early when the task is cancelled (e.g. the query changed).
    public func search(_ query: String, limit: Int = defaultResultLimit) async -> [DCSearchResult] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, limit > 0 else { return [] }

        var results: [DCSearchResult] = []
        for spineIndex in book.spine.indices {
            if Task.isCancelled { return results }
            let text = chapterText(at: spineIndex)
            let title = book.chapterTitle(forSpineIndex: spineIndex) ?? ""

            var searchRange = text.startIndex..<text.endIndex
            var occurrence = 0
            // Non-overlapping, like the JS side, so occurrence numbers line up.
            while let range = text.range(of: query, options: .caseInsensitive, range: searchRange) {
                results.append(makeResult(text: text,
                                          range: range,
                                          spineIndex: spineIndex,
                                          occurrence: occurrence,
                                          chapterTitle: title))
                if results.count >= limit { return results }
                occurrence += 1
                searchRange = range.upperBound..<text.endIndex
            }
        }
        return results
    }

    private func chapterText(at spineIndex: Int) -> String {
        if let cached = chapterTexts[spineIndex] {
            return cached
        }
        var text = ""
        if let url = book.chapterURL(forSpineIndex: spineIndex),
           let html = try? String(contentsOf: url, encoding: .utf8) {
            text = DCHTMLText.bodyText(fromHTML: html)
        }
        chapterTexts[spineIndex] = text
        return text
    }

    private func makeResult(text: String,
                            range: Range<String.Index>,
                            spineIndex: Int,
                            occurrence: Int,
                            chapterTitle: String) -> DCSearchResult {
        let prefixStart = text.index(range.lowerBound, offsetBy: -contextLength, limitedBy: text.startIndex)
        let suffixEnd = text.index(range.upperBound, offsetBy: contextLength, limitedBy: text.endIndex)

        var prefix = Self.collapsingWhitespace(text[(prefixStart ?? text.startIndex)..<range.lowerBound])
        var suffix = Self.collapsingWhitespace(text[range.upperBound..<(suffixEnd ?? text.endIndex)])
        if prefixStart != nil, prefixStart != text.startIndex { prefix = "…" + prefix.drop(while: { $0 == " " }) }
        if suffixEnd != nil, suffixEnd != text.endIndex { suffix += "…" }

        return DCSearchResult(spineIndex: spineIndex,
                              occurrence: occurrence,
                              chapterTitle: chapterTitle,
                              prefix: prefix,
                              match: String(text[range]),
                              suffix: suffix)
    }

    /// Collapses runs of whitespace to one space, keeping a single leading/trailing space so the
    /// snippet still reads "word match word" when the pieces are joined.
    private static func collapsingWhitespace(_ text: Substring) -> String {
        var collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if text.first?.isWhitespace == true { collapsed = " " + collapsed }
        if text.last?.isWhitespace == true, collapsed.last != " " { collapsed += " " }
        return collapsed
    }
}
