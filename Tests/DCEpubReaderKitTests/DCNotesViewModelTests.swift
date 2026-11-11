//
//  DCNotesViewModelTests.swift
//  DCEpubReaderKit
//
//  Created by Liam Smith-Gales on 11/11/26.
//

import Foundation
import SwiftUI
import Testing
import DCEpubCore
@testable import DCEpubRendering

/// The note editor's quote and saving.
@MainActor
@Suite("Note editor")
struct DCNotesViewModelTests {

    @MainActor
    private final class RecordingContext: DCChapterReaderContextProtocol {
        let currentBook = DCEpubBook.mock
        let bookId = "book"
        var saved: [DCHighlight] = []

        func consumeInitialJump(for spineIndex: Int, chapterURL: URL) -> DCChapterJump? { nil }
        func showNote(highlight: DCHighlight) {}
        func save(highlight: DCHighlight) async { saved.append(highlight) }
        func deleteHighlight(uuid: String) async {}
        func highlights(for chapterId: String) async -> [DCHighlight] { [] }
    }

    private func makeViewModel(text: String = "  The quoted passage.\n", note: String = "",
                               context: RecordingContext) -> DCNotesViewModel {
        let highlight = DCHighlight(uuid: "n1", bookId: "book", chapterId: "c1.xhtml", spineIndex: 0,
                                    type: .note, text: text, coords: "", note: note, style: .underline)
        return DCNotesViewModel(highlight: highlight, readerContext: context,
                                userPreferences: DCUserPreferencesMock(),
                                appearance: DCReaderAppearance(theme: .original, isDark: false))
    }

    @Test("Shows the selected passage, trimmed")
    func quotesSelection() {
        let viewModel = makeViewModel(context: RecordingContext())
        #expect(viewModel.quotedText == "The quoted passage.")
    }

    @Test("Closing within the debounce still saves the note")
    func saveNowFlushesPendingEdit() async throws {
        let context = RecordingContext()
        let viewModel = makeViewModel(context: context)
        viewModel.note = "My thought"
        viewModel.noteDidChange("My thought")
        viewModel.saveNow()
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(context.saved.map(\.note) == ["My thought"])

        // The cancelled debounce doesn't save it a second time.
        try await Task.sleep(nanoseconds: 600_000_000)
        #expect(context.saved.count == 1)
    }

    @Test("Closing without changes doesn't save")
    func saveNowWithoutChanges() async throws {
        let context = RecordingContext()
        let viewModel = makeViewModel(note: "Existing", context: context)
        viewModel.saveNow()
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(context.saved.isEmpty)
    }
}
