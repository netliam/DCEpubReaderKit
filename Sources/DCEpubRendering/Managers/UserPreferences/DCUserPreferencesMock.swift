//
//  DCUserPreferencesMock.swift
//  DCEpubReaderKit
//
//  Created by Josep Cerdá Penadés on 27/10/25.
//

import Foundation
import DCEpubCore

final class DCUserPreferencesMock: DCUserPreferencesProtocol {
    var lineFocus = false
    var lineFocusStyle: DCLineFocusStyle = .guide
    var textLayout = DCTextLayout()
    var rotationLock = false
    var fontChoice = DCFontFamily.original.rawValue
    var themeColors: [String: DCThemeColors] = [:]
    var lastHighlightStyle: DCHighlightStyle = .yellow

    func setValue(key: DCUserPreferences.CacheKey, type: Any) {}
    func getFontSize() -> DCFontSize {
        .textSizeFour
    }

    func getFontFamily() -> DCFontFamily {
        .original
    }

    func getTheme() -> DCReaderTheme {
        .original
    }

    func getFollowsSystemAppearance() -> Bool {
        true
    }

    func getBookOrientation() -> DCBookrOrientation {
        .horizontal
    }

    func getPageTransition() -> DCPageTransition {
        .curl
    }

    func getLineFocus() -> Bool {
        lineFocus
    }

    func getLineFocusStyle() -> DCLineFocusStyle {
        lineFocusStyle
    }

    func getTextLayout() -> DCTextLayout {
        textLayout
    }

    func getRotationLock() -> Bool {
        rotationLock
    }

    func getFontChoice() -> String { fontChoice }
    func getThemeColors() -> [String: DCThemeColors] { themeColors }
    func setThemeColors(_ colors: [String: DCThemeColors]) { themeColors = colors }
    func getLastHighlightStyle() -> DCHighlightStyle { lastHighlightStyle }
    func setLastHighlightStyle(_ style: DCHighlightStyle) { lastHighlightStyle = style }
}
