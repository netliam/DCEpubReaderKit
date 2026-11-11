//
//  DCJSONReaderStore.swift
//  DCEpubReaderKit
//
//  Created by Liam Smith-Gales on 11/11/26.
//

import Foundation

/// Ready-made persistence for highlights, notes, bookmarks and the reading position.
///
/// Each book is stored as one JSON file in `directory`. Records are loaded lazily the first time a
/// book is accessed and kept in memory afterwards; every change rewrites that book's file atomically.
/// Use it with `DCStoreReaderDelegate` (DCEpubRendering), or implement
/// `DCHighlightStoreProtocol` / `DCReaderCoordsProtocol` yourself for custom storage.
@MainActor
public final class DCJSONReaderStore: DCHighlightStoreProtocol, DCReadingPositionStoreProtocol {

    private struct BookRecord: Codable {
        var highlights: [DCHighlight] = []
        var position: DCReadingPosition?
    }

    public let directory: URL
    /// The most recent read or write failure, if any. The store protocols don't throw, so failures land here.
    public private(set) var lastError: Error?

    private var records: [String: BookRecord] = [:]
    private let fileManager = FileManager.default

    /// - Parameter directory: Folder for the JSON files. Created on first write if needed.
    public init(directory: URL) {
        self.directory = directory
    }

    /// Stores files in `Application Support/DCEpubReaderKit`.
    public convenience init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.init(directory: base.appendingPathComponent("DCEpubReaderKit", isDirectory: true))
    }

    // MARK: - DCHighlightStoreProtocol

    public func save(_ highlight: DCHighlight) async {
        var record = record(for: highlight.bookId)
        if let index = record.highlights.firstIndex(where: { $0.uuid == highlight.uuid }) {
            record.highlights[index] = highlight
        } else {
            record.highlights.append(highlight)
        }
        store(record, for: highlight.bookId)
    }

    public func highlights(bookId: String) async -> [DCHighlight] {
        record(for: bookId).highlights
    }

    public func highlights(bookId: String, chapterId: String) async -> [DCHighlight] {
        record(for: bookId).highlights.filter { $0.chapterId == chapterId }
    }

    public func delete(uuid: String) async {
        // The protocol doesn't pass the book, so look in loaded books first, then the rest on disk.
        for bookId in Array(records.keys) + unloadedBookIds() {
            var record = record(for: bookId)
            guard let index = record.highlights.firstIndex(where: { $0.uuid == uuid }) else { continue }
            record.highlights.remove(at: index)
            store(record, for: bookId)
            return
        }
    }

    // MARK: - DCReadingPositionStoreProtocol

    public func save(position: DCReadingPosition) async {
        var record = record(for: position.bookId)
        record.position = position
        store(record, for: position.bookId)
    }

    public func position(bookId: String) async -> DCReadingPosition? {
        record(for: bookId).position
    }

    // MARK: - Maintenance

    /// Deletes everything stored for a book, e.g. when it is removed from the library.
    public func removeAll(bookId: String) {
        records[bookId] = nil
        do {
            let url = fileURL(for: bookId)
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        } catch {
            lastError = error
        }
    }

    // MARK: - File handling

    private func record(for bookId: String) -> BookRecord {
        if let cached = records[bookId] {
            return cached
        }
        let url = fileURL(for: bookId)
        var record = BookRecord()
        if fileManager.fileExists(atPath: url.path) {
            do {
                record = try JSONDecoder().decode(BookRecord.self, from: Data(contentsOf: url))
            } catch {
                lastError = error
            }
        }
        records[bookId] = record
        return record
    }

    private func store(_ record: BookRecord, for bookId: String) {
        records[bookId] = record
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(record)
            try data.write(to: fileURL(for: bookId), options: .atomic)
        } catch {
            lastError = error
        }
    }

    private func fileURL(for bookId: String) -> URL {
        directory.appendingPathComponent(fileName(for: bookId)).appendingPathExtension("json")
    }

    /// Percent-encodes the id so any identifier (URNs, ISBNs, paths) maps to a unique, valid file name.
    private func fileName(for bookId: String) -> String {
        bookId.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? bookId
    }

    private func unloadedBookIds() -> [String] {
        let files = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { $0.deletingPathExtension().lastPathComponent.removingPercentEncoding }
            .filter { records[$0] == nil }
    }
}
