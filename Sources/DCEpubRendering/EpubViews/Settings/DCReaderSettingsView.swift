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
    @State private var brightness: CGFloat = DCScreenBrightness.value

    init(viewModel: DCReaderSettingsViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Constants.spacing) {
                HStack(spacing: 12) {
                    textSizeControl
                    toggleControls
                }
                brightnessSlider
                themeGrid
                NavigationLink {
                    DCReaderCustomizeView(viewModel: viewModel)
                } label: {
                    Label("Customize", systemImage: "gearshape")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: Constants.controlHeight)
                        .background(.quaternary, in: Capsule())
                }
                .buttonStyle(.plain)
                // Keep the controls at the top when the card is dragged to full height.
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .modifier(DCClearNavigationBackground())
            .navigationTitle("Themes & Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
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
                Text("A")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: Constants.controlHeight)
            }
            .disabled(!viewModel.canDecreaseFontSize)
            .accessibilityLabel("Decrease text size")

            Divider()
                .frame(height: 24)

            Button {
                viewModel.changeFontSize(by: 1)
            } label: {
                Text("A")
                    .font(.system(size: 22, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: Constants.controlHeight)
            }
            .disabled(!viewModel.canIncreaseFontSize)
            .accessibilityLabel("Increase text size")
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
            .accessibilityLabel(viewModel.isScrolling ? "Scrolling" : "Pages")
            .accessibilityHint("Switches between turning pages and scrolling")

            Button {
                viewModel.toggleFollowsSystemAppearance()
            } label: {
                Image(systemName: viewModel.followsSystemAppearance ? "moon.stars.fill" : "moon.stars")
                    .font(.system(size: 18, weight: .medium))
                    .frame(maxWidth: .infinity, minHeight: Constants.controlHeight)
                    .foregroundStyle(viewModel.followsSystemAppearance ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            }
            .accessibilityLabel("Match system dark mode")
            .accessibilityValue(viewModel.followsSystemAppearance ? "On" : "Off")
        }
        .buttonStyle(.plain)
        .background(.quaternary, in: Capsule())
    }

    private var brightnessSlider: some View {
        HStack(spacing: 12) {
            Image(systemName: "sun.min")
                .accessibilityHidden(true)
            Slider(value: $brightness, in: 0...1)
                .accessibilityLabel("Brightness")
                .onChange(of: brightness) { newValue in
                    DCScreenBrightness.value = newValue
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
                Text("Aa")
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
            Section("Font") {
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
            }

            Section("Layout") {
                Toggle("Scrolling", isOn: Binding(
                    get: { viewModel.isScrolling },
                    set: { viewModel.setScrolling($0) }
                ))
                if !viewModel.isScrolling {
                    Picker("Page Turn", selection: Binding(
                        get: { viewModel.selectedTransition },
                        set: { viewModel.select($0) }
                    )) {
                        ForEach(DCPageTransition.allCases, id: \.self) { transition in
                            Label(transition.name, systemImage: transition.iconName).tag(transition)
                        }
                    }
                }
            }

            Section {
                Toggle("Line Guide", isOn: Binding(
                    get: { viewModel.lineFocus },
                    set: { viewModel.setLineFocus($0) }
                ))
                Picker("Style", selection: Binding(
                    get: { viewModel.selectedLineFocusStyle },
                    set: { viewModel.select($0) }
                )) {
                    ForEach(DCLineFocusStyle.allCases, id: \.self) { style in
                        Text(style.name).tag(style)
                    }
                }
            } header: {
                Text("Line Guide")
            } footer: {
                Text("Keeps the line you're reading prominent by dimming or blurring the rest. Tap a line to focus it; tap it again to move to the next.")
            }
        }
        .scrollContentBackground(.hidden)
        .modifier(DCClearNavigationBackground())
        .navigationTitle("Customize")
        .navigationBarTitleDisplayMode(.inline)
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

/// Screen brightness of the active window scene.
@MainActor
enum DCScreenBrightness {
    private static var screen: UIScreen? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .screen
    }

    static var value: CGFloat {
        get { screen?.brightness ?? 0.5 }
        set { screen?.brightness = newValue }
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
        systemIsDark: true,
        userPreferences: DCUserPreferencesMock()
    )
}

#endif
