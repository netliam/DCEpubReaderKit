//
//  BookHighlightDatabase.swift
//  DCEpubReaderKit
//
//  Created by Josep Cerdá Penadés on 04/05/26.
//

import DCEpubReaderKit
import Foundation
internal import Realm
import RealmSwift

protocol BookHighlightDatabaseProtocol {
    func saveHighlight(_ highlight: DCHighlight) throws
    func highlights(bookId: String) throws -> [DCHighlight]
    func highlights(bookId: String, chapterId: String) throws -> [DCHighlight]
    func deleteHighlight(uuid: String) throws
}

final class BookHighlightDatabase: BookHighlightDatabaseProtocol {

    func saveHighlight(_ highlight: DCHighlight) throws {
        let realm = try Realm()
        let mark = RBookMark()
        mark.bookId = highlight.bookId
        mark.uuid = highlight.uuid
        mark.compoundKey = mark.compoundHighlight
        mark.text = highlight.text
        mark.coords = highlight.coords
        mark.chapterId = highlight.chapterId
        mark.chapterTitle = highlight.chapterTitle
        mark.spineIndex = highlight.spineIndex
        mark.textNote = highlight.note
        mark.type = highlight.type == .highlight
            ? RBookMark.MarkType.hightLihgt.rawValue
            : RBookMark.MarkType.note.rawValue
        mark.dateCreated = Int64(highlight.dateCreated * 1000)
        mark.dateUpdated = Int64(highlight.dateUpdated * 1000)
        try realm.write {
            realm.add(mark, update: .modified)
        }
    }

    func highlights(bookId: String) throws -> [DCHighlight] {
        let realm = try Realm()
        let types = [RBookMark.MarkType.hightLihgt.rawValue,
                     RBookMark.MarkType.note.rawValue]
        return realm.objects(RBookMark.self)
            .filter("bookId == %@ AND type IN %@", bookId, types)
            .sorted(by: [
                SortDescriptor(keyPath: "spineIndex", ascending: true),
                SortDescriptor(keyPath: "dateCreated", ascending: true)
            ])
            .map { $0.toHighlight() }
    }

    func highlights(bookId: String, chapterId: String) throws -> [DCHighlight] {
        let realm = try Realm()
        let types = [RBookMark.MarkType.hightLihgt.rawValue,
                     RBookMark.MarkType.note.rawValue]
        return realm.objects(RBookMark.self)
            .filter("bookId == %@ AND chapterId == %@ AND type IN %@",
                    bookId, chapterId, types)
            .sorted(by: [
                SortDescriptor(keyPath: "dateCreated", ascending: true)
            ])
            .map { $0.toHighlight() }
    }

    func deleteHighlight(uuid: String) throws {
        let realm = try Realm()
        guard let mark = realm.object(ofType: RBookMark.self, forPrimaryKey: uuid) else { return }
        try realm.write { realm.delete(mark) }
    }
}

private extension RBookMark {
    func toHighlight() -> DCHighlight {
        DCHighlight(
            uuid: uuid,
            bookId: bookId,
            chapterId: chapterId,
            spineIndex: spineIndex,
            type: type == RBookMark.MarkType.hightLihgt.rawValue ? .highlight : .note,
            text: text,
            coords: coords,
            note: textNote,
            chapterTitle: chapterTitle,
            dateCreated: Double(dateCreated) / 1000,
            dateUpdated: Double(dateUpdated) / 1000
        )
    }
}
