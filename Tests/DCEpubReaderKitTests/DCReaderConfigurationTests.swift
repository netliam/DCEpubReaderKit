//
//  DCReaderConfigurationTests.swift
//  DCEpubReaderKit
//
//  Created by Liam Smith-Gales on 11/11/26.
//

import Foundation
import Testing
import UIKit
import DCEpubCore
import DCEpubParser
@testable import DCEpubRendering

/// What a host app sets through `DCReaderConfiguration`.
@MainActor
@Suite("Reader configuration")
struct DCReaderConfigurationTests {

    private func book() throws -> DCEpubBook {
        let url = try #require(Bundle.module.url(forResource: "MinimalEPUB", withExtension: nil, subdirectory: "Fixtures"))
        return try DCEpubParser.parse(from: url)
    }

    @Test func hostBookIdReplacesTheOPFIdentifier() throws {
        let book = try book()
        var configuration = DCReaderConfiguration()
        #expect(DCReaderViewModel(book: book, spineIndex: 0, userPreferencesProtocol: DCUserPreferencesMock(),
                                  delegate: nil).bookId == book.uniqueIdentifier)
        configuration.bookId = "bow-42"
        let reader = DCReaderViewModel(book: book, spineIndex: 0, userPreferencesProtocol: DCUserPreferencesMock(),
                                       delegate: nil, configuration: configuration)
        #expect(reader.bookId == "bow-42")
    }

    @Test func storeDelegateUsesTheHostBookId() async throws {
        let book = try book()
        let store = DCJSONReaderStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let delegate = DCStoreReaderDelegate(store: store, bookId: "bow-42")
        let chapter = try #require(book.chapterURL(forSpineIndex: 0))
        delegate.handleCoords(book: book, spineIndex: 0, coords: "0000001>0000000", chapterURL: chapter, isBookMark: false)
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(await store.position(bookId: "bow-42")?.coords == "0000001>0000000")
        #expect(await store.position(bookId: book.uniqueIdentifier) == nil)
    }

    @Test func externalLinksGoToTheHost() throws {
        var opened: URL?
        var configuration = DCReaderConfiguration()
        configuration.onOpenExternalURL = { opened = $0 }
        let reader = DCReaderViewModel(book: try book(), spineIndex: 0, userPreferencesProtocol: DCUserPreferencesMock(),
                                       delegate: nil, configuration: configuration)
        reader.openLink(URL(string: "https://example.com/a")!)
        #expect(opened?.absoluteString == "https://example.com/a")
    }

    @Test func hostFontIsLoadedAndApplied() throws {
        let file = URL(fileURLWithPath: "/fonts/Bow Serif.ttf")
        let font = DCReaderFont(name: "Bow Serif", cssFamily: "BowSerif", files: [file])
        #expect(font.css.contains(#"@font-face { font-family: "BowSerif"; src: url("file:///fonts/Bow%20Serif.ttf"); }"#))
        #expect(font.css.contains(#"font-family: "BowSerif" !important"#))

        let chapter = FileManager.default.temporaryDirectory.appendingPathComponent("c-\(UUID().uuidString).xhtml")
        try "<html><head></head><body><p>x</p></body></html>".write(to: chapter, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: chapter) }
        let preferences = DCUserPreferencesMock()
        preferences.fontChoice = font.storageKey
        let html = DCChapterHTMLBuilder.html(pathtofile: chapter.path, userPreferences: preferences,
                                             appearance: DCReaderAppearance(theme: .original, isDark: false), fonts: [font])
        #expect(html.contains("@font-face"))
        // Unknown host fonts (no longer offered) fall back to the book's own.
        let fallback = DCChapterHTMLBuilder.html(pathtofile: chapter.path, userPreferences: preferences,
                                                 appearance: DCReaderAppearance(theme: .original, isDark: false))
        #expect(!fallback.contains("@font-face"))
    }

    @Test func pageCurlCanBeTurnedOff() {
        var configuration = DCReaderConfiguration()
        #expect(configuration.allowsPageCurl)
        configuration.allowsPageCurl = false
        let settings = DCReaderSettingsViewModel(
            fontSize: .constant(3), textFont: .constant("original"), theme: .constant("original"),
            followsSystemAppearance: .constant(true), orientation: .constant("horizontal"),
            pageTransition: .constant("curl"), lineFocus: .constant(false), lineFocusStyle: .constant("guide"),
            textLayout: .constant(DCTextLayout()), rotationLock: .constant(false), themeColors: .constant([:]),
            systemIsDark: false, userPreferences: DCUserPreferencesMock(), configuration: configuration)
        #expect(!settings.configuration.allowsPageCurl)
    }
}
