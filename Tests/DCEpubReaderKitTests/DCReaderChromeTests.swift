//
//  DCReaderChromeTests.swift
//  DCEpubReaderKit
//
//  Created by Liam Smith-Gales on 11/11/26.
//

import Foundation
import Testing
import DCEpubCore
import DCEpubParser
@testable import DCEpubRendering

/// The reader controls are hidden while reading, toggled by a tap, and hidden again on a page turn.
@MainActor
@Suite("Reader controls")
struct DCReaderChromeTests {

    private func makeReader() throws -> DCReaderViewModel {
        let url = try #require(Bundle.module.url(forResource: "MinimalEPUB", withExtension: nil, subdirectory: "Fixtures"))
        return DCReaderViewModel(book: try DCEpubParser.parse(from: url),
                                 spineIndex: 0,
                                 userPreferencesProtocol: DCUserPreferencesMock(),
                                 delegate: nil)
    }

    @Test func hiddenWhileReadingAndToggledByATap() throws {
        let reader = try makeReader()
        reader.handle(.currentPage(index: 1, totalPages: 3, spineIndex: 0), chapterURL: nil)
        #expect(!reader.isChromeVisible)

        reader.handle(.toggleChrome, chapterURL: nil)
        #expect(reader.isChromeVisible)
        reader.handle(.toggleChrome, chapterURL: nil)
        #expect(!reader.isChromeVisible)
    }

    @Test func turningThePageHidesTheControls() throws {
        let reader = try makeReader()
        reader.handle(.currentPage(index: 1, totalPages: 3, spineIndex: 0), chapterURL: nil)
        reader.handle(.toggleChrome, chapterURL: nil)

        // Re-reporting the same page (e.g. after a theme change) keeps them.
        reader.handle(.currentPage(index: 1, totalPages: 3, spineIndex: 0), chapterURL: nil)
        #expect(reader.isChromeVisible)

        reader.handle(.currentPage(index: 2, totalPages: 3, spineIndex: 0), chapterURL: nil)
        #expect(!reader.isChromeVisible)
    }

    @Test func readingLabelsShowTheChapterTitle() throws {
        let reader = try makeReader()
        #expect(reader.readingTitle == "Chapter One")
        // No whole-book page until the book has been counted.
        #expect(reader.readingPageText.isEmpty)
    }
}
