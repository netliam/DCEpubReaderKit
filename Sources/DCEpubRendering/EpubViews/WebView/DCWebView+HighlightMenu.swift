//
//  DCWebView+HighlightMenu.swift
//  DCEpubReaderKit
//
//  Created by Liam Smith-Gales on 11/11/26.
//

import UIKit
import DCEpubCore

extension Notification.Name {
    /// Posted when a highlight is saved, so pages showing it redraw its color and note marker.
    /// `userInfo[DCHighlight.notificationKey]` is the saved `DCHighlight`.
    static let dcHighlightDidChange = Notification.Name("DCHighlightDidChange")
}

extension DCHighlight {
    static let notificationKey = "highlight"
}

/// The Books-style menu for a tapped highlight: its colors (the current one checked), Add or Edit
/// Note, Copy, Share and Delete. Shown over the highlight with a `UIEditMenuInteraction`.
@MainActor
final class DCHighlightMenu: NSObject, @preconcurrency UIEditMenuInteractionDelegate {

    let highlight: DCHighlight
    let rect: CGRect
    private let elements: [UIMenuElement]
    private(set) lazy var interaction = UIEditMenuInteraction(delegate: self)

    init(highlight: DCHighlight, rect: CGRect, elements: [UIMenuElement]) {
        self.highlight = highlight
        self.rect = rect
        self.elements = elements
    }

    func editMenuInteraction(_ interaction: UIEditMenuInteraction,
                             menuFor configuration: UIEditMenuConfiguration,
                             suggestedActions: [UIMenuElement]) -> UIMenu? {
        UIMenu(children: elements)
    }

    func editMenuInteraction(_ interaction: UIEditMenuInteraction,
                             targetRectFor configuration: UIEditMenuConfiguration) -> CGRect {
        rect
    }
}

extension DCWebView {

    /// Shows the menu for `highlight`, which was tapped at `rect` (this view's coordinates).
    func showHighlightMenu(for highlight: DCHighlight, at rect: CGRect) {
        if let old = highlightMenu {
            old.interaction.dismissMenu()
            removeInteraction(old.interaction)
        }
        let menu = DCHighlightMenu(highlight: highlight, rect: rect, elements: highlightMenuElements(for: highlight))
        highlightMenu = menu
        addInteraction(menu.interaction)
        let configuration = UIEditMenuConfiguration(identifier: nil, sourcePoint: CGPoint(x: rect.midX, y: rect.minY))
        menu.interaction.presentEditMenu(with: configuration)
    }

    func highlightMenuElements(for highlight: DCHighlight) -> [UIMenuElement] {
        let current = highlight.displayStyle
        let styles = DCHighlightStyle.allCases.map { style in
            let action = UIAction(title: "", image: style == current ? style.selectedMenuImage : style.menuImage) { [weak self] _ in
                self?.restyle(highlight, as: style)
            }
            // No `.on` state: the menu would draw its own tint-colored check over the swatch.
            action.accessibilityLabel = style == current ? "\(style.menuTitle), current" : style.menuTitle
            return action
        }
        let colors: UIMenu
        if #available(iOS 17.0, *) {
            colors = UIMenu(options: [.displayInline, .displayAsPalette], children: styles)
        } else {
            colors = UIMenu(options: .displayInline, children: styles)
        }
        colors.preferredElementSize = .small

        let note = UIAction(title: highlight.hasNote ? "Edit Note" : "Add Note",
                            image: UIImage(systemName: highlight.hasNote ? "note.text" : "note.text.badge.plus")) { [weak self] _ in
            self?.viewModel.showNoote(highlight: highlight)
        }
        let copy = UIAction(title: "Copy", image: UIImage(systemName: "doc.on.doc")) { _ in
            UIPasteboard.general.string = highlight.text
        }
        let share = UIAction(title: "Share…", image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in
            self?.share(highlight)
        }
        let delete = UIAction(title: highlight.hasNote ? "Delete Highlight and Note" : "Delete Highlight",
                              image: UIImage(systemName: "trash"),
                              attributes: .destructive) { [weak self] _ in
            self?.delete(highlight)
        }

        return [
            colors,
            UIMenu(options: .displayInline, children: [note]),
            UIMenu(options: .displayInline, children: [copy, share]),
            UIMenu(options: .displayInline, children: [delete])
        ]
    }

    private func restyle(_ highlight: DCHighlight, as style: DCHighlightStyle) {
        guard style != highlight.displayStyle else { return }
        var updated = highlight
        updated.style = style
        updated.dateUpdated = Date().timeIntervalSince1970
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.updateDrawnHighlight(updated)
            // Saving tells the other pages (see `.dcHighlightDidChange`).
            await self.viewModel.saveHighlight(updated)
        }
    }

    private func delete(_ highlight: DCHighlight) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.viewModel.deleteHighlight(uuid: highlight.uuid)
            await self.removeHighlight(uuid: highlight.uuid)
        }
    }

    private func share(_ highlight: DCHighlight) {
        guard let presenter = parentViewController else { return }
        let activity = UIActivityViewController(activityItems: [highlight.text], applicationActivities: nil)
        activity.popoverPresentationController?.sourceView = self
        activity.popoverPresentationController?.sourceRect = highlightMenu?.rect
            ?? CGRect(x: bounds.midX, y: bounds.midY, width: 0, height: 0)
        presenter.present(activity, animated: true)
    }
}

extension DCWebView {
    /// Whether a highlight or a link is under `point` (in `view`'s coordinates), in whichever
    /// reader web view is there, so the tap isn't also a page tap.
    static func hasHighlight(at point: CGPoint, in view: UIView) async -> Bool {
        var hit = view.hitTest(point, with: nil)
        while let current = hit, !(current is DCWebView) {
            hit = current.superview
        }
        guard let webView = hit as? DCWebView else { return false }
        return await webView.hasHighlight(at: view.convert(point, to: webView))
    }
}

extension DCHighlightStyle {
    /// The palette image for the highlight's current style: a checked circle, or a filled underline glyph.
    var selectedMenuImage: UIImage? {
        // The underline's swatch is a glyph; checked, it becomes a check in the underline's red.
        let color = swatchColor ?? UIColor(red: 240 / 255, green: 40 / 255, blue: 20 / 255, alpha: 1)
        // Tinted like the other swatches (the menu ignores palette colors): the check is a cut-out.
        return UIImage(systemName: "checkmark.circle.fill")?.withTintColor(color, renderingMode: .alwaysOriginal)
    }
}
