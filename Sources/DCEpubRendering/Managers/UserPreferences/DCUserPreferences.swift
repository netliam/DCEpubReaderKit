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
        case theme
        case followsSystemAppearance
        case pageTransition
        case lineFocus
        case lineFocusStyle
        case lineSpacing
        case pageMargins
        case justifyText
        case rotationLock
        case allowSpreads
        case characterSpacing
        case wordSpacing
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

    func getTheme() -> DCReaderTheme {
        userPreferences.getTheme()
    }

    func getFollowsSystemAppearance() -> Bool {
        userPreferences.getFollowsSystemAppearance()
    }

    func getBookOrientation() -> DCBookrOrientation {
        userPreferences.getBookOrientation()
    }

    func getPageTransition() -> DCPageTransition {
        userPreferences.getPageTransition()
    }

    func getLineFocus() -> Bool {
        userPreferences.getLineFocus()
    }

    func getLineFocusStyle() -> DCLineFocusStyle {
        userPreferences.getLineFocusStyle()
    }

    func getTextLayout() -> DCTextLayout {
        userPreferences.getTextLayout()
    }

    func getRotationLock() -> Bool {
        userPreferences.getRotationLock()
    }
}
