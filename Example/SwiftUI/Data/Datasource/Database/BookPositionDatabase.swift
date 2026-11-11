//
//  BookPositionDatabase.swift
//  DCEpubReaderKit
//
//  Created by Josep Cerdá Penadés on 22/12/25.
//

import DCEpubReaderKit
import Foundation
internal import Realm
import RealmSwift

protocol BookPositionDatabaseProtocol {
    func saveBookPosition(book: DCEpubBook,
                          spineIndex: Int,
                          coords: String,
                          chapterURL: URL,
                          markType: RBookMark.MarkType) throws
    func getBookPosition(book: DCEpubBook) throws -> EBookPositionEntity?
}

final class BookPositionDatabase: BookPositionDatabaseProtocol {
    func saveBookPosition(book: DCEpubBook,
                          spineIndex: Int,
                          coords: String,
                          chapterURL: URL,
                          markType: RBookMark.MarkType) throws {
        let realm = try Realm()
        let nowMillis = Date().timeMillis
        switch markType {
        case .lastPosition:
            if let mark = realm.objects(RBookMark.self).filter(
                """
                uuid = '\(book.uniqueIdentifier)' AND
                type = '\(markType.rawValue)'
                """).first {
                try realm.write {
                    mark.type = markType.rawValue
                    mark.bookTitle = book.bookTitle
                    mark.lastcoords = coords
                    mark.lastchapterid = chapterURL.lastPathComponent
                    mark.spineIndex = spineIndex
                    mark.dateUpdated = nowMillis
                }
            } else {
                let mark = RBookMark()
                mark.type = markType.rawValue
                mark.uuid = book.uniqueIdentifier
                mark.bookTitle = book.bookTitle
                mark.lastcoords = coords
                mark.lastchapterid = chapterURL.lastPathComponent
                mark.spineIndex = spineIndex
                mark.dateCreated = nowMillis
                mark.dateUpdated = nowMillis
                mark.compoundKey = mark.compoundLastPosition
                try realm.write {
                    realm.add(mark, update: .modified)
                }
            }
        case .bookMark:
            let mark = RBookMark()
            mark.type = markType.rawValue
            mark.uuid = book.uniqueIdentifier
            mark.coords = coords
            mark.bookTitle = book.bookTitle
            mark.chapterId = chapterURL.lastPathComponent
            mark.spineIndex = spineIndex
            mark.dateCreated = nowMillis
            mark.compoundKey = mark.compoundBookmark
            try realm.write {
                realm.add(mark, update: .modified)
            }
        default:
            break
        }
    }

    func getBookPosition(book: DCEpubBook) throws -> EBookPositionEntity? {
        let realm = try Realm()
        guard let mark = realm.objects(RBookMark.self).filter(
            """
            uuid = '\(book.uniqueIdentifier)' AND
            type = '\(RBookMark.MarkType.lastPosition.rawValue)'
            """
        ).first else {
            return nil
        }

        let storedSpineIndex = mark.spineIndex
        let resolvedSpineIndex = resolveSpineIndex(
            storedSpineIndex,
            chapterId: mark.lastchapterid,
            book: book
        )

        return EBookPositionEntity(
            spineIndex: resolvedSpineIndex,
            coords: mark.lastcoords,
            chapterId: mark.lastchapterid,
            dateUpdated: mark.dateUpdated
        )
    }

    private func resolveSpineIndex(_ storedSpineIndex: Int,
                                   chapterId: String,
                                   book: DCEpubBook) -> Int {
        if !chapterId.isEmpty, let index = book.spine.firstIndex(where: { spineItem in
            guard let manifestItem = book.manifest.first(where: { $0.id == spineItem.idref }) else {
                return false
            }
            return URL(fileURLWithPath: manifestItem.href).lastPathComponent == chapterId
        }) {
            return index
        }

        if storedSpineIndex >= 0 && storedSpineIndex < book.spine.count {
            return storedSpineIndex
        }
        return 0
    }
}

final class BookPositionDatabaseMock: BookPositionDatabaseProtocol {
    func saveBookPosition(book: DCEpubBook,
                          spineIndex: Int,
                          coords: String,
                          chapterURL: URL,
                          markType: RBookMark.MarkType) throws {}

    func getBookPosition(book: DCEpubBook) throws -> EBookPositionEntity? {
        nil
    }
}
