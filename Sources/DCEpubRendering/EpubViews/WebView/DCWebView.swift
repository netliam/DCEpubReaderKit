//
//  DCWebView.swift
//  DCEpubReaderKit
//
//  Created by Josep Cerdá Penadés on 23/10/25.
//

import WebKit
import DCEpubCore

final class DCWebView: WKWebView, WKScriptMessageHandler, UIGestureRecognizerDelegate {

    private enum Constants {
        static let selectionChanged = "selectionChanged"
        static let highlightTapped  = "highlightTapped"
    }

    var viewModel: DCWebViewModelProtocol!
    var selectionMenuTask: Task<Void, Never>?
    /// Line focus effect, present while the setting is on (see `setLineFocus(enabled:appearance:style:)`).
    private(set) var lineFocus: DCLineFocusController?

    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        setupBindings()
        injectMessageHandlers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupBindings()
        injectMessageHandlers()
    }

    deinit {
        teardown()
    }

    private func teardown() {
        selectionMenuTask?.cancel()
        configuration.userContentController.removeScriptMessageHandler(forName: Constants.selectionChanged)
        configuration.userContentController.removeScriptMessageHandler(forName: Constants.highlightTapped)
    }

    private func setupBindings() {}

    // MARK: - UIGestureRecognizerDelegate

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    private func injectMessageHandlers() {
        teardown()
        // WKUserContentController retains its handlers strongly, so registering `self` directly
        // would keep every web view alive. The weak proxy lets `deinit` (and `teardown`) run.
        let handler = DCWeakScriptMessageHandler(target: self)
        configuration.userContentController.add(handler, name: Constants.selectionChanged)
        configuration.userContentController.add(handler, name: Constants.highlightTapped)
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        switch message.name {
        case Constants.selectionChanged:
            handleSelectionChanged(message.body)
        case Constants.highlightTapped:
            handleHighlightTapped(message.body)
        default:
            break
        }
    }

    private func handleSelectionChanged(_ body: Any) {
        selectionMenuTask?.cancel()
        let selectedText = (body as? [String: Any])?["text"] as? String
        guard let selectedText,
              selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            removeMenuItems()
            return
        }
        selectionMenuTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard Task.isCancelled == false else { return }
            await self?.shoMenuInteraction()
        }
    }

    private func handleHighlightTapped(_ body: Any) {
        guard let dict = body as? [String: Any],
              let uuid = dict["uuid"] as? String,
              !uuid.isEmpty else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let highlights = await self.viewModel.loadHighlights()
            guard let highlight = highlights.first(where: { $0.uuid == uuid }) else { return }

            if highlight.type == .note {
                self.showNoteOptionsAlert(highlight: highlight)
            } else {
                self.showDeleteHighlightAlert(uuid: uuid)
            }
        }
    }

    private func showNoteOptionsAlert(highlight: DCHighlight) {
        guard let vc = parentViewController else { return }
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Edit Note", style: .default) { [weak self] _ in
            self?.viewModel.showNoote(highlight: highlight)
        })
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.viewModel.deleteHighlight(uuid: highlight.uuid)
                await self.removeHighlight(uuid: highlight.uuid)
            }
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        vc.present(alert, animated: true)
    }

    private func showDeleteHighlightAlert(uuid: String) {
        guard let vc = parentViewController else { return }
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Delete Highlight", style: .destructive) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.viewModel.deleteHighlight(uuid: uuid)
                await self.removeHighlight(uuid: uuid)
            }
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        vc.present(alert, animated: true)
    }

    // MARK: - UIMenuController

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(applyHightLight) ||
            action == #selector(applyUnderline) {
            return true
        } else {
            return false
        }
    }

    override var canBecomeFirstResponder: Bool {
        return true
    }
}

// MARK: - Selection

extension DCWebView {
    /// The selected text, trimmed, or `nil` when nothing is selected.
    func selectedText() async -> String? {
        let text = try? await evaluateJavaScriptAsync("window.getSelection().toString()")
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Line focus

extension DCWebView {
    /// Turns line focus on or off. Call `lineFocus?.refresh(anchor:)` once the page is positioned.
    /// - Parameter textTrailingInset: Blank space at the right edge of the web view that isn't part of
    ///   the text column (the paged reader's column gap), so the guide outline hugs the text.
    func setLineFocus(enabled: Bool,
                      appearance: DCReaderAppearance,
                      style: DCLineFocusStyle,
                      textTrailingInset: CGFloat = 0) {
        lineFocus?.detach()
        lineFocus = enabled
            ? DCLineFocusController(webView: self, appearance: appearance, style: style, textTrailingInset: textTrailingInset)
            : nil
    }
}

// MARK: - Weak script message handler

@MainActor
private final class DCWeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?

    init(target: WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

// MARK: - Responder chain helper

private extension DCWebView {
    var parentViewController: UIViewController? {
        var responder: UIResponder? = self
        while let r = responder {
            if let vc = r as? UIViewController { return vc }
            responder = r.next
        }
        return nil
    }
}

// MARK: - WKWebView evaluateJavaScript with async/await

extension WKWebView {
    /// Waits until fonts are loaded and layout has settled (see `waitForLayout` in EpubUtil.js).
    /// Replaces fixed delays: usually a couple of frames; off screen, fonts plus `frameTimeout`.
    @MainActor
    func waitForLayout(frameTimeout: TimeInterval = 0.1, totalTimeout: TimeInterval = 2) async {
        let frameMilliseconds = Int(frameTimeout * 1000)
        let totalMilliseconds = Int(totalTimeout * 1000)
        _ = try? await callAsyncJavaScript("return await waitForLayout(\(frameMilliseconds), \(totalMilliseconds));",
                                           arguments: [:],
                                           in: nil,
                                           contentWorld: .page)
    }

    @MainActor
    func evaluateJavaScriptAsync(_ javaScript: String) async throws -> String? {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String?, Error>) in
            self.evaluateJavaScript(javaScript) { result, error in
                if let error = error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume(returning: result as? String)
                }
            }
        }
    }
}
