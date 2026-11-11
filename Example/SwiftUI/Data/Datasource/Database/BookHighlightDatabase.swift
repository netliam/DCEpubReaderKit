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
        mark.type = RBookMark.MarkType(highlight.type).rawValue
        mark.style = highlight.style?.rawValue ?? ""
        mark.dateCreated = Int64(highlight.dateCreated * 1000)
        mark.dateUpdated = Int64(highlight.dateUpdated * 1000)
        try realm.write {
            realm.add(mark, update: .modified)
        }
    }

    func highlights(bookId: String) throws -> [DCHighlight] {
        let realm = try Realm()
        let types = RBookMark.MarkType.highlightTypes
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
        let types = RBookMark.MarkType.highlightTypes
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
            type: RBookMark.MarkType(rawValue: type)?.highlightType ?? .highlight,
            text: text,
            coords: coords,
            note: textNote,
            chapterTitle: chapterTitle,
            style: DCHighlightStyle(rawValue: style),
            dateCreated: Double(dateCreated) / 1000,
            dateUpdated: Double(dateUpdated) / 1000
        )
    }
}

private extension RBookMark.MarkType {
    /// Types stored for `DCHighlight`s (highlights, notes and bookmarks), as opposed to the last position.
    static let highlightTypes = [RBookMark.MarkType.hightLihgt, .note, .bookMark].map(\.rawValue)

    init(_ type: DCHighlight.MarkType) {
        switch type {
        case .highlight: self = .hightLihgt
        case .note: self = .note
        case .bookMark: self = .bookMark
        }
    }

    var highlightType: DCHighlight.MarkType {
        switch self {
        case .note: .note
        case .bookMark: .bookMark
        case .hightLihgt, .lastPosition: .highlight
        }
    }
}
