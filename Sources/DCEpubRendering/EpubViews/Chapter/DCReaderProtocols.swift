//
//  DCReaderProtocols.swift
//  DCEpubReaderKit
//
//  Created by Josep Cerdá Penadés on 6/2/26.
//

import Foundation
import DCEpubCore

@MainActor
public protocol DCReaderCoordsProtocol {
    func handleCoords(book: DCEpubBook,
                      spineIndex: Int,
                      coords: String,
                      chapterURL: URL?,
                      isBookMark: Bool)

    func save(highlight: DCHighlight) async
    func deleteHighlight(uuid: String, book: DCEpubBook) async
    func highlights(for book: DCEpubBook) async -> [DCHighlight]?
    func highlights(for book: DCEpubBook, chapterId: String) async -> [DCHighlight]?
}

public extension DCReaderCoordsProtocol {
    func save(highlight: DCHighlight) async {}

    func deleteHighlight(uuid: String, book: DCEpubBook) async {}

    func highlights(for book: DCEpubBook) async -> [DCHighlight]? {
        nil
    }

    func highlights(for book: DCEpubBook, chapterId: String) async -> [DCHighlight]? {
        nil
    }
}

/// Where to move inside a chapter once it has loaded.
enum DCChapterJump: Equatable {
    /// A saved location (position, highlight or bookmark).
    case coords(String)
    /// The n-th match of a search query, which is also highlighted.
    case search(query: String, occurrence: Int)
    /// The element with this id, from a table-of-contents link.
    case fragment(String)
    /// A page (0-based) of the chapter, from the progress scrubber.
    case page(Int)
}

@MainActor
protocol DCChapterReaderContextProtocol: AnyObject {
    var currentBook: DCEpubBook { get }
    var bookId: String { get }
    func consumeInitialJump(for spineIndex: Int, chapterURL: URL) -> DCChapterJump?
    func showNote(highlight: DCHighlight)
    func save(highlight: DCHighlight) async
    func deleteHighlight(uuid: String) async
    func highlights(for chapterId: String) async -> [DCHighlight]
}
