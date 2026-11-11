//
//  DCNotesViewBuilder.swift
//  DCEpubReaderKit
//
//  Created by Josep Cerdá Penadés on 10/11/25.
//

import Foundation
import DCEpubCore

final class DCNotesViewBuilder {
    @MainActor
    func build(highlight: DCHighlight,
               readerContext: any DCChapterReaderContextProtocol,
               userPreferences: DCUserPreferencesProtocol,
               appearance: DCReaderAppearance) -> DCNotesView {
        let viewModel = DCNotesViewModel(
            highlight: highlight,
            readerContext: readerContext,
            userPreferences: userPreferences,
            appearance: appearance
        )
        return DCNotesView(viewModel: viewModel)
    }
}

final class DCNotesViewBuilderMock {
    @MainActor
    func build() -> DCNotesView {
        let highlight = DCHighlight(
            uuid: "preview-uuid",
            bookId: "preview-book",
            chapterId: "chapter01.xhtml",
            spineIndex: 0,
            type: .note,
            text: "Selected text for preview",
            coords: ""
        )
        let viewModel = DCNotesViewModel(
            highlight: highlight,
            readerContext: DCNotesPreviewContext(),
            userPreferences: DCUserPreferencesMock(),
            appearance: DCReaderAppearance(theme: .original, isDark: false)
        )
        return DCNotesView(viewModel: viewModel)
    }
}

@MainActor
private final class DCNotesPreviewContext: DCChapterReaderContextProtocol {
    let currentBook = DCEpubBook.mock
    let bookId = "preview-book"

    func consumeInitialJump(for spineIndex: Int, chapterURL: URL) -> DCChapterJump? { nil }
    func showNote(highlight: DCHighlight) {}
    func save(highlight: DCHighlight) async {}
    func deleteHighlight(uuid: String) async {}
    func highlights(for chapterId: String) async -> [DCHighlight] { [] }
}
