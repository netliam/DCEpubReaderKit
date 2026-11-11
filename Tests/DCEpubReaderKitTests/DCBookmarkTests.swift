//
//  DCBookmarkTests.swift
//  DCEpubReaderKit
//
//  Created by Liam Smith-Gales on 11/11/26.
//

import Foundation
import Testing
import DCEpubCore
import DCEpubParser
@testable import DCEpubRendering

/// Bookmark button behaviour, with the built-in JSON store behind the reader.
@MainActor
@Suite("Bookmarks")
struct DCBookmarkTests {

    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)

    private func makeBook() throws -> DCEpubBook {
        let url = try #require(Bundle.module.url(forResource: "MinimalEPUB", withExtension: nil, subdirectory: "Fixtures"))
        return try DCEpubParser.parse(from: url)
    }

    private func makeReader(book: DCEpubBook, store: DCJSONReaderStore) -> DCReaderViewModel {
        DCReaderViewModel(book: book,
                          spineIndex: 0,
                          userPreferencesProtocol: DCUserPreferencesMock(),
                          delegate: DCStoreReaderDelegate(store: store))
    }

    private func waitUntil(_ condition: () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !(await condition()) {
            guard Date() < deadline else { throw CancellationError() }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    @Test func bookmarkingThenTappingAgainRemovesIt() async throws {
        let book = try makeBook()
        let store = DCJSONReaderStore(directory: directory)
        let reader = makeReader(book: book, store: store)
        reader.handle(.currentPage(index: 2, totalPages: 3, spineIndex: 0), chapterURL: nil)

        // The page reports its first text when bookmarking.
        reader.handle(.coordsFirstNodeOfPage(orientation: .horizontal, spineIndex: 0, coords: "0001|0000", isBookMark: true),
                      chapterURL: book.chapterURL(forSpineIndex: 0))
        #expect(reader.isCurrentPageBookmarked)
        try await waitUntil { await store.highlights(bookId: book.uniqueIdentifier).count == 1 }
        let saved = try #require(await store.highlights(bookId: book.uniqueIdentifier).first)
        #expect(saved.type == .bookMark)
        #expect(saved.coords == "0001|0000")

        // Bookmarking the same spot again doesn't duplicate it.
        reader.handle(.coordsFirstNodeOfPage(orientation: .horizontal, spineIndex: 0, coords: "0001|0000", isBookMark: true),
                      chapterURL: book.chapterURL(forSpineIndex: 0))
        #expect(reader.bookmarks.count == 1)

        reader.toggleBookmark()
        #expect(!reader.isCurrentPageBookmarked)
        #expect(reader.bookmarks.isEmpty)
        try await waitUntil { await store.highlights(bookId: book.uniqueIdentifier).isEmpty }
    }

    @Test func reopeningTheBookLoadsItsBookmarks() async throws {
        let book = try makeBook()
        let store = DCJSONReaderStore(directory: directory)
        await store.save(DCHighlight(uuid: "b1", bookId: book.uniqueIdentifier, chapterId: "chapter1.xhtml",
                                     spineIndex: 0, type: .bookMark, text: "", coords: "0001|0000"))
        await store.save(DCHighlight(uuid: "h1", bookId: book.uniqueIdentifier, chapterId: "chapter1.xhtml",
                                     spineIndex: 0, type: .highlight, text: "Fixture", coords: "0001|0000,0001|0007"))

        let reader = makeReader(book: book, store: store)
        await reader.loadBookmarks()
        #expect(reader.bookmarks.map(\.uuid) == ["b1"], "only bookmarks, not highlights")
    }
}
