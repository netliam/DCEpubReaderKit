//
//  DCStoreReaderDelegate.swift
//  DCEpubReaderKit
//
//  Created by Liam Smith-Gales on 11/11/26.
//

import Foundation
import DCEpubCore

/// A `DCReaderCoordsProtocol` that persists everything into a store, so integrators don't need
/// their own delegate:
///
/// ```swift
/// let store = DCJSONReaderStore()
/// let position = await store.position(bookId: book.uniqueIdentifier)
/// DCReaderViewBuilder.build(book,
///                           spineIndex: position?.spineIndex ?? 0,
///                           initialCoords: position?.coords,
///                           delegate: DCStoreReaderDelegate(store: store))
/// ```
///
/// Reading positions go to `save(position:)`; bookmarks are saved as `DCHighlight`s of type `.bookMark`
/// so they show up in the marks list.
@MainActor
public final class DCStoreReaderDelegate: DCReaderCoordsProtocol {

    public typealias Store = DCHighlightStoreProtocol & DCReadingPositionStoreProtocol

    public let store: any Store

    public init(store: any Store) {
        self.store = store
    }

    public func handleCoords(book: DCEpubBook,
                             spineIndex: Int,
                             coords: String,
                             chapterURL: URL?,
                             isBookMark: Bool) {
        let chapterId = (chapterURL ?? book.chapterURL(forSpineIndex: spineIndex))?.lastPathComponent ?? ""
        let bookId = book.uniqueIdentifier
        let chapterTitle = book.chapterTitle(forSpineIndex: spineIndex) ?? ""
        Task {
            if isBookMark {
                await saveBookmark(bookId: bookId,
                                   spineIndex: spineIndex,
                                   coords: coords,
                                   chapterId: chapterId,
                                   chapterTitle: chapterTitle)
            } else {
                await store.save(position: DCReadingPosition(bookId: bookId,
                                                             spineIndex: spineIndex,
                                                             coords: coords,
                                                             chapterId: chapterId))
            }
        }
    }

    public func save(highlight: DCHighlight) async {
        await store.save(highlight)
    }

    public func deleteHighlight(uuid: String, book: DCEpubBook) async {
        await store.delete(uuid: uuid)
    }

    public func highlights(for book: DCEpubBook) async -> [DCHighlight]? {
        await store.highlights(bookId: book.uniqueIdentifier)
    }

    public func highlights(for book: DCEpubBook, chapterId: String) async -> [DCHighlight]? {
        await store.highlights(bookId: book.uniqueIdentifier, chapterId: chapterId)
    }

    private func saveBookmark(bookId: String,
                              spineIndex: Int,
                              coords: String,
                              chapterId: String,
                              chapterTitle: String) async {
        let existing = await store.highlights(bookId: bookId)
        // Tapping bookmark twice on the same page refreshes the existing bookmark instead of duplicating it.
        if var bookmark = existing.first(where: {
            $0.type == .bookMark && $0.spineIndex == spineIndex && $0.coords == coords
        }) {
            bookmark.dateUpdated = Date().timeIntervalSince1970
            await store.save(bookmark)
            return
        }
        await store.save(DCHighlight(uuid: UUID().uuidString,
                                     bookId: bookId,
                                     chapterId: chapterId,
                                     spineIndex: spineIndex,
                                     type: .bookMark,
                                     text: "",
                                     coords: coords,
                                     chapterTitle: chapterTitle))
    }
}
