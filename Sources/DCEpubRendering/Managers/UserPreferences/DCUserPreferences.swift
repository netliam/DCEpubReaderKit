//
//  DCUserPreferences.swift
//  DCEpubReaderKit
//
//  Created by Josep Cerdá Penadés on 26/10/25.
//

import Foundation

/// Keys for the reader settings in user defaults (`UserDefaults` is the preferences store).
enum DCUserPreferences {

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
        // Keys kept from when these were stored separately.
        case themeColors = "DCThemeColors"
        /// Older versions' last highlight color (a `DCHighlightStyle` name), read once.
        case lastHighlightStyle = "DCLastHighlightStyle"
        case lastAnnotationStyle = "DCLastAnnotationStyle"
        case lastHighlightColors = "DCLastHighlightColors"
    }
}
