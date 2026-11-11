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

    var isDark: Bool {
        appearance.isDark
    }

    /// The highlighted passage, shown above the editor.
    var quotedText: String {
        highlight.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The highlight's color; underlined notes get the underline's red from Style.css.
    var quoteColor: Color {
        if let swatch = highlight.displayStyle.swatchColor {
            return Color(uiColor: swatch)
        }
        return Color(red: 240 / 255, green: 40 / 255, blue: 20 / 255)
    }

    func noteDidChange(_ text: String) {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            await save(text)
        }
    }

    /// Saves any pending edit right away, so closing the editor within the debounce doesn't lose it.
    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        guard note != highlight.note else { return }
        let text = note
        Task { await save(text) }
    }

    private func save(_ text: String) async {
        guard text != highlight.note else { return }
        var updated = highlight
        updated.note = text
        updated.dateUpdated = Date().timeIntervalSince1970
        highlight = updated
        await readerContext.save(highlight: updated)
    }
}
