//
//  DCWebView+Highlights.swift
//  DCEpubReaderKit
//
//  Created by Josep Cerdá Penadés on 24/10/25.
//

import WebKit
import DCEpubCore

// MARK: - DCWebView Highlights

extension DCWebView {

    private enum JSMethod {
        case rectsForSelection
        case getCoordsFromSelection
        case getSelectionString
        case highlight(cssClass: String, uuid: String)
        case clearSelection
        case highlightCoords(coords: String, cssClass: String, uuid: String, text: String)
        case removeHighlightById(uuid: String)
        case setStyle(uuid: String, cssClass: String)
        case setNote(uuid: String, hasNote: Bool)
        case isHighlightAtPoint(CGPoint)

        var rawValue: String {
            switch self {
            case .rectsForSelection:
                return "rectsForSelection()"
            case .getCoordsFromSelection:
                return "getCoordsFromSelection()"
            case .getSelectionString:
                return "window.getSelection().toString()"
            case let .highlight(cssClass, uuid):
                return "highlightSelectionInPlace(\(jsLiteral(cssClass)),\(jsLiteral(uuid)))"
            case .clearSelection:
                return "window.getSelection().removeAllRanges()"
            case let .highlightCoords(coords, cssClass, uuid, text):
                return "highlightCoords(\(jsLiteral(coords)),\(jsLiteral(cssClass)),\(jsLiteral(uuid)),\(jsLiteral(text)))"
            case let .removeHighlightById(uuid):
                return "removeHighlightById(\(jsLiteral(uuid)))"
            case let .setStyle(uuid, cssClass):
                return "setHighlightStyleById(\(jsLiteral(uuid)),\(jsLiteral(cssClass)))"
            case let .setNote(uuid, hasNote):
                return "setHighlightNoteById(\(jsLiteral(uuid)),\(hasNote))"
            case let .isHighlightAtPoint(point):
                return "isTappableAtPoint(\(Double(point.x)),\(Double(point.y)))"
            }
        }

        private func jsLiteral(_ str: String) -> String {
            guard let data = try? JSONSerialization.data(withJSONObject: [str]),
                  let json = String(data: data, encoding: .utf8) else {
                return "\"\""
            }
            return String(json.dropFirst().dropLast())
        }
    }

    // MARK: Selection menu

    /// The Books-style edit menu for selected text: a row of highlight colors, Add Note,
    /// Look Up, Translate, Search, Copy and Share. Replaces everything else the system offers.
    func selectionMenuElements(systemLookUp: [UIMenuElement]) -> [UIMenuElement] {
        let styles = DCHighlightStyle.allCases.map { style in
            // No title: the compact edit menu shows titles instead of images. VoiceOver reads the label.
            let action = UIAction(title: "", image: style.menuImage) { [weak self] _ in
                self?.highlightSelection(style: style)
            }
            action.accessibilityLabel = style.menuTitle
            return action
        }
        let colors: UIMenu
        if #available(iOS 17.0, *) {
            colors = UIMenu(options: [.displayInline, .displayAsPalette], children: styles)
        } else {
            colors = UIMenu(options: .displayInline, children: styles)
        }
        colors.preferredElementSize = .small

        let addNote = UIAction(title: "Add Note", image: UIImage(systemName: "note.text.badge.plus")) { [weak self] _ in
            self?.addNoteToSelection()
        }

        // Look Up and Translate come from the system (there's no public Translate API); its
        // "Search Web" gives way to searching the book.
        var lookUp = systemLookUp
        if lookUp.isEmpty {
            lookUp = [UIAction(title: "Look Up", image: UIImage(systemName: "character.book.closed")) { [weak self] _ in
                self?.lookUpSelection()
            }]
        }
        let search = UIAction(title: "Search", image: UIImage(systemName: "magnifyingglass")) { [weak self] _ in
            self?.searchBookForSelection()
        }
        let copy = UIAction(title: "Copy", image: UIImage(systemName: "doc.on.doc")) { [weak self] _ in
            self?.copySelection()
        }
        let share = UIAction(title: "Share…", image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in
            self?.shareSelection()
        }

        return [
            colors,
            UIMenu(options: .displayInline, children: [addNote]),
            UIMenu(options: .displayInline, children: lookUp + [search, copy]),
            UIMenu(options: .displayInline, children: [share])
        ]
    }

    /// The system's Look Up and Translate commands, without its web search.
    static func lookUpCommands(in menu: UIMenu?) -> [UIMenuElement] {
        (menu?.children ?? []).filter { element in
            guard let command = element as? UICommand else { return true }
            return NSStringFromSelector(command.action).lowercased().contains("search") == false
        }
    }

    /// Highlights the selection with `style` and saves it.
    func highlightSelection(style: DCHighlightStyle) {
        Task { @MainActor [weak self] in
            await self?.saveSelection(type: .highlight, style: style)
        }
    }

    /// Underlines the selection, saves it as a note and opens the note editor.
    func addNoteToSelection() {
        Task { @MainActor [weak self] in
            guard let self, let highlight = await self.saveSelection(type: .note, style: .underline) else { return }
            self.viewModel.showNoote(highlight: highlight)
        }
    }

    /// Draws and saves the selection, which may span paragraphs. `nil` when nothing is selected
    /// or the selection overlaps an existing highlight.
    @discardableResult
    private func saveSelection(type: DCHighlight.MarkType, style: DCHighlightStyle) async -> DCHighlight? {
        // Coords first: drawing the highlight splits the text nodes they're taken from.
        guard let coords = await getCoordsFromSelection(),
              let selectedText = await getSelectedText()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !selectedText.isEmpty,
              let uuid = await highlightSelection(cssClass: style.cssClass, uuid: UUID().uuidString) else {
            return nil
        }
        let highlight = DCHighlight(
            uuid: uuid,
            bookId: viewModel.currentBookId,
            chapterId: viewModel.currentChapterId,
            spineIndex: viewModel.currentSpineIndex,
            type: type,
            text: selectedText,
            coords: coords,
            style: style
        )
        await viewModel.saveHighlight(highlight)
        await clearJSSelection()
        return highlight
    }

    func searchBookForSelection() {
        Task { @MainActor [weak self] in
            guard let self, let text = await self.selectedText() else { return }
            await self.clearJSSelection()
            self.viewModel.searchBook(for: text)
        }
    }

    func copySelection() {
        Task { @MainActor [weak self] in
            guard let self, let text = await self.selectedText() else { return }
            UIPasteboard.general.string = text
            await self.clearJSSelection()
        }
    }

    func lookUpSelection() {
        Task { @MainActor [weak self] in
            guard let self, let text = await self.selectedText(), let presenter = self.parentViewController else { return }
            presenter.present(UIReferenceLibraryViewController(term: text), animated: true)
        }
    }

    func shareSelection() {
        Task { @MainActor [weak self] in
            guard let self, let text = await self.selectedText(), let presenter = self.parentViewController else { return }
            let sourceRect = await self.selectionRect() ?? CGRect(x: self.bounds.midX, y: self.bounds.midY, width: 0, height: 0)
            await self.clearJSSelection()
            let activity = UIActivityViewController(activityItems: [text], applicationActivities: nil)
            activity.popoverPresentationController?.sourceView = self
            activity.popoverPresentationController?.sourceRect = sourceRect
            presenter.present(activity, animated: true)
        }
    }

    /// The first rect of the selection, in the web view's coordinates.
    private func selectionRect() async -> CGRect? {
        guard let rectsString = await getRectsFromSelection(),
              let rectsData = rectsString.data(using: .utf8),
              let rects = try? JSONSerialization.jsonObject(with: rectsData) as? [[String: Any]],
              let first = rects.first,
              let x = first["x"] as? CGFloat,
              let y = first["y"] as? CGFloat else { return nil }
        let width = first["width"] as? CGFloat ?? 0
        let height = first["height"] as? CGFloat ?? 0
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func getRectsFromSelection() async -> String? {
        try? await self.evaluateJavaScriptAsync(JSMethod.rectsForSelection.rawValue) as? String
    }

    private func getCoordsFromSelection() async -> String? {
        try? await self.evaluateJavaScriptAsync(JSMethod.getCoordsFromSelection.rawValue) as? String
    }

    private func getSelectedText() async -> String? {
        try? await self.evaluateJavaScriptAsync(JSMethod.getSelectionString.rawValue) as? String
    }

    private func highlightSelection(cssClass: String, uuid: String) async -> String? {
        try? await self.evaluateJavaScriptAsync(JSMethod.highlight(cssClass: cssClass, uuid: uuid).rawValue) as? String
    }

    private func clearJSSelection() async {
        _ = try? await self.evaluateJavaScriptAsync(JSMethod.clearSelection.rawValue)
    }

    // Removes every part of the highlight from the DOM without touching the store.
    func removeHighlight(uuid: String) async {
        _ = try? await self.evaluateJavaScriptAsync(JSMethod.removeHighlightById(uuid: uuid).rawValue)
    }

    /// Redraws a highlight already in the page with its current style and note marker.
    /// Does nothing if the page doesn't show it.
    func updateDrawnHighlight(_ highlight: DCHighlight) async {
        _ = try? await evaluateJavaScriptAsync(JSMethod.setStyle(uuid: highlight.uuid,
                                                                 cssClass: highlight.displayStyle.cssClass).rawValue)
        _ = try? await evaluateJavaScriptAsync(JSMethod.setNote(uuid: highlight.uuid, hasNote: highlight.hasNote).rawValue)
    }

    /// Whether a highlight or a link is at `point` (this web view's coordinates): they handle the
    /// tap themselves.
    func hasHighlight(at point: CGPoint) async -> Bool {
        let result = try? await evaluateJavaScriptAsync(JSMethod.isHighlightAtPoint(point).rawValue)
        return result == "true"
    }

    // Injects all persisted highlights for the current chapter into the DOM.
    // Sorted descending by coords (legacy behavior) to avoid offset shifts.
    func loadHighlights() async {
        // Bookmarks mark a page, not a passage, so they aren't drawn in the text.
        let highlights = await viewModel.loadHighlights().filter { $0.type != .bookMark }
        let sorted = highlights.sorted { $0.coords > $1.coords }
        for h in sorted {
            await applyHighlight(h)
        }
    }

    // Injects a single highlight into the DOM without touching the store.
    func applyHighlight(_ highlight: DCHighlight) async {
        let js = JSMethod.highlightCoords(
            coords: highlight.coords,
            cssClass: highlight.displayStyle.cssClass,
            uuid: highlight.uuid,
            text: highlight.text
        ).rawValue
        _ = try? await self.evaluateJavaScriptAsync(js)
        // If it was already drawn, this brings its color and note marker up to date.
        await updateDrawnHighlight(highlight)
    }
}

extension DCHighlight {
    /// Whether the margin-style note marker is drawn: the note has text.
    var hasNote: Bool {
        !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Highlight styles

extension DCHighlightStyle {
    /// Class in Style.css that draws the style.
    var cssClass: String { "highlight-\(rawValue)" }

    var menuTitle: String {
        switch self {
        case .yellow: "Yellow"
        case .green: "Green"
        case .blue: "Blue"
        case .pink: "Pink"
        case .purple: "Purple"
        case .underline: "Underline"
        }
    }

    /// Swatch color, matching Style.css. `nil` for the underline.
    var swatchColor: UIColor? {
        switch self {
        case .yellow: UIColor(red: 1, green: 235 / 255, blue: 107 / 255, alpha: 1)
        case .green: UIColor(red: 192 / 255, green: 237 / 255, blue: 114 / 255, alpha: 1)
        case .blue: UIColor(red: 173 / 255, green: 216 / 255, blue: 1, alpha: 1)
        case .pink: UIColor(red: 1, green: 176 / 255, blue: 202 / 255, alpha: 1)
        case .purple: UIColor(red: 214 / 255, green: 184 / 255, blue: 245 / 255, alpha: 1)
        case .underline: nil
        }
    }

    /// A filled color circle, or the underline glyph.
    var menuImage: UIImage? {
        guard let swatchColor else { return UIImage(systemName: "underline") }
        return UIImage(systemName: "circle.fill")?.withTintColor(swatchColor, renderingMode: .alwaysOriginal)
    }
}
