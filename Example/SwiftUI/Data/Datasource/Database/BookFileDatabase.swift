//
//  BookFileDatabase.swift
//  DCEpubReaderKit
//
//  Created by Josep Cerdá Penadés on 19/1/26.
//

import DCEpubReaderKit
import Foundation
internal import Realm
import RealmSwift

protocol BookFileDatabaseProtocol {
    func saveBook(book: DCEpubBook) throws
    func getBookList() throws -> [RBook]
    func getBook(uuid: String) throws -> RBook
    func deleteBook(uuid: String) throws
}

final class BookFileDatabase: BookFileDatabaseProtocol {
    func saveBook(book: DCEpubBook) throws {
        let realm = try Realm()
        let nowMillis = Date().timeMillis
        let bookId = book.uniqueIdentifier

        let record = RBook()
        record.uuid = bookId
        record.title = book.metadata.title ?? ""
        record.author = book.metadata.creators.first ?? ""
        record.coverPath = normalizeCoverPath(book.metadata.coverHint ?? "")
        record.language = book.metadata.language ?? ""
        record.publisher = book.metadata.publisher ?? ""
        record.bookVersion = book.metadata.version ?? ""
        record.bookDate = book.metadata.date ?? ""
        record.descriptionHTML = book.metadata.descriptionHTML ?? ""
        record.updatedAt = nowMillis

        if let existing = realm.object(ofType: RBook.self, forPrimaryKey: bookId) {
            record.createdAt = existing.createdAt == 0 ? nowMillis : existing.createdAt
        } else {
            record.createdAt = nowMillis
        }

        try realm.write {
            realm.add(record, update: .modified)
        }
    }

    func getBookList() throws -> [RBook] {
        let realm = try Realm()
        let results = realm.objects(RBook.self).sorted(byKeyPath: "createdAt", ascending: false)
        return results.toArray
    }

    func getBook(uuid: String) throws -> RBook {
        let realm = try Realm()
        guard let book = realm.object(ofType: RBook.self, forPrimaryKey: uuid) else {
            throw RealmError.canNotLoadData(error: "Book not found for uuid: \(uuid)")
        }
        return book.detached()
    }

    func deleteBook(uuid: String) throws {
        let realm = try Realm()
        guard let book = realm.object(ofType: RBook.self, forPrimaryKey: uuid) else {
            return
        }
        let bookFolder = FileHelper.shared.bookDirectory(for: uuid)
        if FileManager.default.fileExists(atPath: bookFolder.path) {
            try FileManager.default.removeItem(at: bookFolder)
        }
        try realm.write {
            realm.delete(book)
        }
    }
}

private extension BookFileDatabase {
    func normalizeCoverPath(_ coverPath: String) -> String {
        guard !coverPath.isEmpty else { return "" }

        let knownRoots = ["OEBPS", "OPS", "EPUB"]
        let components = URL(fileURLWithPath: coverPath).pathComponents
        if let idx = components.lastIndex(where: { knownRoots.contains($0) }) {
            let rel = components[idx...].joined(separator: "/")
            if !rel.isEmpty { return rel }
        }

        if components.count >= 3 {
            return components.suffix(3).joined(separator: "/")
        }

        return coverPath
    }
}
