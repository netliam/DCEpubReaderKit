//
//  DCUserPreferencesProtocol.swift
//  DCEpubReaderKit
//
//  Created by Josep Cerdá Penadés on 3/11/25.
//

import Foundation

protocol DCUserPreferencesProtocol {
    func setValue(key: DCUserPreferences.CacheKey, type: Any)
    func getFontSize() -> DCFontSize
    func getFontFamily() -> DCFontFamily
    func getTheme() -> DCReaderTheme
    /// Whether themes switch to their dark palette when the system is in dark mode.
    func getFollowsSystemAppearance() -> Bool
    func getBookOrientation() -> DCBookrOrientation
    func getPageTransition() -> DCPageTransition
    func getLineFocus() -> Bool
    func getLineFocusStyle() -> DCLineFocusStyle
    /// Line spacing, margins and justification.
    func getTextLayout() -> DCTextLayout
    /// Whether the reader keeps the orientation it was in.
    func getRotationLock() -> Bool
}

extension UserDefaults: DCUserPreferencesProtocol {
    func setValue(key: DCUserPreferences.CacheKey, type: Any) {
        setValue(type, forKey: key.rawValue)
        synchronize()
    }

    func getFontSize() -> DCFontSize {
        guard let number = object(forKey: DCUserPreferences.CacheKey.fontSize.rawValue) as? NSNumber else {
            return .textSizeFour
        }
        switch number {
        case 0:
            return .textSizeOne
        case 1:
            return .textSizeTwo
        case 2:
            return .textSizeThree
        case 3:
            return .textSizeFour
        case 4:
            return .textSizeFive
        case 5:
            return .textSizeSix
        case 6:
            return .textSizeSeven
        case 7:
            return .textSizeEight
        default:
            return .textSizeFour
        }
    }

    func getFontFamily() -> DCFontFamily {
        string(forKey: DCUserPreferences.CacheKey.fontFamily.rawValue).flatMap(DCFontFamily.init(rawValue:)) ?? .original
    }

    func getTheme() -> DCReaderTheme {
        string(forKey: DCUserPreferences.CacheKey.theme.rawValue).flatMap(DCReaderTheme.init(rawValue:)) ?? .original
    }

    func getFollowsSystemAppearance() -> Bool {
        // Defaults to on, like Books.
        object(forKey: DCUserPreferences.CacheKey.followsSystemAppearance.rawValue) as? Bool ?? true
    }

    func getBookOrientation() -> DCBookrOrientation {
        guard let orientation = string(forKey: DCUserPreferences.CacheKey.bookOrientation.rawValue) else {
            return .horizontal
        }
        switch orientation {
        case "horizontal":
            return .horizontal
        case "vertical":
            return .vertical
        default:
            return .horizontal
        }
    }

    func getPageTransition() -> DCPageTransition {
        guard let transition = string(forKey: DCUserPreferences.CacheKey.pageTransition.rawValue) else {
            return .curl
        }
        return DCPageTransition(rawValue: transition) ?? .curl
    }

    func getLineFocus() -> Bool {
        bool(forKey: DCUserPreferences.CacheKey.lineFocus.rawValue)
    }

    func getLineFocusStyle() -> DCLineFocusStyle {
        string(forKey: DCUserPreferences.CacheKey.lineFocusStyle.rawValue).flatMap(DCLineFocusStyle.init(rawValue:)) ?? .guide
    }

    func getTextLayout() -> DCTextLayout {
        typealias Key = DCUserPreferences.CacheKey
        var layout = DCTextLayout()
        if let spacing = string(forKey: Key.lineSpacing.rawValue).flatMap(DCLineSpacing.init(rawValue:)) {
            layout.lineSpacing = spacing
        }
        if let margins = string(forKey: Key.pageMargins.rawValue).flatMap(DCPageMargins.init(rawValue:)) {
            layout.margins = margins
        }
        // Justified unless turned off.
        layout.justified = object(forKey: Key.justifyText.rawValue) as? Bool ?? true
        layout.allowsSpreads = object(forKey: Key.allowSpreads.rawValue) as? Bool ?? true
        let steps = DCTextLayout.spacingSteps
        layout.characterSpacing = min(max(integer(forKey: Key.characterSpacing.rawValue), steps.lowerBound), steps.upperBound)
        layout.wordSpacing = min(max(integer(forKey: Key.wordSpacing.rawValue), steps.lowerBound), steps.upperBound)
        return layout
    }

    func getRotationLock() -> Bool {
        bool(forKey: DCUserPreferences.CacheKey.rotationLock.rawValue)
    }
}

extension DCUserPreferencesProtocol {
    /// The appearance to render with, given whether the system is currently in dark mode.
    func appearance(systemIsDark: Bool) -> DCReaderAppearance {
        DCReaderAppearance(theme: getTheme(), isDark: getFollowsSystemAppearance() && systemIsDark)
    }
}
