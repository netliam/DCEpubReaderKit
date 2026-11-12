//
//  DCEpubReaderKitApp.swift
//  DCEpubReaderKit
//
//  Created by Josep Cerdá Penadés on 15/10/25.
//

import SwiftUI

@main
struct DCEpubReaderKitApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init () {
        RealmHelper().applyMigrations()
        print("----------------------------------------------------------------")
        print("Documents path: \(FileHelper.shared.getDocumentsDirectory().path)")
        print("----------------------------------------------------------------")
        print("Temp. path: \(FileHelper.shared.getTempFolder().path)")
        print("----------------------------------------------------------------")
        FileHelper.shared.clearTempSubfolder()
    }

    var body: some Scene {
        WindowGroup {
            MainViewBuilder().build()
        }
    }
}
