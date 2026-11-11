//
//  DCChapterWebViewBuilder.swift
//  DCEpubReaderKit
//
//  Created by Josep Cerdá Penadés on 2/11/25.
//

import Foundation
import DCEpubCore

final class DCChapterWebViewBuilder {
    @MainActor
    func build(chapterURL: URL,
               readAccessURL: URL,
               spineIndex: Int,
               userPreferences: DCUserPreferencesProtocol,
               appearance: DCReaderAppearance,
               readerContext: any DCChapterReaderContextProtocol,
               onAction: @escaping (DCChapterViewAction) -> Void) -> DCChapterWebView {
        let viewModel = DCChapterWebViewModel(
            chapterURL: chapterURL,
            readAccessURL: readAccessURL,
            spineIndex: spineIndex,
            userPreferences: userPreferences,
            appearance: appearance,
            readerContext: readerContext,
            onAction: onAction
        )
        let view = DCChapterWebView(viewModel: viewModel)
        return view
    }
}
