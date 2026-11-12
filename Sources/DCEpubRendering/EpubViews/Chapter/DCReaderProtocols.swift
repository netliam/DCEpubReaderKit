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

    /// Where the reader is in the whole book, after each `handleCoords` for a page turn (not bookmarks).
    func handleProgress(book: DCEpubBook, progress: DCReaderProgress)

    func save(highlight: DCHighlight) async
    func deleteHighlight(uuid: String, book: DCEpubBook) async
    func highlights(for book: DCEpubBook) async -> [DCHighlight]?
    func highlights(for book: DCEpubBook, chapterId: String) async -> [DCHighlight]?
}

public extension DCReaderCoordsProtocol {
    func handleProgress(book: DCEpubBook, progress: DCReaderProgress) {}

    func save(highlight: DCHighlight) async {}

    func deleteHighlight(uuid: String, book: DCEpubBook) async {}

    func highlights(for book: DCEpubBook) async -> [DCHighlight]? {
        nil
    }

    func highlights(for book: DCEpubBook, chapterId: String) async -> [DCHighlight]? {
        nil
    }
}

/// The reader's place in the whole book, as the progress bar shows it ("11 of 39").
public struct DCReaderProgress: Equatable, Sendable {
    public let spineIndex: Int
    public let coords: String
    /// Fraction of the book read, 0...1: `page / totalPages` once counted, else estimated from
    /// chapters (the chapter index plus the fraction of the chapter read).
    public let fraction: Double
    /// Whole-book page and page count, once the book has been counted (`nil` until then). They
    /// depend on the text size, layout and window size.
    public let page: Int?
    public let totalPages: Int?

    public init(spineIndex: Int, coords: String, fraction: Double, page: Int?, totalPages: Int?) {
        self.spineIndex = spineIndex
        self.coords = coords
        self.fraction = fraction
        self.page = page
        self.totalPages = totalPages
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
    var configuration: DCReaderConfiguration { get }
}

extension DCChapterReaderContextProtocol {
    var configuration: DCReaderConfiguration { DCReaderConfiguration() }
}
