//
//  DCReaderSettingsView.swift
//  DCEpubReaderKit
//
//  Created by Josep Cerdá Penadés on 29/10/25.
//

import SwiftUI

/// "Themes & Settings": text size, layout and appearance toggles, brightness, theme tiles and
/// a Customize screen, laid out like Apple Books.
struct DCReaderSettingsView: View {

    private enum Constants {
        static let controlHeight: CGFloat = 48
        static let tileHeight: CGFloat = 96
        static let tileCornerRadius: CGFloat = 16
        static let spacing: CGFloat = 16
    }

    @ObservedObject var viewModel: DCReaderSettingsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var brightness: CGFloat

    init(viewModel: DCReaderSettingsViewModel) {
        self.viewModel = viewModel
        _brightness = State(initialValue: DCScreenBrightness.value(of: viewModel.windowScene))
    }

    var body: some View {
        NavigationStack {
            // Scrolls on short screens (landscape), where the controls don't fit under the title.
            ScrollView {
            VStack(spacing: Constants.spacing) {
                HStack(spacing: 12) {
                    textSizeControl
                    toggleControls
                }
                if viewModel.configuration.showsBrightness {
                    brightnessSlider
                }
                themeGrid
                NavigationLink {
                    DCReaderCustomizeView(viewModel: viewModel)
                } label: {
                    Label(L("Customize"), systemImage: "gearshape")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: Constants.controlHeight)
                        .background(.quaternary, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            }
            .scrollBounceBehaviorBasedOnSize()
            .modifier(DCClearNavigationBackground())
            .navigationTitle(L("Themes & Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(L("Close"))
                }
            }
        }
    }

    // MARK: Controls

    private var textSizeControl: some View {
        HStack(spacing: 0) {
            Button {
                viewModel.changeFontSize(by: -1)
            } label: {
                Text(L("A"))
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: Constants.controlHeight)
            }
            .disabled(!viewModel.canDecreaseFontSize)
            .accessibilityLabel(L("Decrease text size"))

            Divider()
                .frame(height: 24)

            Button {
                viewModel.changeFontSize(by: 1)
            } label: {
                Text(L("A"))
                    .font(.system(size: 22, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: Constants.controlHeight)
            }
            .disabled(!viewModel.canIncreaseFontSize)
            .accessibilityLabel(L("Increase text size"))
        }
        .buttonStyle(.plain)
        .background(.quaternary, in: Capsule())
    }

    private var toggleControls: some View {
        HStack(spacing: 0) {
            Button {
                viewModel.setScrolling(!viewModel.isScrolling)
            } label: {
                Image(systemName: viewModel.isScrolling ? "scroll" : "doc.plaintext")
                    .font(.system(size: 18, weight: .medium))
                    .frame(maxWidth: .infinity, minHeight: Constants.controlHeight)
            }
            .accessibilityLabel(viewModel.isScrolling ? L("Scrolling") : L("Pages"))
            .accessibilityHint(L("Switches between turning pages and scrolling"))

            if viewModel.showsRotationLock {
                Button {
                    viewModel.setRotationLock(!viewModel.rotationLock)
                } label: {
                    Image(systemName: viewModel.rotationLock ? "lock.rotation" : "lock.open.rotation")
                        .font(.system(size: 18, weight: .medium))
                        .frame(maxWidth: .infinity, minHeight: Constants.controlHeight)
                        .foregroundStyle(viewModel.rotationLock ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                }
                .accessibilityLabel(L("Rotation Lock"))
                .accessibilityValue(viewModel.rotationLock ? L("On") : L("Off"))
            }

            Button {
                viewModel.toggleFollowsSystemAppearance()
            } label: {
                Image(systemName: viewModel.followsSystemAppearance ? "moon.stars.fill" : "moon.stars")
                    .font(.system(size: 18, weight: .medium))
                    .frame(maxWidth: .infinity, minHeight: Constants.controlHeight)
                    .foregroundStyle(viewModel.followsSystemAppearance ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            }
            .accessibilityLabel(L("Match system dark mode"))
            .accessibilityValue(viewModel.followsSystemAppearance ? L("On") : L("Off"))
        }
        .buttonStyle(.plain)
        .background(.quaternary, in: Capsule())
    }

    private var brightnessSlider: some View {
        HStack(spacing: 12) {
            Image(systemName: "sun.min")
                .accessibilityHidden(true)
            Slider(value: $brightness, in: 0...1)
                .accessibilityLabel(L("Brightness"))
                .onChange(of: brightness) { newValue in
                    DCScreenBrightness.set(newValue, on: viewModel.windowScene)
                }
            Image(systemName: "sun.max")
                .accessibilityHidden(true)
        }
        .foregroundStyle(.secondary)
    }

    private var themeGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
            ForEach(DCReaderTheme.allCases, id: \.self) { theme in
                themeTile(theme)
            }
        }
    }

    private func themeTile(_ theme: DCReaderTheme) -> some View {
        let appearance = viewModel.previewAppearance(for: theme)
        let isSelected = viewModel.selectedTheme == theme
        return Button {
            viewModel.select(theme)
        } label: {
            VStack(spacing: 2) {
                Text(L("Aa"))
                    .font(.system(size: 30, weight: theme.fontWeight > 400 ? .bold : .regular))
                Text(theme.name)
                    .font(.caption)
            }
            .foregroundStyle(appearance.textColor)
            .frame(maxWidth: .infinity, minHeight: Constants.tileHeight)
            .background(appearance.backgroundColor,
                        in: RoundedRectangle(cornerRadius: Constants.tileCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Constants.tileCornerRadius, style: .continuous)
                    .strokeBorder(isSelected ? Color.primary : Color.secondary.opacity(0.25),
                                  lineWidth: isSelected ? 3 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Customize

struct DCReaderCustomizeView: View {

    @ObservedObject var viewModel: DCReaderSettingsViewModel

    var body: some View {
        Form {
            Section(L("Font")) {
                ForEach(DCFontFamily.allCases, id: \.self) { font in
                    Button {
                        viewModel.select(font)
                    } label: {
                        HStack {
                            Text(font.name)
                                .font(font.previewFont)
                                .foregroundStyle(.primary)
                            Spacer()
                            if viewModel.isSelected(font) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    // Form buttons draw their label in the accent color; font names should read as text.
                    .tint(.primary)
                    .accessibilityAddTraits(viewModel.isSelected(font) ? .isSelected : [])
                }
                ForEach(viewModel.configuration.fonts, id: \.name) { font in
                    Button {
                        viewModel.select(font)
                    } label: {
                        HStack {
                            Text(font.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            if viewModel.textFont == font.storageKey {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .tint(.primary)
                    .accessibilityAddTraits(viewModel.textFont == font.storageKey ? .isSelected : [])
                }
            }

            Section(L("Text")) {
                Picker(L("Line Spacing"), selection: Binding(
                    get: { viewModel.textLayout.lineSpacing },
                    set: { viewModel.select($0) }
                )) {
                    ForEach(DCLineSpacing.allCases, id: \.self) { spacing in
                        Text(spacing.name).tag(spacing)
                    }
                }
                Picker(L("Margins"), selection: Binding(
                    get: { viewModel.textLayout.margins },
                    set: { viewModel.select($0) }
                )) {
                    ForEach(DCPageMargins.allCases, id: \.self) { margins in
                        Text(margins.name).tag(margins)
                    }
                }
                Toggle(L("Justify Text"), isOn: Binding(
                    get: { viewModel.textLayout.justified },
                    set: { viewModel.setJustified($0) }
                ))
                spacingSlider(L("Character Spacing"),
                              value: viewModel.textLayout.characterSpacing,
                              set: viewModel.setCharacterSpacing)
                spacingSlider(L("Word Spacing"),
                              value: viewModel.textLayout.wordSpacing,
                              set: viewModel.setWordSpacing)
            }

            Section {
                ColorPicker(L("Background"), selection: Binding(
                    get: { viewModel.currentAppearance.backgroundColor },
                    set: { viewModel.setThemeColors(background: UIColor($0)) }
                ), supportsOpacity: false)
                ColorPicker(L("Text"), selection: Binding(
                    get: { viewModel.currentAppearance.textColor },
                    set: { viewModel.setThemeColors(text: UIColor($0)) }
                ), supportsOpacity: false)
                Button(L("Reset to Theme Colors"), role: .destructive) {
                    viewModel.resetThemeColors()
                }
                .disabled(!viewModel.currentAppearance.hasCustomColors)
            } header: {
                Text(L("Theme Colors"))
            } footer: {
                Text(String(format: L("Changes the %@ theme."), viewModel.currentPaletteName))
            }

            Section(L("Layout")) {
                Toggle(L("Scrolling"), isOn: Binding(
                    get: { viewModel.isScrolling },
                    set: { viewModel.setScrolling($0) }
                ))
                if viewModel.showsRotationLock {
                    Toggle(L("Lock Rotation"), isOn: Binding(
                        get: { viewModel.rotationLock },
                        set: { viewModel.setRotationLock($0) }
                    ))
                }
                if !viewModel.isScrolling {
                    Toggle(L("Allow Multiple Columns"), isOn: Binding(
                        get: { viewModel.textLayout.allowsSpreads },
                        set: { viewModel.setAllowsSpreads($0) }
                    ))
                }
                if !viewModel.isScrolling && viewModel.configuration.allowsPageCurl {
                    Picker(L("Page Turn"), selection: Binding(
                        get: { viewModel.selectedTransition },
                        set: { viewModel.select($0) }
                    )) {
                        ForEach(DCPageTransition.allCases, id: \.self) { transition in
                            Label(transition.name, systemImage: transition.iconName).tag(transition)
                        }
                    }
                }
            }

            if viewModel.configuration.showsLineGuide {
                Section {
                    Toggle(L("Line Guide"), isOn: Binding(
                        get: { viewModel.lineFocus },
                        set: { viewModel.setLineFocus($0) }
                    ))
                    Picker(L("Style"), selection: Binding(
                        get: { viewModel.selectedLineFocusStyle },
                        set: { viewModel.select($0) }
                    )) {
                        ForEach(DCLineFocusStyle.allCases, id: \.self) { style in
                            Text(style.name).tag(style)
                        }
                    }
                } header: {
                    Text(L("Line Guide"))
                } footer: {
                    Text(L("Keeps the line you're reading prominent by dimming or blurring the rest. Tap a line to focus it; tap it again to move to the next."))
                }
            }
        }
        .scrollContentBackground(.hidden)
        .modifier(DCClearNavigationBackground())
        .navigationTitle(L("Customize"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension DCReaderCustomizeView {
    /// A stepped slider from the book's own spacing ("Default") to the widest step.
    func spacingSlider(_ title: String, value: Int, set: @escaping (Int) -> Void) -> some View {
        let steps = DCTextLayout.spacingSteps
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(value == 0 ? L("Default") : "+\(value)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: Binding(get: { Double(value) }, set: { set(Int($0.rounded())) }),
                   in: Double(steps.lowerBound)...Double(steps.upperBound), step: 1)
                .accessibilityLabel(title)
                .accessibilityValue(value == 0 ? L("Default") : String(format: L("%lld of %lld"), value, steps.upperBound))
        }
    }
}

// MARK: - Backgrounds

/// Lets the sheet's material show through a NavigationStack, whose container is opaque by default.
struct DCClearNavigationBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.containerBackground(.clear, for: .navigation)
        } else {
            content
        }
    }
}

// MARK: - Brightness

/// Brightness of the screen the reader's window is on.
@MainActor
enum DCScreenBrightness {
    static func value(of scene: UIWindowScene?) -> CGFloat {
        scene?.screen.brightness ?? 0.5
    }

    static func set(_ value: CGFloat, on scene: UIWindowScene?) {
        scene?.screen.brightness = value
    }
}

#if DEBUG

#Preview {
    DCReaderSettingsViewBuilder().build(
        fontSize: .constant(3),
        textFont: .constant(DCFontFamily.original.rawValue),
        theme: .constant(DCReaderTheme.original.rawValue),
        followsSystemAppearance: .constant(true),
        orientation: .constant(DCBookrOrientation.horizontal.rawValue),
        pageTransition: .constant(DCPageTransition.curl.rawValue),
        lineFocus: .constant(false),
        lineFocusStyle: .constant(DCLineFocusStyle.guide.rawValue),
        textLayout: .constant(DCTextLayout()),
        rotationLock: .constant(false),
        themeColors: .constant([:]),
        systemIsDark: true,
        userPreferences: DCUserPreferencesMock()
    )
}

#endif

private extension View {
    /// Doesn't bounce when everything fits (iOS 16.4 and later).
    @ViewBuilder
    func scrollBounceBehaviorBasedOnSize() -> some View {
        if #available(iOS 16.4, *) {
            scrollBounceBehavior(.basedOnSize)
        } else {
            self
        }
    }
}
