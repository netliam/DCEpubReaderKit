//
//  RealmHelper.swift
//  DCEpubReaderKit
//
//  Created by Josep Cerdá Penadés on 22/12/25.
//

import Foundation
import RealmSwift

protocol RealmHelperProtocol {
    func applyMigrations()
}

final class RealmHelper: RealmHelperProtocol {

    private let utils: UtilsProtocol

    init(utils: UtilsProtocol = Utils()) {
        self.utils = utils
    }

    func applyMigrations() {
        let filemanager = utils.fileManager
        let realmFileURL = utils.realmFileURL()
        if !filemanager.fileExists(atPath: realmFileURL.path) {
            utils.createDirectory(directoryName: Utils.Directories.database.rawValue)
        }
        var config = Realm.Configuration(
            fileURL: realmFileURL,
            schemaVersion: 2,
            migrationBlock: { _, _ in },
            shouldCompactOnLaunch: {totalBytes, usedBytes in
                // totalBytes refers to the size of the file on disk in bytes (data + free space)
                // usedBytes refers to the number of bytes used by data in the file
                // Compact if the file is over 30MB in size and less than 50% 'used'
                let oneHundredMB = 30 * 1024 * 1024
                return (totalBytes > oneHundredMB) && (Double(usedBytes) / Double(totalBytes)) < 0.5
            })
        config.deleteRealmIfMigrationNeeded = true
        Realm.Configuration.defaultConfiguration = config
    }
}
