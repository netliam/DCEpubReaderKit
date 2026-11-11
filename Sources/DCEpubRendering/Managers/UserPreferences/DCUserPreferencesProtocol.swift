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
    func getDesktopMode() -> DCDesktopMode
    func getBookOrientation() -> DCBookrOrientation
    func getPageTransition() -> DCPageTransition
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
        guard let fontFamily = string(forKey: DCUserPreferences.CacheKey.fontFamily.rawValue) else {
            return .original
        }
        switch fontFamily {
        case "original":
            return .original
        case "andada":
            return .andada
        case "lato":
            return .lato
        case "lora":
            return .lora
        case "raleway":
            return .raleway
        default:
            return .original
        }
    }

    func getDesktopMode() -> DCDesktopMode {
        guard let desktopMode = string(forKey: DCUserPreferences.CacheKey.desktopMode.rawValue) else {
            return .lihgt
        }
        switch desktopMode {
        case "":
            return .lihgt
        case "nightMode":
            return .dark
        case "redMode":
            return .red
        default:
            return .lihgt
        }
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
}
