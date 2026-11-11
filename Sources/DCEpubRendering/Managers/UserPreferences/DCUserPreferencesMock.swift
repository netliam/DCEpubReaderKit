//
//  DCUserPreferencesMock.swift
//  DCEpubReaderKit
//
//  Created by Josep Cerdá Penadés on 27/10/25.
//

import Foundation

final class DCUserPreferencesMock: DCUserPreferencesProtocol {
    func setValue(key: DCUserPreferences.CacheKey, type: Any) {}
    func getFontSize() -> DCFontSize {
        .textSizeFour
    }

    func getFontFamily() -> DCFontFamily {
        .original
    }

    func getDesktopMode() -> DCDesktopMode {
        .lihgt
    }

    func getBookOrientation() -> DCBookrOrientation {
        .horizontal
    }

    func getPageTransition() -> DCPageTransition {
        .curl
    }
}
