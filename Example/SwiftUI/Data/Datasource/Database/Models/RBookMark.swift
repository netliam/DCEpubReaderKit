//
//  RBookMark.swift
//  DCEpubReaderKit
//
//  Created by Josep Cerdá Penadés on 21/12/25.
//

import Foundation
internal import Realm
import RealmSwift

final class RBookMark: Object {

    enum MarkType: String {
        case hightLihgt
        case note
        case bookMark
        case lastPosition
    }

    private enum Constants {
        static let primaryKey = "compoundKey"
    }

    @Persisted var compoundKey: String = ""
    @Persisted var uuid: String = ""
    @Persisted var bookId: String = ""
    @Persisted var bookTitle: String = ""
    @Persisted var text: String = ""
    @Persisted var coords: String = ""
    @Persisted var chapterId: String = ""
    @Persisted var chapterTitle: String = ""
    @Persisted var pageNumber: Int = 0
    @Persisted var spineIndex: Int = 0
    @Persisted var textNote: String = ""
    @Persisted var type: String = ""
    /// Highlight color or underline (`DCHighlightStyle` raw value); empty for older marks.
    @Persisted var style: String = ""
    @Persisted var lastcoords: String = ""
    @Persisted var lastchapterid: String = ""
    @Persisted var dateCreated: Int64 = 0
    @Persisted var dateUpdated: Int64 = 0
    @Persisted var state: Bool = true

    var compoundLastPosition: String {
        "\(uuid)-\(type)"
    }

    var compoundBookmark: String {
        "\(uuid)-\(coords)-\(chapterId)"
    }

    // For highlights/notes: primary key is the JS-generated uuid (unique per highlight)
    var compoundHighlight: String { uuid }

    public override static func primaryKey() -> String {
        return Constants.primaryKey
    }
}
