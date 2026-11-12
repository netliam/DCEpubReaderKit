//
//  DCHighlightMenuConfiguration.swift
//  DCEpubReaderKit
//
//  Created by Liam Smith-Gales on 12/11/26.
//

import Foundation
import DCEpubCore

/// What the menus for selected text and for a tapped highlight offer: the styles and colors to
/// annotate with, and the actions, in order. The default is the Books-style menu.
///
/// ```swift
/// configuration.highlightMenu.palettes = [
///     DCHighlightPalette(style: .highlight, colors: [("Yellow", "#FACC15"), ("Green", "#4ADE80")]),
///     DCHighlightPalette(style: .squiggly, colors: [("Crimson", "#DC143C")])
/// ]
/// configuration.highlightMenu.selectionActions = [.note, .search, .copy, .custom(sendToNotebook)]
/// ```
public struct DCHighlightMenuConfiguration {

    /// The styles offered, in order, each with its colors. The menu shows the colors of the current
    /// style (the highlight's, or the last one used), and the other styles in a Style submenu. A
    /// style with a single color is shown as its own button in the row instead (like the default
    /// underline). Empty: text can't be annotated from the menu.
    public var palettes: [DCHighlightPalette] = DCHighlightPalette.books

    /// The actions for selected text, in order. `.delete` doesn't apply to a selection and is skipped.
    public var selectionActions: [DCHighlightAction] = [.note, .lookUp, .search, .copy, .share]

    /// The actions for a tapped highlight, in order.
    public var highlightActions: [DCHighlightAction] = [.note, .copy, .share, .delete]

    public init() {}

    /// The palette for `style`, if offered.
    func palette(for style: DCAnnotationStyle) -> DCHighlightPalette? {
        palettes.first { $0.style == style && !$0.colors.isEmpty }
    }

    /// The accessible name of a color, from the palettes; `nil` for colors made elsewhere.
    public func colorName(_ color: String, style: DCAnnotationStyle) -> String? {
        palette(for: style)?.colors.first { $0.matches(color) }?.name
    }
}

/// The colors offered for one annotation style.
public struct DCHighlightPalette: Sendable {
    public let style: DCAnnotationStyle
    public let colors: [DCHighlightColor]

    public init(style: DCAnnotationStyle, colors: [DCHighlightColor]) {
        self.style = style
        self.colors = colors
    }

    /// Colors as (accessible name, `#RRGGBB`).
    public init(style: DCAnnotationStyle, colors: [(String, String)]) {
        self.init(style: style, colors: colors.map { DCHighlightColor(name: $0.0, hex: $0.1) })
    }

    /// The kit's default: Books' five highlight colors and a red underline.
    public static let books: [DCHighlightPalette] = [
        DCHighlightPalette(style: .highlight, colors: [DCHighlightStyle.yellow, .green, .blue, .pink, .purple].map {
            DCHighlightColor(name: $0.menuTitle, hex: $0.color)
        }),
        DCHighlightPalette(style: .underline, colors: [DCHighlightColor(name: L("Underline"),
                                                                        hex: DCHighlightStyle.underline.color)])
    ]
}

public struct DCHighlightColor: Equatable, Sendable {
    /// Read by VoiceOver and shown in the Style submenu.
    public let name: String
    /// `#RRGGBB`.
    public let hex: String

    public init(name: String, hex: String) {
        self.name = name
        self.hex = hex
    }

    /// Hex colors compare without case.
    func matches(_ color: String) -> Bool {
        hex.caseInsensitiveCompare(color) == .orderedSame
    }
}

/// An item in the selection or highlight menu.
public enum DCHighlightAction {
    /// Add Note (highlights in the current style and color, and opens the note), or Edit Note.
    case note
    case copy
    case share
    /// Searches the book for the text.
    case search
    /// Look Up / Define (and, for a selection, the system's Translate).
    case lookUp
    /// Deletes the tapped highlight and its note.
    case delete
    case custom(DCCustomHighlightAction)
}

/// A menu item the host app adds, e.g. "Send to Notebook" or "Translate".
public struct DCCustomHighlightAction {
    public let title: String
    /// An SF Symbol name.
    public let systemImage: String?
    public let handler: @MainActor (DCHighlightActionContext) -> Void

    public init(title: String, systemImage: String? = nil, handler: @escaping @MainActor (DCHighlightActionContext) -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.handler = handler
    }
}

/// What a custom action receives: the text and where it is.
public struct DCHighlightActionContext: Sendable {
    public let text: String
    public let spineIndex: Int
    /// The reader's coords for the text (`"a,b"`).
    public let coords: String
    /// The same range as an EPUB CFI, `nil` if it couldn't be converted.
    public let cfi: String?
    /// The tapped highlight; `nil` for selected text.
    public let highlight: DCHighlight?
}
