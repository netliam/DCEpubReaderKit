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
    // Fonts that come with iOS, as Books offers.
    case athelas
    case charter
    case georgia
    case iowan
    case newYork
    case palatino
    case sanFrancisco
    case seravek

    var name: String {
        switch self {
        case .original: "Original"
        case .andada: "AndadaPro"
        case .lato: "Lato"
        case .lora: "Lora"
        case .raleway: "Raleway"
        case .athelas: "Athelas"
        case .charter: "Charter"
        case .georgia: "Georgia"
        case .iowan: "Iowan"
        case .newYork: "New York"
        case .palatino: "Palatino"
        case .sanFrancisco: "San Francisco"
        case .seravek: "Seravek"
        }
    }

    var font: Font {
        font(size: 12)
    }

    /// The font at body size, for the font list in Customize.
    var previewFont: Font {
        font(size: 17)
    }

    private func font(size: CGFloat) -> Font {
        switch self {
        case .original: size == 12 ? Font.system(size: size) : Font.body
        case .andada: Font.fontType(.andadaPro(size))
        case .lato: Font.fontType(.lato(size))
        case .lora: Font.fontType(.lora(size))
        case .raleway: Font.fontType(.raleway(size))
        case .athelas: Font.custom("Athelas-Regular", size: size)
        case .charter: Font.custom("Charter-Roman", size: size)
        case .georgia: Font.custom("Georgia", size: size)
        case .iowan: Font.custom("IowanOldStyle-Roman", size: size)
        case .newYork: Font.system(size: size, design: .serif)
        case .palatino: Font.custom("Palatino-Roman", size: size)
        case .sanFrancisco: Font.system(size: size)
        case .seravek: Font.custom("Seravek", size: size)
        }
    }

    /// The CSS font stack for fonts the system provides; the bundled ones are in Style.css.
    var systemFontStack: String? {
        switch self {
        case .original, .andada, .lato, .lora, .raleway: nil
        case .athelas: #""Athelas", serif"#
        case .charter: #""Charter", serif"#
        case .georgia: #"Georgia, serif"#
        case .iowan: #""Iowan Old Style", serif"#
        case .newYork: #"ui-serif, "New York", serif"#
        case .palatino: #"Palatino, "Palatino Linotype", serif"#
        case .sanFrancisco: #"-apple-system, system-ui, sans-serif"#
        case .seravek: #"Seravek, sans-serif"#
        }
    }

    static let allCases: [DCFontFamily] = [
        .original, .athelas, .charter, .georgia, .iowan, .newYork, .palatino, .sanFrancisco, .seravek,
        .andada, .lato, .lora, .raleway
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

/// A theme palette the reader changed in Customize (Books' custom theme colors), as 0xRRGGBB.
struct DCThemeColors: Codable, Equatable, Sendable {
    var background: UInt32
    var text: UInt32
}

/// Custom colors for each theme's light and dark palette, stored in user defaults.
enum DCThemeColorStore {
    nonisolated(unsafe) static var store: UserDefaults = .standard
    private static let key = "DCThemeColors"

    static func key(_ theme: DCReaderTheme, isDark: Bool) -> String {
        "\(theme.rawValue)-\(isDark ? "dark" : "light")"
    }

    static var all: [String: DCThemeColors] {
        get {
            guard let data = store.data(forKey: key) else { return [:] }
            return (try? JSONDecoder().decode([String: DCThemeColors].self, from: data)) ?? [:]
        }
        set {
            store.set(try? JSONEncoder().encode(newValue), forKey: key)
        }
    }

    static func colors(for theme: DCReaderTheme, isDark: Bool) -> DCThemeColors? {
        all[key(theme, isDark: isDark)]
    }
}

/// The resolved look of the reader: a theme, whether its dark palette is in use, and its colors
/// (the theme's own, or custom ones from Customize).
struct DCReaderAppearance: Equatable {
    let theme: DCReaderTheme
    let isDark: Bool
    /// 0xRRGGBB.
    let background: UInt32
    let text: UInt32

    init(theme: DCReaderTheme, isDark: Bool, custom: DCThemeColors? = nil) {
        self.theme = theme
        self.isDark = isDark
        let palette = theme.palette(isDark: isDark)
        self.background = custom?.background ?? palette.background
        self.text = custom?.text ?? palette.text
    }

    /// With the custom colors saved for this theme and palette, if any.
    static func stored(theme: DCReaderTheme, isDark: Bool) -> DCReaderAppearance {
        DCReaderAppearance(theme: theme, isDark: isDark,
                           custom: DCThemeColorStore.colors(for: theme, isDark: isDark))
    }

    /// Whether the background is dark (by its luminance), whichever palette it comes from.
    var hasDarkBackground: Bool {
        let r = Double((background >> 16) & 0xFF), g = Double((background >> 8) & 0xFF), b = Double(background & 0xFF)
        return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255 < 0.5
    }

    var hasCustomColors: Bool {
        let palette = theme.palette(isDark: isDark)
        return background != palette.background || text != palette.text
    }

    var backgroundColor: Color { Color(uiColor: uiBackgroundColor) }
    var textColor: Color { Color(uiColor: uiTextColor) }
    var uiBackgroundColor: UIColor { Self.color(background) }
    var uiTextColor: UIColor { Self.color(text) }

    /// Identifies everything that affects layout or colors, for rebuilding pages when it changes.
    var id: String { "\(theme.rawValue)-\(isDark ? "dark" : "light")-\(Self.cssHex(background))\(Self.cssHex(text))" }

    var cssTextColor: String { Self.cssHex(text) }

    /// 0xRRGGBB for a color (sRGB, alpha ignored).
    static func hex(_ color: UIColor) -> UInt32 {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func channel(_ value: CGFloat) -> UInt32 { UInt32((min(max(value, 0), 1) * 255).rounded()) }
        return channel(red) << 16 | channel(green) << 8 | channel(blue)
    }

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

// MARK: - Text layout

/// Line spacing, a setting in Books' Customize. `original` keeps the book's own.
enum DCLineSpacing: String, CaseIterable, Sendable {
    case original
    case tight
    case normal
    case relaxed
    case loose

    var name: String {
        switch self {
        case .original: "Original"
        case .tight: "Tight"
        case .normal: "Normal"
        case .relaxed: "Relaxed"
        case .loose: "Loose"
        }
    }

    /// The `line-height` applied to the text, or `nil` to keep the book's.
    var lineHeight: Double? {
        switch self {
        case .original: nil
        case .tight: 1.3
        case .normal: 1.5
        case .relaxed: 1.75
        case .loose: 2
        }
    }
}

/// Page margins at the left and right of the text.
enum DCPageMargins: String, CaseIterable, Sendable {
    case narrow
    case normal
    case wide

    var name: String {
        switch self {
        case .narrow: "Narrow"
        case .normal: "Normal"
        case .wide: "Wide"
        }
    }

    /// Space between the screen edge (inside the safe area) and the text.
    var inset: CGFloat {
        switch self {
        case .narrow: 12
        case .normal: DCReaderChrome.horizontalInset
        case .wide: 44
        }
    }
}

/// Line spacing, margins and justification: settings that change where text falls on the page,
/// so changing one lays the book out again.
struct DCTextLayout: Equatable, Sendable {
    var lineSpacing: DCLineSpacing = .original
    var margins: DCPageMargins = .normal
    /// Justified, like the reader has always been; off aligns text to the start of the line.
    var justified: Bool = true
    /// Two columns side by side on wide landscape pages (Books' "Allow Multiple Columns").
    var allowsSpreads: Bool = true
    /// Extra space between letters and between words, as steps (0 is the book's own).
    var characterSpacing: Int = 0
    var wordSpacing: Int = 0

    static let spacingSteps = 0...4

    /// `letter-spacing` for a step, in em.
    static func characterSpacingEm(_ step: Int) -> Double { Double(step) * 0.02 }
    /// `word-spacing` for a step, in em.
    static func wordSpacingEm(_ step: Int) -> Double { Double(step) * 0.1 }

    /// Part of the layout ids that decide when pages are counted and laid out again.
    var id: String {
        "\(lineSpacing.rawValue)-\(margins.rawValue)-\(justified ? "justified" : "ragged")-\(allowsSpreads ? "spreads" : "single")-c\(characterSpacing)w\(wordSpacing)"
    }

    /// The CSS that applies it (margins are native insets around the web view).
    var css: String {
        var rules: [String] = []
        if let lineHeight = lineSpacing.lineHeight {
            // Headings keep a tighter spacing, as books set them.
            rules.append("html body, html body :where(p, div, li, blockquote, dd, dt, td, span) { line-height: \(lineHeight) !important; }")
            rules.append("html body :where(h1, h2, h3, h4, h5, h6) { line-height: 1.25 !important; }")
        }
        if characterSpacing > 0 {
            rules.append("html body, html body * { letter-spacing: \(Self.characterSpacingEm(characterSpacing))em !important; }")
        }
        if wordSpacing > 0 {
            rules.append("html body, html body * { word-spacing: \(Self.wordSpacingEm(wordSpacing))em !important; }")
        }
        if !justified {
            // Pagination sets `text-align: justify` inline on <body>; !important wins over it, and
            // paragraphs inherit it. A book's own centered or right-aligned text keeps its alignment.
            rules.append("html body { text-align: start !important; }")
            rules.append("html body [style*='justify'] { text-align: start !important; }")
        }
        return rules.joined(separator: "\n")
    }
}
