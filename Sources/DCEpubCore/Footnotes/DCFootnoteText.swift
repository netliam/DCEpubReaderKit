//
//  DCFootnoteText.swift
//  DCEpubReaderKit
//
//  Created by Liam Smith-Gales on 11/11/26.
//

import Foundation

/// Reads the text of a note from an XHTML chapter, for notes linked from another chapter (endnotes
/// files). Notes in the same chapter are read in the page (see `noteText` in EpubUtil.js); this
/// matches it: back links are left out and paragraphs are separated by a blank line.
public enum DCFootnoteText {

    /// The text of the element with `id` in the XHTML `data`, or `nil` if there's none (or the
    /// file isn't well-formed XML).
    public static func text(ofElementWithId id: String, inXHTML data: Data) -> String? {
        let collector = Collector(targetId: id)
        let parser = XMLParser(data: data)
        parser.delegate = collector
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        _ = parser.parse()
        guard collector.found else { return nil }
        let text = collector.paragraphs
            .map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        return text.isEmpty ? nil : text
    }

    /// The text of the note a link points at, reading the chapter file at `url`'s path.
    public static func text(forLinkTo url: URL) -> String? {
        guard let id = url.fragment?.removingPercentEncoding, !id.isEmpty else { return nil }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        guard let fileURL = components?.url, fileURL.isFileURL,
              let data = try? Data(contentsOf: fileURL) else { return nil }
        return text(ofElementWithId: id, inXHTML: data)
    }

    private final class Collector: NSObject, XMLParserDelegate {
        let targetId: String
        private(set) var found = false
        private(set) var paragraphs: [String] = [""]
        /// Element depth inside the note; 0 outside it.
        private var depth = 0
        /// Depth of a back link being skipped, if any.
        private var skippingFrom: Int?
        private static let blocks: Set<String> = ["p", "li", "div", "blockquote", "br"]

        init(targetId: String) {
            self.targetId = targetId
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes: [String: String] = [:]) {
            let name = Self.localName(elementName)
            if depth == 0 {
                guard !found, attributes["id"] == targetId else { return }
                found = true
                depth = 1
                return
            }
            depth += 1
            if skippingFrom == nil, name == "a", Self.isBackLink(attributes) {
                skippingFrom = depth
            }
            if Self.blocks.contains(name) {
                paragraphs.append("")
            }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?) {
            guard depth > 0 else { return }
            if skippingFrom == depth { skippingFrom = nil }
            depth -= 1
            if depth == 0 { parser.abortParsing() }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard depth > 0, skippingFrom == nil else { return }
            paragraphs[paragraphs.count - 1] += string
        }

        private static func localName(_ name: String) -> String {
            String(name.split(separator: ":").last ?? Substring(name)).lowercased()
        }

        private static func isBackLink(_ attributes: [String: String]) -> Bool {
            let type = attributes["epub:type"] ?? ""
            let role = attributes["role"] ?? ""
            return type.split(separator: " ").contains("backlink") || role.contains("doc-backlink")
        }
    }
}
