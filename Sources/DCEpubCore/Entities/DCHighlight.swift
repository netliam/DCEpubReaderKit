//
//  DCHighlight.swift
//  DCEpubReaderKit
//
//  Created by Josep Cerdá Penadés on 04/05/26.
//

import Foundation

/// How a highlight is drawn: one of the Books highlight colors, or an underline.
public enum DCHighlightStyle: String, Codable, Sendable, CaseIterable {
    case yellow
    case green
    case blue
    case pink
    case purple
    case underline
}

public struct DCHighlight: Codable, Sendable, Equatable {

    public enum MarkType: String, Codable, Sendable {
        case highlight = "H"
        case note = "N"
        case bookMark = "B"
    }

    public let uuid: String
    public let bookId: String
    public let chapterId: String
    public let spineIndex: Int
    public let type: MarkType
    public let text: String
    public let coords: String
    public var note: String
    public var chapterTitle: String
    /// Color or underline. `nil` for highlights saved before styles existed; see `displayStyle`.
    public var style: DCHighlightStyle?
    public let dateCreated: Double
    public var dateUpdated: Double

    public init(
        uuid: String,
        bookId: String,
        chapterId: String,
        spineIndex: Int,
        type: MarkType,
        text: String,
        coords: String,
        note: String = "",
        chapterTitle: String = "",
        style: DCHighlightStyle? = nil,
        dateCreated: Double = Date().timeIntervalSince1970,
        dateUpdated: Double = Date().timeIntervalSince1970
    ) {
        self.uuid = uuid
        self.bookId = bookId
        self.chapterId = chapterId
        self.spineIndex = spineIndex
        self.type = type
        self.text = text
        self.coords = coords
        self.note = note
        self.chapterTitle = chapterTitle
        self.style = style
        self.dateCreated = dateCreated
        self.dateUpdated = dateUpdated
    }

    /// The style to draw: the saved one, or yellow for highlights and underline for notes.
    public var displayStyle: DCHighlightStyle {
        style ?? (type == .note ? .underline : .yellow)
    }
}
