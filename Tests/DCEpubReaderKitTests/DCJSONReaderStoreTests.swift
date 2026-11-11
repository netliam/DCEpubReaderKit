//
//  DCJSONReaderStoreTests.swift
//  DCEpubReaderKit
//
//  Created by Liam Smith-Gales on 11/11/26.
//

import Foundation
import Testing
import DCEpubCore

@MainActor
@Suite("DCJSONReaderStore")
struct DCJSONReaderStoreTests {

    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)

    private func highlight(_ uuid: String,
                           bookId: String = "urn:isbn:978-0",
                           chapterId: String = "chapter1.xhtml",
                           note: String = "") -> DCHighlight {
        DCHighlight(uuid: uuid,
                    bookId: bookId,
                    chapterId: chapterId,
                    spineIndex: 0,
                    type: .highlight,
                    text: "Some text",
                    coords: "0001|0002",
                    note: note)
    }

    @Test func savesAndReloadsHighlightsFromDisk() async {
        let store = DCJSONReaderStore(directory: directory)
        await store.save(highlight("a"))
        await store.save(highlight("b", chapterId: "chapter2.xhtml"))

        // A fresh store only sees what was written to disk.
        let reloaded = DCJSONReaderStore(directory: directory)
        #expect(await reloaded.highlights(bookId: "urn:isbn:978-0").map(\.uuid) == ["a", "b"])
        #expect(await reloaded.highlights(bookId: "urn:isbn:978-0", chapterId: "chapter2.xhtml").map(\.uuid) == ["b"])
        #expect(reloaded.lastError == nil)
    }

    @Test func savingTheSameUUIDUpdatesInPlace() async {
        let store = DCJSONReaderStore(directory: directory)
        await store.save(highlight("a"))
        await store.save(highlight("a", note: "Edited"))

        let highlights = await store.highlights(bookId: "urn:isbn:978-0")
        #expect(highlights.count == 1)
        #expect(highlights.first?.note == "Edited")
    }

    @Test func deleteFindsHighlightsInBooksNotLoadedYet() async {
        let writer = DCJSONReaderStore(directory: directory)
        await writer.save(highlight("a", bookId: "book-1"))
        await writer.save(highlight("b", bookId: "book-2"))

        let store = DCJSONReaderStore(directory: directory)
        await store.delete(uuid: "b")

        let reloaded = DCJSONReaderStore(directory: directory)
        #expect(await reloaded.highlights(bookId: "book-1").map(\.uuid) == ["a"])
        #expect(await reloaded.highlights(bookId: "book-2").isEmpty)
    }

    @Test func storesThePositionAlongsideHighlights() async {
        let store = DCJSONReaderStore(directory: directory)
        await store.save(highlight("a"))
        await store.save(position: DCReadingPosition(bookId: "urn:isbn:978-0",
                                                     spineIndex: 3,
                                                     coords: "0004|0001",
                                                     chapterId: "chapter4.xhtml"))

        let reloaded = DCJSONReaderStore(directory: directory)
        let position = await reloaded.position(bookId: "urn:isbn:978-0")
        #expect(position?.spineIndex == 3)
        #expect(position?.coords == "0004|0001")
        #expect(await reloaded.highlights(bookId: "urn:isbn:978-0").count == 1)
    }

    @Test func bookIdsThatAreNotValidFileNamesDoNotCollide() async {
        let store = DCJSONReaderStore(directory: directory)
        await store.save(highlight("a", bookId: "a/b"))
        await store.save(highlight("b", bookId: "a:b"))

        let reloaded = DCJSONReaderStore(directory: directory)
        #expect(await reloaded.highlights(bookId: "a/b").map(\.uuid) == ["a"])
        #expect(await reloaded.highlights(bookId: "a:b").map(\.uuid) == ["b"])
    }

    @Test func removeAllDeletesTheBookFile() async {
        let store = DCJSONReaderStore(directory: directory)
        await store.save(highlight("a"))
        store.removeAll(bookId: "urn:isbn:978-0")

        let reloaded = DCJSONReaderStore(directory: directory)
        #expect(await reloaded.highlights(bookId: "urn:isbn:978-0").isEmpty)
    }
}
