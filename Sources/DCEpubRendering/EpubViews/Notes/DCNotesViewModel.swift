//
//  DCNotesViewModel.swift
//  DCEpubReaderKit
//
//  Created by Josep Cerdá Penadés on 10/11/25.
//

import SwiftUI
import DCEpubCore

@MainActor
final class DCNotesViewModel: ObservableObject {

    @Published var note: String

    private var highlight: DCHighlight
    private let readerContext: any DCChapterReaderContextProtocol
    private let userPreferences: DCUserPreferencesProtocol
    private let appearance: DCReaderAppearance
    private var saveTask: Task<Void, Never>?

    init(highlight: DCHighlight,
         readerContext: any DCChapterReaderContextProtocol,
         userPreferences: DCUserPreferencesProtocol,
         appearance: DCReaderAppearance) {
        self.highlight = highlight
        self.readerContext = readerContext
        self.userPreferences = userPreferences
        self.appearance = appearance
        self.note = highlight.note
    }

    var backgroundColor: Color {
        appearance.backgroundColor
    }

    var textColor: Color {
        appearance.textColor
    }

    func noteDidChange(_ text: String) {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            var updated = highlight
            updated.note = text
            updated.dateUpdated = Date().timeIntervalSince1970
            highlight = updated
            await readerContext.save(highlight: updated)
        }
    }
}
