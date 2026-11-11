//
//  DCReaderSettingsViewModel.swift
//  DCEpubReaderKit
//
//  Created by Josep Cerdá Penadés on 31/10/25.
//

import SwiftUI

final class DCReaderSettingsViewModel: ObservableObject {

    @Binding var fontSize: CGFloat
    @Binding var textFont: String
    @Binding var desktopMode: String
    @Binding var orientation: String
    @Binding var pageTransition: String

    let userPreferences: DCUserPreferencesProtocol

    init(fontSize: Binding<CGFloat>,
         textFont: Binding<String>,
         desktopMode: Binding<String>,
         orientation: Binding<String>,
         pageTransition: Binding<String>,
         userPreferences: DCUserPreferencesProtocol) {
        self._fontSize = fontSize
        self._textFont = textFont
        self._desktopMode = desktopMode
        self._orientation = orientation
        self._pageTransition = pageTransition
        self.userPreferences = userPreferences
    }

    var backgroundColor: Color {
        userPreferences.getDesktopMode().backgroundColor
    }

    var textColor: Color {
        userPreferences.getDesktopMode().textColor
    }

    /// The page transition only applies to the horizontal (paged) reader.
    var showsPageTransition: Bool {
        orientation == DCBookrOrientation.horizontal.rawValue
    }
}
