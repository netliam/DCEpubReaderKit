//
//  DCReaderSettingsViewBuilder.swift
//  DCEpubReaderKit
//
//  Created by Josep Cerdá Penadés on 31/10/25.
//

import SwiftUI

final class DCReaderSettingsViewBuilder {
    @MainActor
    func build(fontSize: Binding<CGFloat>,
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
               userPreferences: DCUserPreferencesProtocol,
               configuration: DCReaderConfiguration = DCReaderConfiguration(),
               windowScene: UIWindowScene? = nil) -> DCReaderSettingsView {
        let viewModel = DCReaderSettingsViewModel(fontSize: fontSize,
                                                  textFont: textFont,
                                                  theme: theme,
                                                  followsSystemAppearance: followsSystemAppearance,
                                                  orientation: orientation,
                                                  pageTransition: pageTransition,
                                                  lineFocus: lineFocus,
                                                  lineFocusStyle: lineFocusStyle,
                                                  textLayout: textLayout,
                                                  rotationLock: rotationLock,
                                                  themeColors: themeColors,
                                                  systemIsDark: systemIsDark,
                                                  userPreferences: userPreferences,
                                                  configuration: configuration,
                                                  windowScene: windowScene)
        return DCReaderSettingsView(viewModel: viewModel)
    }
}
