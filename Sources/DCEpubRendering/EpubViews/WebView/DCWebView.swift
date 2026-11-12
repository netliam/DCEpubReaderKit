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
        static let highlightTapped  = "highlightTapped"
    }

    var viewModel: DCWebViewModelProtocol!
    /// Line focus effect, present while the setting is on (see `setLineFocus(enabled:appearance:style:)`).
    private(set) var lineFocus: DCLineFocusController?
    /// The menu shown when a highlight is tapped (see DCWebView+HighlightMenu.swift).
    var highlightMenu: DCHighlightMenu?

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
        configuration.userContentController.removeScriptMessageHandler(forName: Constants.highlightTapped)
    }

    private func setupBindings() {
        // Any page may show a highlight edited elsewhere (the note editor, another page of the chapter).
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(highlightDidChange(_:)),
                                               name: .dcHighlightDidChange,
                                               object: nil)
    }

    @objc private func highlightDidChange(_ notification: Notification) {
        guard let highlight = notification.userInfo?[DCHighlight.notificationKey] as? DCHighlight else { return }
        Task { @MainActor [weak self] in
            await self?.updateDrawnHighlight(highlight)
        }
    }

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
        configuration.userContentController.add(handler, name: Constants.highlightTapped)
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        switch message.name {
        case Constants.highlightTapped:
            handleHighlightTapped(message.body)
        default:
            break
        }
    }

    private func handleHighlightTapped(_ body: Any) {
        guard let dict = body as? [String: Any],
              let uuid = dict["uuid"] as? String,
              !uuid.isEmpty else { return }
        // The rect comes from getBoundingClientRect, in viewport points: this view's coordinates.
        let rect = (dict["rect"] as? String).map { NSCoder.cgRect(for: $0) } ?? .zero

        Task { @MainActor [weak self] in
            guard let self else { return }
            let highlights = await self.viewModel.loadHighlights()
            guard let highlight = highlights.first(where: { $0.uuid == uuid }) else { return }
            self.showHighlightMenu(for: highlight, at: rect)
        }
    }

    // MARK: - Edit menu

    /// Swaps the system edit menu for the Books-style selection menu (see `selectionMenuElements`).
    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        guard builder.system == .context else { return }
        let lookUp = Self.lookUpCommands(in: builder.menu(for: .lookup))
        let elements = selectionMenuElements(systemLookUp: lookUp)
        builder.replaceChildren(ofMenu: .root) { _ in elements }
    }

    override var canBecomeFirstResponder: Bool {
        return true
    }
}

// MARK: - Theme

extension WKWebView {
    /// Switches a loaded chapter to another theme by replacing its injected theme style.
    /// Only for themes with the same font weight: colors don't change the layout, weight does.
    func applyTheme(_ appearance: DCReaderAppearance) async {
        let css = DCChapterHTMLBuilder.themeCSS(for: appearance)
        guard let data = try? JSONSerialization.data(withJSONObject: [css]),
              let array = String(data: data, encoding: .utf8) else { return }
        let id = DCChapterHTMLBuilder.themeStyleId
        _ = try? await evaluateJavaScriptAsync("""
        (function () {
            var style = document.getElementById('\(id)');
            if (!style) { style = document.createElement('style'); style.id = '\(id)'; document.head.appendChild(style); }
            style.textContent = \(array)[0];
            return 'ok';
        })()
        """)
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

extension DCWebView {
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
