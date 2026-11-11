//
//  DCUserPreferencesTypes.swift
//  DCEpubReaderKit
//
//  Created by Josep Cerdá Penadés on 3/11/25.
//

import SwiftUI

// MARK: - DCFontSize

enum DCFontSize: String {
    case textSizeOne
    case textSizeTwo
    case textSizeThree
    case textSizeFour
    case textSizeFive
    case textSizeSix
    case textSizeSeven
    case textSizeEight

    var size: CGFloat {
        switch self {
        case .textSizeOne:
            return 0
        case .textSizeTwo:
            return 1
        case .textSizeThree:
            return 2
        case .textSizeFour:
            return 3
        case .textSizeFive:
            return 4
        case .textSizeSix:
            return 5
        case .textSizeSeven:
            return 6
        case .textSizeEight:
            return 7
        }
    }
}

// MARK: - DCFontFamily

enum DCFontFamily: String {
    case original
    case andada
    case lato
    case lora
    case raleway

    var name: String {
        switch self {
        case .original:
            "Original"
        case .andada:
            "AndadaPro"
        case .lato:
            "Lato"
        case .lora:
            "Lora"
        case .raleway:
            "Raleway"
        }
    }

    var font: Font {
        switch self {
        case .original:
            Font.system(size: 12)
        case .andada:
            Font.fontType(.andadaPro(12))
        case .lato:
            Font.fontType(.lato(12))
        case .lora:
            Font.fontType(.lora(12))
        case .raleway:
            Font.fontType(.raleway(12))
        }
    }

    static let allCases: [DCFontFamily] = [
        .original,
        .andada,
        .lato,
        .lora,
        .raleway
    ]
}

// MARK: - DCDesktopMode

enum DCDesktopMode: String {
    case lihgt
    case dark
    case red

    var mode: String {
        switch self {
        case .lihgt:
            ""
        case .dark:
            "nightMode"
        case .red:
            "redMode"
        }
    }

    var name: String {
        switch self {
        case .lihgt:
            "Day"
        case .dark:
            "Dark"
        case .red:
            "Red"
        }
    }

    var icon: String {
        switch self {
        case .lihgt:
            "sun.max.fill"
        case .dark:
            "moon.fill"
        case .red:
            "Red"
        }
    }

    var backgroundColor: Color {
        switch self {
        case .lihgt:
            Color(.backgroundLight)
        case .dark, .red:
            Color(.backgroundNight)
        }
    }

    var textColor: Color {
        switch self {
        case .lihgt:
            Color(.backgroundNight)
        case .dark, .red:
            Color(.backgroundLight)
        }
    }

    var iconColor: Color {
        switch self {
        case .lihgt:
            Color(.backgroundLight)
        case .dark:
            Color(.backgroundNight)
        case .red:
                .red
        }
    }

    static let allCase: [DCDesktopMode] = [
        .lihgt,
        .dark,
        .red
    ]
}

// MARK: - DCBookrOrientation

enum DCBookrOrientation: String {
    case vertical
    case horizontal

    var name: String {
        switch self {
        case .vertical:
            "Vertical"
        case .horizontal:
            "Horizontal"
        }
    }

    var icon: Image {
        switch self {
        case .vertical:
            Image(.verticalRead)
        case .horizontal:
            Image(.horizontalRead)
        }
    }

    static let allCases: [DCBookrOrientation] = [
        .vertical,
        .horizontal
    ]
}

// MARK: - DCPageTransition

/// Page turn animation used by the horizontal (paged) reader.
enum DCPageTransition: String {
    case curl
    case slide

    var name: String {
        switch self {
        case .curl:
            "Curl"
        case .slide:
            "Slide"
        }
    }

    var iconName: String {
        switch self {
        case .curl:
            "book"
        case .slide:
            "rectangle.on.rectangle"
        }
    }

    static let allCases: [DCPageTransition] = [
        .curl,
        .slide
    ]
}
