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

    /// The font at body size, for the font list in Customize.
    var previewFont: Font {
        switch self {
        case .original:
            Font.body
        case .andada:
            Font.fontType(.andadaPro(17))
        case .lato:
            Font.fontType(.lato(17))
        case .lora:
            Font.fontType(.lora(17))
        case .raleway:
            Font.fontType(.raleway(17))
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

// MARK: - DCReaderTheme

/// Reading themes, modelled on Apple Books. Each has a light and a dark palette; which one is used
/// depends on `DCReaderAppearance` (the "match system dark mode" setting and the system appearance).
enum DCReaderTheme: String, CaseIterable {
    case original
    case quiet
    case paper
    case bold
    case calm
    case focus

    var name: String {
        switch self {
        case .original: "Original"
        case .quiet: "Quiet"
        case .paper: "Paper"
        case .bold: "Bold"
        case .calm: "Calm"
        case .focus: "Focus"
        }
    }

    /// (background, text) as 0xRRGGBB.
    func palette(isDark: Bool) -> (background: UInt32, text: UInt32) {
        switch (self, isDark) {
        case (.original, false), (.bold, false): (0xFFFFFF, 0x000000)
        case (.original, true), (.bold, true): (0x000000, 0xFFFFFF)
        case (.quiet, false): (0xECECEC, 0x5E5E5E)
        case (.quiet, true): (0x1C1C1E, 0x8D8D92)
        case (.paper, false): (0xF6F4EF, 0x2A2A2A)
        case (.paper, true): (0x2B2B2D, 0xE3E3E3)
        case (.calm, false): (0xF3EAD3, 0x4A3E2C)
        case (.calm, true): (0x4A4337, 0xEADFC8)
        case (.focus, false): (0xFBF7EC, 0x1F1B14)
        case (.focus, true): (0x1D1A12, 0xF1E7D2)
        }
    }

    /// CSS font weight for body text.
    var fontWeight: Int {
        self == .bold ? 700 : 400
    }
}

/// The resolved look of the reader: a theme plus whether its dark palette is in use.
struct DCReaderAppearance: Equatable {
    let theme: DCReaderTheme
    let isDark: Bool

    init(theme: DCReaderTheme, isDark: Bool) {
        self.theme = theme
        self.isDark = isDark
    }

    var backgroundColor: Color { Color(uiColor: uiBackgroundColor) }
    var textColor: Color { Color(uiColor: uiTextColor) }
    var uiBackgroundColor: UIColor { Self.color(theme.palette(isDark: isDark).background) }
    var uiTextColor: UIColor { Self.color(theme.palette(isDark: isDark).text) }

    /// Identifies everything that affects layout or colors, for rebuilding pages when it changes.
    var id: String { "\(theme.rawValue)-\(isDark ? "dark" : "light")" }

    var cssTextColor: String { Self.cssHex(theme.palette(isDark: isDark).text) }

    private static func color(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1)
    }

    private static func cssHex(_ hex: UInt32) -> String {
        String(format: "#%06X", hex)
    }
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
