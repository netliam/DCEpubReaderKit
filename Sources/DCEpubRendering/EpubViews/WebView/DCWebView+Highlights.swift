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
        case highlight(type: HighlightType)
        case clearSelection
        case highlightCoords(coords: String, cssClass: String, uuid: String, text: String)
        case removeHighlightById(uuid: String)

        var rawValue: String {
            switch self {
            case .rectsForSelection:
                return "rectsForSelection()"
            case .getCoordsFromSelection:
                return "getCoordsFromSelection()"
            case .getSelectionString:
                return "window.getSelection().toString()"
            case .highlight(type: let type):
                return "highlightString('highlight-\(type.rawValue)')"
            case .clearSelection:
                return "window.getSelection().removeAllRanges()"
            case let .highlightCoords(coords, cssClass, uuid, text):
                return "highlightCoords(\(jsLiteral(coords)),\(jsLiteral(cssClass)),\(jsLiteral(uuid)),\(jsLiteral(text)))"
            case let .removeHighlightById(uuid):
                return "removeHighlightById(\(jsLiteral(uuid)))"
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

    private enum HighlightType: String {
        case yellow
        case underline
    }

    func shoMenuInteraction() async {
        guard let selected = await getSelectedText()?.trimmingCharacters(in: .whitespacesAndNewlines),
              selected.isEmpty == false,
              let rectsString = await getRectsFromSelection(),
              let rectsData = rectsString.data(using: .utf8),
              let jsonArray = try? JSONSerialization.jsonObject(with: rectsData) as? [[String: Any]],
              let first = jsonArray.first,
              let xValue = first["x"] as? CGFloat,
              let yValue = first["y"] as? CGFloat else { return }
        let rectInView = CGRect(x: xValue, y: yValue, width: 0, height: 0)
        self.presentSelectionMenu(at: rectInView, text: selected)
    }

    private func presentSelectionMenu(at rect: CGRect, text: String) {
        removeMenuItems()
        becomeFirstResponder()
        let menu = UIMenuController.shared
        menu.menuItems = [
            UIMenuItem(title: "Highlight", action: #selector(applyHightLight)),
            UIMenuItem(title: "Note", action: #selector(applyUnderline))
        ]
        menu.showMenu(from: self, rect: rect)
    }

    @objc func removeMenuItems() {
        let menu = UIMenuController.shared
        menu.menuItems?.removeAll()
        menu.hideMenu()
        menu.menuItems = nil
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

    private func highlightSelection(type: HighlightType) async -> String? {
        try? await self.evaluateJavaScriptAsync(JSMethod.highlight(type: type).rawValue) as? String
    }

    private func clearJSSelection() async {
        _ = try? await self.evaluateJavaScriptAsync(JSMethod.clearSelection.rawValue)
    }

    @objc func applyHightLight() {
        selectionMenuTask?.cancel()
        Task { @MainActor in
            guard let coords = await getCoordsFromSelection(),
                  let selectedText = await getSelectedText(),
                  !selectedText.contains("\n"),
                  let uuid = await highlightSelection(type: .yellow) else {
                return
            }
            let highlight = DCHighlight(
                uuid: uuid,
                bookId: viewModel.currentBookId,
                chapterId: viewModel.currentChapterId,
                spineIndex: viewModel.currentSpineIndex,
                type: .highlight,
                text: selectedText,
                coords: coords
            )
            await viewModel.saveHighlight(highlight)
            await self.clearJSSelection()
            self.removeMenuItems()
        }
    }

    @objc func applyUnderline() {
        selectionMenuTask?.cancel()
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let coords = await self.getCoordsFromSelection(),
                  let selectedText = await self.getSelectedText(),
                  !selectedText.contains("\n"),
                  let uuid = await self.highlightSelection(type: .underline) else {
                return
            }
            let highlight = DCHighlight(
                uuid: uuid,
                bookId: viewModel.currentBookId,
                chapterId: viewModel.currentChapterId,
                spineIndex: viewModel.currentSpineIndex,
                type: .note,
                text: selectedText,
                coords: coords
            )
            await viewModel.saveHighlight(highlight)
            await self.clearJSSelection()
            self.removeMenuItems()
            self.viewModel.showNoote(highlight: highlight)
        }
    }

    // Removes the highlight span from the DOM without touching the store.
    func removeHighlight(uuid: String) async {
        _ = try? await self.evaluateJavaScriptAsync(JSMethod.removeHighlightById(uuid: uuid).rawValue)
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
        let cssClass = highlight.type == .highlight ? "highlight-yellow" : "highlight-underline"
        let js = JSMethod.highlightCoords(
            coords: highlight.coords,
            cssClass: cssClass,
            uuid: highlight.uuid,
            text: highlight.text
        ).rawValue
        _ = try? await self.evaluateJavaScriptAsync(js)
    }
}
