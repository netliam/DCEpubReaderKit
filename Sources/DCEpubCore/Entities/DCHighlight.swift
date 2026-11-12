//
//  DCHighlight.swift
//  DCEpubReaderKit
//
//  Created by Josep Cerdá Penadés on 04/05/26.
//

import Foundation

/// How an annotation is drawn. Its color is separate (`DCHighlight.color`).
public enum DCAnnotationStyle: String, Codable, Sendable, CaseIterable {
    /// A filled background.
    case highlight
    /// A solid line under the text.
    case underline
    /// A wavy line under the text.
    case squiggly
    /// A line through the text.
    case strikethrough
}

/// The kit's own colors (Books'), and the underline. Saved highlights carry a style and a hex
/// color instead (`DCHighlight.annotationStyle`, `.color`); these remain as defaults, and to read
/// highlights saved by older versions, which stored only one of these names.
public enum DCHighlightStyle: String, Codable, Sendable, CaseIterable {
    case yellow
    case green
    case blue
    case pink
    case purple
    case underline

    public var annotationStyle: DCAnnotationStyle {
        self == .underline ? .underline : .highlight
    }

    /// `#RRGGBB`.
    public var color: String {
        switch self {
        case .yellow: "#FFEB6B"
        case .green: "#C0ED72"
        case .blue: "#ADD8FF"
        case .pink: "#FFB0CA"
        case .purple: "#D6B8F5"
        case .underline: "#F02814"
        }
    }
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
    /// Filled, underline, squiggly or strikethrough.
    public var annotationStyle: DCAnnotationStyle
    /// `#RRGGBB`, any color: kept as given, so colors made elsewhere survive a round trip.
    public var color: String
    public let dateCreated: Double
    public var dateUpdated: Double

    /// - Parameters:
    ///   - style: One of the kit's colors, used for `annotationStyle` and `color` when those
    ///     aren't given.
    ///   - annotationStyle: Defaults to `style`'s, else highlight (underline for notes).
    ///   - color: Defaults to `style`'s, else yellow (red for lines).
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
        annotationStyle: DCAnnotationStyle? = nil,
        color: String? = nil,
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
        let resolvedStyle = annotationStyle ?? style?.annotationStyle ?? (type == .note ? .underline : .highlight)
        self.annotationStyle = resolvedStyle
        self.color = color ?? style?.color ?? Self.defaultColor(for: resolvedStyle)
        self.dateCreated = dateCreated
        self.dateUpdated = dateUpdated
    }

    /// Yellow for highlights, the underline's red for lines.
    public static func defaultColor(for style: DCAnnotationStyle) -> String {
        style == .highlight ? DCHighlightStyle.yellow.color : DCHighlightStyle.underline.color
    }

    private enum CodingKeys: String, CodingKey {
        case uuid, bookId, chapterId, spineIndex, type, text, coords, note, chapterTitle
        case annotationStyle, color, dateCreated, dateUpdated
        /// Older versions: one of `DCHighlightStyle`'s names.
        case style
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(uuid: try c.decode(String.self, forKey: .uuid),
                  bookId: try c.decode(String.self, forKey: .bookId),
                  chapterId: try c.decode(String.self, forKey: .chapterId),
                  spineIndex: try c.decode(Int.self, forKey: .spineIndex),
                  type: try c.decode(MarkType.self, forKey: .type),
                  text: try c.decode(String.self, forKey: .text),
                  coords: try c.decode(String.self, forKey: .coords),
                  note: try c.decodeIfPresent(String.self, forKey: .note) ?? "",
                  chapterTitle: try c.decodeIfPresent(String.self, forKey: .chapterTitle) ?? "",
                  style: try? c.decodeIfPresent(DCHighlightStyle.self, forKey: .style),
                  annotationStyle: try? c.decodeIfPresent(DCAnnotationStyle.self, forKey: .annotationStyle),
                  color: try c.decodeIfPresent(String.self, forKey: .color),
                  dateCreated: try c.decode(Double.self, forKey: .dateCreated),
                  dateUpdated: try c.decode(Double.self, forKey: .dateUpdated))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(uuid, forKey: .uuid)
        try c.encode(bookId, forKey: .bookId)
        try c.encode(chapterId, forKey: .chapterId)
        try c.encode(spineIndex, forKey: .spineIndex)
        try c.encode(type, forKey: .type)
        try c.encode(text, forKey: .text)
        try c.encode(coords, forKey: .coords)
        try c.encode(note, forKey: .note)
        try c.encode(chapterTitle, forKey: .chapterTitle)
        try c.encode(annotationStyle, forKey: .annotationStyle)
        try c.encode(color, forKey: .color)
        try c.encode(dateCreated, forKey: .dateCreated)
        try c.encode(dateUpdated, forKey: .dateUpdated)
    }
}
