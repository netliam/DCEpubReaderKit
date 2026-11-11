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
/// Reading positions go to `save(position:)`. Bookmarks, highlights and notes are `DCHighlight`s the
/// reader saves and deletes through `save(highlight:)` / `deleteHighlight(uuid:book:)`.
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
        // The reader saves bookmarks itself (as `.bookMark` highlights); only positions are stored here.
        guard !isBookMark else { return }
        let chapterId = (chapterURL ?? book.chapterURL(forSpineIndex: spineIndex))?.lastPathComponent ?? ""
        let position = DCReadingPosition(bookId: book.uniqueIdentifier,
                                         spineIndex: spineIndex,
                                         coords: coords,
                                         chapterId: chapterId)
        Task {
            await store.save(position: position)
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
}
