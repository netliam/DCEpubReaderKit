//
//  DCChapterWebViewModel.swift
//  DCEpubReaderKit
//
//  Created by Josep Cerdá Penadés on 2/11/25.
//

import SwiftUI
import DCEpubCore

@MainActor
final class DCChapterWebViewModel: ObservableObject {

    var showNotes: Bool = false
    weak var coordinator: DCChapterWebView.Coordinator?

    /// Absolute file URL of the HTML/XHTML chapter.
    let chapterURL: URL
    /// Directory granting read access to all relative resources (usually `opfDirectoryURL`).
    let readAccessURL: URL
    /// Index of the spine that this view represents (used for disambiguating async callbacks).
    let spineIndex: Int
    let userPreferences: DCUserPreferencesProtocol
    let appearance: DCReaderAppearance
    let onAction: (DCChapterViewAction) -> Void
    private let readerContext: any DCChapterReaderContextProtocol
    private var hasConsumedInitialCoords = false

    init(chapterURL: URL,
         readAccessURL: URL,
         spineIndex: Int,
         userPreferences: DCUserPreferencesProtocol,
         appearance: DCReaderAppearance,
         readerContext: any DCChapterReaderContextProtocol,
         onAction: @escaping (DCChapterViewAction) -> Void) {
        self.chapterURL = chapterURL
        self.readAccessURL = readAccessURL
        self.spineIndex = spineIndex
        self.userPreferences = userPreferences
        self.appearance = appearance
        self.readerContext = readerContext
        self.onAction = onAction
    }

    func consumeInitialJump() -> DCChapterJump? {
        guard hasConsumedInitialCoords == false else { return nil }
        hasConsumedInitialCoords = true
        return readerContext.consumeInitialJump(for: spineIndex, chapterURL: chapterURL)
    }
}

extension DCChapterWebViewModel: DCWebViewRouterProtocol {

    func showNoote(highlight: DCHighlight) {
        onAction(.showNote(highlight: highlight))
    }

    func saveHighlight(_ highlight: DCHighlight) async {
        await readerContext.save(highlight: highlight)
    }

    func loadHighlights() async -> [DCHighlight] {
        await readerContext.highlights(for: currentChapterId)
    }

    func deleteHighlight(uuid: String) async {
        await readerContext.deleteHighlight(uuid: uuid)
    }

    var currentBookId: String { readerContext.bookId }
    var currentChapterId: String { chapterURL.lastPathComponent }
    var currentSpineIndex: Int { spineIndex }

    func updateCurrentPage(target: Int?) {
        coordinator?.updateCurrentPageInternal(target: target)
    }

    func saveBookmark() {
        coordinator?.saveBookMark()
    }

    func jump(to jump: DCChapterJump) {
        coordinator?.jump(to: jump)
    }

    func selectedText() async -> String? {
        await coordinator?.lazyWebView?.selectedText()
    }
}
