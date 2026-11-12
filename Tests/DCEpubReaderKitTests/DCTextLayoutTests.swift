//
//  DCTextLayoutTests.swift
//  DCEpubReaderKit
//
//  Created by Liam Smith-Gales on 11/11/26.
//

import Foundation
import Testing
import SwiftUI
import DCEpubCore
import DCEpubParser
@testable import DCEpubRendering

/// Line spacing, margins and justification.
@Suite("Text layout settings")
struct DCTextLayoutTests {

    @Test func defaultsKeepTheBooksLayout() {
        let layout = DCTextLayout()
        #expect(layout.lineSpacing == .original)
        #expect(layout.margins == .normal)
        #expect(layout.justified)
        // Nothing to override, and the margins are the reader's long-standing inset.
        #expect(layout.css.isEmpty)
        #expect(layout.margins.inset == DCReaderChrome.horizontalInset)
    }

    @Test func cssSetsLineHeightAndAlignment() {
        let layout = DCTextLayout(lineSpacing: .relaxed, margins: .wide, justified: false)
        #expect(layout.css.contains("line-height: 1.75 !important"))
        #expect(layout.css.contains("text-align: start !important"))
        #expect(DCPageMargins.allCases.map(\.inset) == DCPageMargins.allCases.map(\.inset).sorted())
    }

    @Test func storedInUserDefaults() throws {
        let defaults = try #require(UserDefaults(suiteName: "DCTextLayoutTests-\(UUID().uuidString)"))
        #expect(defaults.getTextLayout() == DCTextLayout())
        defaults.setValue(key: .lineSpacing, type: DCLineSpacing.loose.rawValue)
        defaults.setValue(key: .pageMargins, type: DCPageMargins.narrow.rawValue)
        defaults.setValue(key: .justifyText, type: false)
        #expect(defaults.getTextLayout() == DCTextLayout(lineSpacing: .loose, margins: .narrow, justified: false))
    }

    @Test @MainActor func changingItLaysTheBookOutAgain() throws {
        let url = try #require(Bundle.module.url(forResource: "MinimalEPUB", withExtension: nil, subdirectory: "Fixtures"))
        let reader = DCReaderViewModel(book: try DCEpubParser.parse(from: url),
                                       spineIndex: 0,
                                       userPreferencesProtocol: DCUserPreferencesMock(),
                                       delegate: nil)
        let paged = reader.pagedConfigId
        let scrolling = reader.readerConfigId(for: 0)
        reader.textLayout.lineSpacing = .loose
        #expect(reader.pagedConfigId != paged)
        #expect(reader.readerConfigId(for: 0) != scrolling)
    }
}

/// Rotation lock: the setting and the orientation it locks to.
@MainActor
@Suite("Rotation lock")
struct DCRotationLockTests {
    @Test func locksToTheOrientationOnScreen() {
        #expect(DCReaderOrientationLock.mask(for: .portrait) == .portrait)
        #expect(DCReaderOrientationLock.mask(for: .landscapeLeft) == .landscapeLeft)
        #expect(DCReaderOrientationLock.mask(for: .landscapeRight) == .landscapeRight)
        #expect(DCReaderOrientationLock.mask(for: .unknown) == .portrait)
    }

    @Test func settingIsStoredAndUnlockedByDefault() throws {
        let defaults = try #require(UserDefaults(suiteName: "DCRotationLockTests-\(UUID().uuidString)"))
        #expect(defaults.getRotationLock() == false)
        defaults.setValue(key: .rotationLock, type: true)
        #expect(defaults.getRotationLock())
    }

    @Test func closingTheReaderUnlocks() throws {
        let url = try #require(Bundle.module.url(forResource: "MinimalEPUB", withExtension: nil, subdirectory: "Fixtures"))
        let preferences = DCUserPreferencesMock()
        preferences.rotationLock = true
        let reader = DCReaderViewModel(book: try DCEpubParser.parse(from: url), spineIndex: 0,
                                       userPreferencesProtocol: preferences, delegate: nil)
        reader.readerDidAppear()
        reader.readerDidDisappear()
        #expect(DCReaderOrientationLock.supportedOrientations == .all)
    }
}

/// More fonts, and character and word spacing.
@Suite("Fonts and spacing")
struct DCFontsAndSpacingTests {
    @Test func everyFontHasAStylesheetRule() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Sources/DCEpubRendering/Resources/Style.css")
        let css = try String(contentsOf: url, encoding: .utf8)
        for font in DCFontFamily.allCases where font != .original {
            #expect(css.contains(".\(font.rawValue), .\(font.rawValue) p"), "Missing a rule for \(font.rawValue)")
        }
        // System fonts use the same stack in Swift and CSS.
        for font in DCFontFamily.allCases {
            if let stack = font.systemFontStack {
                #expect(css.contains("font-family: \(stack) !important"), "\(font.rawValue)")
            }
        }
    }

    @Test func fontsAndSpacingAreStored() throws {
        let defaults = try #require(UserDefaults(suiteName: "DCFontsAndSpacingTests-\(UUID().uuidString)"))
        defaults.setValue(key: .fontFamily, type: DCFontFamily.iowan.rawValue)
        #expect(defaults.getFontFamily() == .iowan)
        defaults.setValue(key: .fontFamily, type: "no-such-font")
        #expect(defaults.getFontFamily() == .original)

        defaults.setValue(key: .characterSpacing, type: 2)
        defaults.setValue(key: .wordSpacing, type: 9)
        let layout = defaults.getTextLayout()
        #expect(layout.characterSpacing == 2)
        #expect(layout.wordSpacing == DCTextLayout.spacingSteps.upperBound, "out-of-range values are clamped")
    }

    @Test func spacingAddsCSSAndLaysOutAgain() {
        var layout = DCTextLayout()
        let id = layout.id
        layout.characterSpacing = 3
        layout.wordSpacing = 1
        #expect(layout.css.contains("letter-spacing: 0.06em !important"))
        #expect(layout.css.contains("word-spacing: 0.1em !important"))
        #expect(layout.id != id)
    }
}

/// Custom theme colors (Customize → Theme Colors).
@MainActor
@Suite("Custom theme colors", .serialized)
struct DCThemeColorTests {

    private func withTemporaryStore(_ body: () throws -> Void) throws {
        let defaults = try #require(UserDefaults(suiteName: "DCThemeColorTests-\(UUID().uuidString)"))
        let previous = DCThemeColorStore.store
        DCThemeColorStore.store = defaults
        defer { DCThemeColorStore.store = previous }
        try body()
    }

    @Test func appearanceUsesCustomColorsForItsPaletteOnly() throws {
        try withTemporaryStore {
            #expect(DCThemeColorStore.all.isEmpty)
            DCThemeColorStore.all = [DCThemeColorStore.key(.paper, isDark: false): DCThemeColors(background: 0x102030, text: 0xF0E0D0)]

            let custom = DCReaderAppearance.stored(theme: .paper, isDark: false)
            #expect(custom.cssTextColor == "#F0E0D0")
            #expect(DCReaderAppearance.hex(custom.uiBackgroundColor) == 0x102030)
            #expect(custom.hasCustomColors)
            #expect(custom.hasDarkBackground, "a dark custom background in a light palette")
            #expect(custom != DCReaderAppearance(theme: .paper, isDark: false))

            // Paper's dark palette and other themes are unchanged.
            #expect(!DCReaderAppearance.stored(theme: .paper, isDark: true).hasCustomColors)
            #expect(!DCReaderAppearance.stored(theme: .calm, isDark: false).hasCustomColors)
            #expect(!DCReaderAppearance(theme: .original, isDark: false).hasDarkBackground)
        }
    }

    @Test func customizeSetsAndResetsTheCurrentPalette() throws {
        try withTemporaryStore {
            var colors: [String: DCThemeColors] = [:]
            var theme = DCReaderTheme.calm.rawValue
            let settings = DCReaderSettingsViewModel(
                fontSize: .constant(3), textFont: .constant("original"),
                theme: Binding(get: { theme }, set: { theme = $0 }),
                followsSystemAppearance: .constant(true), orientation: .constant("horizontal"),
                pageTransition: .constant("curl"), lineFocus: .constant(false), lineFocusStyle: .constant("guide"),
                textLayout: .constant(DCTextLayout()), rotationLock: .constant(false),
                themeColors: Binding(get: { colors }, set: { colors = $0 }),
                systemIsDark: false, userPreferences: DCUserPreferencesMock())

            settings.setThemeColors(background: UIColor(red: 1, green: 0, blue: 0, alpha: 1))
            let key = DCThemeColorStore.key(.calm, isDark: false)
            #expect(colors[key]?.background == 0xFF0000)
            #expect(colors[key]?.text == DCReaderTheme.calm.palette(isDark: false).text, "text keeps the theme's")
            #expect(DCThemeColorStore.all[key] == colors[key], "saved")
            #expect(settings.currentAppearance.hasCustomColors)

            settings.resetThemeColors()
            #expect(colors[key] == nil)
            #expect(DCThemeColorStore.all.isEmpty)
        }
    }
}
