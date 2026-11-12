//
//  DCWebView+Links.swift
//  DCEpubReaderKit
//
//  Created by Liam Smith-Gales on 11/11/26.
//

import SwiftUI
import DCEpubCore

/// Link taps posted by EpubUtil.js (`linkTapped`): footnotes open in a popover over the page;
/// other links go to the reader, which jumps there (with Back) or opens the browser.
extension DCWebView {

    static let linkTappedHandler = "linkTapped"

    func handleLinkTapped(_ body: Any) {
        guard let dict = body as? [String: Any], let kind = dict["kind"] as? String else { return }
        let rect = (dict["rect"] as? String).map { NSCoder.cgRect(for: $0) } ?? .zero
        switch kind {
        case "footnote":
            guard let text = dict["text"] as? String, !text.isEmpty else { return }
            showFootnote(text, at: rect)
        case "noteref":
            guard let url = (dict["url"] as? String).flatMap(URL.init(string:)) else { return }
            if let text = DCFootnoteText.text(forLinkTo: url) {
                showFootnote(text, at: rect)
            } else {
                // Not a note after all, or unreadable: go there instead.
                viewModel.openLink(url)
            }
        case "image":
            guard let url = (dict["url"] as? String).flatMap(URL.init(string:)), url.isFileURL,
                  let image = UIImage(contentsOfFile: url.path) else { return }
            showImage(image, description: dict["alt"] as? String ?? "")
        case "link":
            guard let url = (dict["url"] as? String).flatMap(URL.init(string:)) else { return }
            viewModel.openLink(url)
        default:
            break
        }
    }

    /// Opens a picture from the book full screen, to zoom into.
    func showImage(_ image: UIImage, description: String) {
        guard let presenter = parentViewController else { return }
        presenter.present(DCImageViewerController(image: image, description: description), animated: true)
    }

    /// Shows a note in a popover pointing at its reference, like Books.
    func showFootnote(_ text: String, at rect: CGRect) {
        guard let presenter = parentViewController else { return }
        let appearance = readerAppearance
        let content = DCFootnoteView(text: text, appearance: appearance)
        let controller = UIHostingController(rootView: content)
        controller.view.backgroundColor = appearance?.uiBackgroundColor ?? .systemBackground
        controller.modalPresentationStyle = .popover
        let width = min(bounds.width - 32, 360)
        let fitting = controller.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
        controller.preferredContentSize = CGSize(width: width, height: min(fitting.height, bounds.height * 0.6))
        if let popover = controller.popoverPresentationController {
            popover.sourceView = self
            popover.sourceRect = rect.isEmpty ? CGRect(x: bounds.midX, y: bounds.midY, width: 1, height: 1) : rect
            popover.permittedArrowDirections = [.up, .down]
            popover.delegate = DCFootnotePopoverDelegate.shared
        }
        presenter.present(controller, animated: true)
    }
}

/// A popover on iPhone too (not a sheet).
private final class DCFootnotePopoverDelegate: NSObject, UIPopoverPresentationControllerDelegate {
    static let shared = DCFootnotePopoverDelegate()

    func adaptivePresentationStyle(for controller: UIPresentationController,
                                   traitCollection: UITraitCollection) -> UIModalPresentationStyle {
        .none
    }
}

/// The text of a footnote, scrolling when it's long.
struct DCFootnoteView: View {
    let text: String
    let appearance: DCReaderAppearance?

    var body: some View {
        ScrollView {
            Text(text)
                .font(.body)
                .foregroundStyle(appearance?.textColor ?? .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .padding(16)
        }
        .accessibilityLabel("Footnote")
        .accessibilityValue(text)
    }
}
