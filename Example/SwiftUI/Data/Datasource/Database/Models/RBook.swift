//
//  RBook.swift
//  DCEpubReaderKit
//
//  Created by Josep Cerdá Penadés on 17/1/26.
//

import Foundation
internal import Realm
import RealmSwift

final class RBook: Object {

    private enum Constants {
        static let primaryKey = "uuid"
    }

    @Persisted var uuid: String = ""
    @Persisted var title: String = ""
    @Persisted var author: String = ""
    @Persisted var coverPath: String = ""
    @Persisted var language: String = ""
    @Persisted var publisher: String = ""
    @Persisted var bookVersion: String = ""
    @Persisted var bookDate: String = ""
    @Persisted var descriptionHTML: String = ""
    @Persisted var createdAt: Int64 = 0
    @Persisted var updatedAt: Int64 = 0

    public override static func primaryKey() -> String {
        return Constants.primaryKey
    }
}
