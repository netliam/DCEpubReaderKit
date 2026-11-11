//
//  DCUserPreferences.swift
//  DCEpubReaderKit
//
//  Created by Josep Cerdá Penadés on 26/10/25.
//

import Foundation

final class DCUserPreferences: DCUserPreferencesProtocol {

    enum CacheKey: String {
        case bookOrientation
        case fontSize
        case fontFamily
        case desktopMode
        case pageTransition
    }

    private let userPreferences: DCUserPreferencesProtocol

    init(userPreferences: DCUserPreferencesProtocol) {
        self.userPreferences = userPreferences
    }

    func setValue(key: CacheKey, type: Any) {
        userPreferences.setValue(key: key, type: type)
    }

    func getFontSize() -> DCFontSize {
        userPreferences.getFontSize()
    }

    func getFontFamily() -> DCFontFamily {
        userPreferences.getFontFamily()
    }

    func getDesktopMode() -> DCDesktopMode {
        userPreferences.getDesktopMode()
    }

    func getBookOrientation() -> DCBookrOrientation {
        userPreferences.getBookOrientation()
    }

    func getPageTransition() -> DCPageTransition {
        userPreferences.getPageTransition()
    }
}
