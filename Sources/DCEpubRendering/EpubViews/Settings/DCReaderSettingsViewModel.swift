//
//  DCReaderSettingsViewModel.swift
//  DCEpubReaderKit
//
//  Created by Josep Cerdá Penadés on 31/10/25.
//

import SwiftUI

@MainActor
final class DCReaderSettingsViewModel: ObservableObject {

    @Binding var fontSize: CGFloat
    @Binding var textFont: String
    @Binding var theme: String
    @Binding var followsSystemAppearance: Bool
    @Binding var orientation: String
    @Binding var pageTransition: String
    @Binding var lineFocus: Bool
    @Binding var lineFocusStyle: String
    @Binding var textLayout: DCTextLayout
    @Binding var rotationLock: Bool
    @Binding var themeColors: [String: DCThemeColors]

    /// Whether the system is in dark mode, to preview the theme tiles in the palette that will be used.
    let systemIsDark: Bool
    let userPreferences: DCUserPreferencesProtocol

    private let fontSizeRange: ClosedRange<CGFloat> = 0...7

    init(fontSize: Binding<CGFloat>,
         textFont: Binding<String>,
         theme: Binding<String>,
         followsSystemAppearance: Binding<Bool>,
         orientation: Binding<String>,
         pageTransition: Binding<String>,
         lineFocus: Binding<Bool>,
         lineFocusStyle: Binding<String>,
         textLayout: Binding<DCTextLayout>,
         rotationLock: Binding<Bool>,
         themeColors: Binding<[String: DCThemeColors]>,
         systemIsDark: Bool,
         userPreferences: DCUserPreferencesProtocol) {
        self._fontSize = fontSize
        self._textFont = textFont
        self._theme = theme
        self._followsSystemAppearance = followsSystemAppearance
        self._orientation = orientation
        self._pageTransition = pageTransition
        self._lineFocus = lineFocus
        self._lineFocusStyle = lineFocusStyle
        self._textLayout = textLayout
        self._rotationLock = rotationLock
        self._themeColors = themeColors
        self.systemIsDark = systemIsDark
        self.userPreferences = userPreferences
    }

    // MARK: Text size

    var canDecreaseFontSize: Bool { fontSize > fontSizeRange.lowerBound }
    var canIncreaseFontSize: Bool { fontSize < fontSizeRange.upperBound }

    func changeFontSize(by step: CGFloat) {
        let newValue = min(max(fontSize + step, fontSizeRange.lowerBound), fontSizeRange.upperBound)
        guard newValue != fontSize else { return }
        userPreferences.setValue(key: .fontSize, type: newValue)
        fontSize = newValue
    }

    // MARK: Themes

    var selectedTheme: DCReaderTheme {
        DCReaderTheme(rawValue: theme) ?? .original
    }

    /// Tiles preview the palette the reader would actually use right now.
    func previewAppearance(for theme: DCReaderTheme) -> DCReaderAppearance {
        let isDark = followsSystemAppearance && systemIsDark
        return DCReaderAppearance(theme: theme, isDark: isDark,
                                  custom: themeColors[DCThemeColorStore.key(theme, isDark: isDark)])
    }

    func select(_ theme: DCReaderTheme) {
        userPreferences.setValue(key: .theme, type: theme.rawValue)
        self.theme = theme.rawValue
    }

    func toggleFollowsSystemAppearance() {
        let newValue = !followsSystemAppearance
        userPreferences.setValue(key: .followsSystemAppearance, type: newValue)
        followsSystemAppearance = newValue
    }

    // MARK: Layout

    var isScrolling: Bool {
        orientation == DCBookrOrientation.vertical.rawValue
    }

    func setScrolling(_ scrolling: Bool) {
        let value = (scrolling ? DCBookrOrientation.vertical : .horizontal).rawValue
        userPreferences.setValue(key: .bookOrientation, type: value)
        orientation = value
    }

    var selectedTransition: DCPageTransition {
        DCPageTransition(rawValue: pageTransition) ?? .curl
    }

    func select(_ transition: DCPageTransition) {
        userPreferences.setValue(key: .pageTransition, type: transition.rawValue)
        pageTransition = transition.rawValue
    }

    func select(_ font: DCFontFamily) {
        userPreferences.setValue(key: .fontFamily, type: font.rawValue)
        textFont = font.rawValue
    }

    func isSelected(_ font: DCFontFamily) -> Bool {
        // Older builds stored the display name rather than the raw value.
        textFont == font.rawValue || textFont == font.name
    }

    func setLineFocus(_ isOn: Bool) {
        userPreferences.setValue(key: .lineFocus, type: isOn)
        lineFocus = isOn
    }

    var selectedLineFocusStyle: DCLineFocusStyle {
        DCLineFocusStyle(rawValue: lineFocusStyle) ?? .guide
    }

    // MARK: Theme colors

    /// The palette the reader uses now (the selected theme, light or dark), which Customize edits.
    var currentAppearance: DCReaderAppearance {
        previewAppearance(for: selectedTheme)
    }

    var currentPaletteName: String {
        let isDark = followsSystemAppearance && systemIsDark
        return "\(selectedTheme.name)\(isDark ? " (Dark)" : "")"
    }

    func setThemeColors(background: UIColor? = nil, text: UIColor? = nil) {
        let current = currentAppearance
        var colors = DCThemeColors(background: current.background, text: current.text)
        if let background { colors.background = DCReaderAppearance.hex(background) }
        if let text { colors.text = DCReaderAppearance.hex(text) }
        let key = DCThemeColorStore.key(selectedTheme, isDark: current.isDark)
        guard themeColors[key] != colors else { return }
        themeColors[key] = colors
        DCThemeColorStore.all = themeColors
    }

    func resetThemeColors() {
        let key = DCThemeColorStore.key(selectedTheme, isDark: currentAppearance.isDark)
        themeColors[key] = nil
        DCThemeColorStore.all = themeColors
    }

    func setRotationLock(_ locked: Bool) {
        userPreferences.setValue(key: .rotationLock, type: locked)
        rotationLock = locked
    }

    // MARK: Text layout

    func select(_ spacing: DCLineSpacing) {
        userPreferences.setValue(key: .lineSpacing, type: spacing.rawValue)
        textLayout.lineSpacing = spacing
    }

    func select(_ margins: DCPageMargins) {
        userPreferences.setValue(key: .pageMargins, type: margins.rawValue)
        textLayout.margins = margins
    }

    func setCharacterSpacing(_ step: Int) {
        guard step != textLayout.characterSpacing else { return }
        userPreferences.setValue(key: .characterSpacing, type: step)
        textLayout.characterSpacing = step
    }

    func setWordSpacing(_ step: Int) {
        guard step != textLayout.wordSpacing else { return }
        userPreferences.setValue(key: .wordSpacing, type: step)
        textLayout.wordSpacing = step
    }

    func setAllowsSpreads(_ allowed: Bool) {
        userPreferences.setValue(key: .allowSpreads, type: allowed)
        textLayout.allowsSpreads = allowed
    }

    func setJustified(_ justified: Bool) {
        userPreferences.setValue(key: .justifyText, type: justified)
        textLayout.justified = justified
    }

    func select(_ style: DCLineFocusStyle) {
        userPreferences.setValue(key: .lineFocusStyle, type: style.rawValue)
        lineFocusStyle = style.rawValue
    }
}
