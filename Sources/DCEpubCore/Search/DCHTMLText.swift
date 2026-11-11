//
//  DCHTMLText.swift
//  DCEpubReaderKit
//
//  Created by Liam Smith-Gales on 11/11/26.
//

import Foundation

/// Extracts the text a browser would expose for a chapter's `<body>`.
///
/// The output must match the concatenation of the body's DOM text nodes (what the reader's JS
/// searches), so the n-th match found here is the n-th match highlighted in the web view:
/// tags are removed without inserting separators, `<script>`/`<style>` content and comments are
/// dropped, whitespace is kept as-is, and character references are decoded.
public enum DCHTMLText {

    public static func bodyText(fromHTML html: String) -> String {
        decodeEntities(stripTags(body(of: html)))
    }

    /// Contents of `<body …>…</body>`, or the whole document when there is no body element.
    static func body(of html: String) -> String {
        guard let open = html.range(of: "<body", options: .caseInsensitive),
              let openEnd = html[open.upperBound...].firstIndex(of: ">") else {
            return html
        }
        let contentStart = html.index(after: openEnd)
        let close = html.range(of: "</body>", options: [.caseInsensitive, .backwards], range: contentStart..<html.endIndex)
        return String(html[contentStart..<(close?.lowerBound ?? html.endIndex)])
    }

    static func stripTags(_ html: String) -> String {
        var output = ""
        output.reserveCapacity(html.utf8.count)
        var index = html.startIndex

        while index < html.endIndex {
            let character = html[index]
            guard character == "<" else {
                output.append(character)
                index = html.index(after: index)
                continue
            }
            let rest = html[index...]
            if rest.hasPrefix("<!--") {
                index = rest.range(of: "-->")?.upperBound ?? html.endIndex
                continue
            }
            // Raw text elements: drop their content entirely, as the reader's JS ignores them.
            if let rawEnd = rawTextElementEnd(in: rest) {
                index = rawEnd
                continue
            }
            index = rest.firstIndex(of: ">").map { html.index(after: $0) } ?? html.endIndex
        }
        return output
    }

    private static func rawTextElementEnd(in tag: Substring) -> String.Index? {
        for name in ["script", "style"] {
            let opening = tag.dropFirst()
            guard opening.prefix(name.count).lowercased() == name else { continue }
            let next = opening.dropFirst(name.count).first
            guard next == nil || next == ">" || next == "/" || next?.isWhitespace == true else { continue }
            // Self-closing (<script src="…"/>) has no content to skip.
            if let tagEnd = tag.firstIndex(of: ">"), tag[tag.index(before: tagEnd)] == "/" {
                return tag.index(after: tagEnd)
            }
            return tag.range(of: "</\(name)>", options: .caseInsensitive)?.upperBound ?? tag.endIndex
        }
        return nil
    }

    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
        "nbsp": "\u{00A0}", "shy": "\u{00AD}", "copy": "©", "reg": "®", "trade": "™",
        "mdash": "—", "ndash": "–", "hellip": "…", "laquo": "«", "raquo": "»",
        "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”", "bull": "•",
        "middot": "·", "iexcl": "¡", "iquest": "¿", "deg": "°", "sect": "§", "para": "¶"
    ]

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var output = ""
        output.reserveCapacity(text.utf8.count)
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            guard character == "&",
                  let semicolon = text[index...].prefix(12).firstIndex(of: ";") else {
                output.append(character)
                index = text.index(after: index)
                continue
            }
            let name = text[text.index(after: index)..<semicolon]
            if let decoded = decode(entity: name) {
                output.append(decoded)
                index = text.index(after: semicolon)
            } else {
                output.append(character)
                index = text.index(after: index)
            }
        }
        return output
    }

    private static func decode(entity name: Substring) -> String? {
        if name.hasPrefix("#") {
            let digits = name.dropFirst()
            let value = digits.first == "x" || digits.first == "X"
                ? UInt32(digits.dropFirst(), radix: 16)
                : UInt32(digits, radix: 10)
            return value.flatMap(Unicode.Scalar.init).map { String(Character($0)) }
        }
        return namedEntities[String(name)]
    }
}
