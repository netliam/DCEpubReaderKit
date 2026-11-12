//
//  DCReaderViewBuilder.swift
//  DCEpubReaderKit
//
//  Created by Josep Cerdá Penadés on 31/10/25.
//

import Foundation
import DCEpubCore

public final class DCReaderViewBuilder {
    @MainActor
    public static func build(_ book: DCEpubBook,
                             spineIndex: Int,
                             initialCoords: String? = nil,
                             delegate: DCReaderCoordsProtocol?,
                             configuration: DCReaderConfiguration = DCReaderConfiguration()) -> DCReaderView {
        let viewModel = DCReaderViewModel(
            book: book,
            spineIndex: spineIndex,
            initialCoords: initialCoords,
            userPreferencesProtocol: configuration.defaults,
            delegate: delegate,
            configuration: configuration
        )
        DCFonts.registerAllFontsIfNeeded()
        let view = DCReaderView(viewModel: viewModel)
        return view
    }
}

final class DCReaderViewBuilderMock {
    @MainActor
    static func build(_ book: DCEpubBook,
                      spineIndex: Int) -> DCReaderView {
        let userPreferences: DCUserPreferencesProtocol = DCUserPreferencesMock()
        let viewModel = DCReaderViewModel(
            book: book,
            spineIndex: spineIndex,
            initialCoords: nil,
            userPreferencesProtocol: userPreferences,
            delegate: nil
        )
        let view = DCReaderView(viewModel: viewModel)
        return view
    }
}
