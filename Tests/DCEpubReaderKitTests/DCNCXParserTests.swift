//
//  DCNCXParserTests.swift
//  DCEpubReaderKit
//
//  Created by Liam Smith-Gales on 11/11/26.
//

import Foundation
import Testing
import DCEpubCore
@testable import DCEpubParser

/// EPUB 2 tables of contents (toc.ncx).
@Suite("NCX table of contents")
struct DCNCXParserTests {
    @Test func readsTitlesLinksAndNesting() throws {
        let ncx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
          <navMap>
            <navPoint id="p1" playOrder="1">
              <navLabel><text>Chapter One</text></navLabel>
              <content src="Text/ch1.xhtml"/>
              <navPoint id="p1a" playOrder="2">
                <navLabel><text> Part &amp; Parcel </text></navLabel>
                <content src="Text/ch1.xhtml#part"/>
              </navPoint>
            </navPoint>
            <navPoint id="p2" playOrder="3">
              <navLabel><text>Chapter Two</text></navLabel>
              <content src="Text/ch2.xhtml"/>
            </navPoint>
          </navMap>
        </ncx>
        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("toc-\(UUID().uuidString).ncx")
        try Data(ncx.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let toc = try DCNCXParser().parse(ncxURL: url)
        #expect(toc.map(\.label) == ["Chapter One", "Chapter Two"])
        #expect(toc.map(\.href) == ["Text/ch1.xhtml", "Text/ch2.xhtml"])
        #expect(toc.first?.children.map(\.label) == ["Part & Parcel"])
        #expect(toc.first?.children.first?.href == "Text/ch1.xhtml#part")
        #expect(toc.last?.children.isEmpty == true)
    }
}
