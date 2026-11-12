//
//  DCMarksViewModel.swift
//  DCEpubReaderKit
//
//  Created by Josep Cerdá Penadés on 07/05/2026.
//

import Foundation
import DCEpubCore

@MainActor
final class DCMarksViewModel: ObservableObject {

    /// Which highlights the list shows, like Books' Highlights filter.
    enum Filter: Hashable {
        case all
        /// Highlights with a note.
        case notes
        case style(DCHighlightStyle)
    }

    enum Sort: Hashable, CaseIterable {
        /// In reading order.
        case position
        /// Most recently changed first.
        case recent

        var title: String {
            switch self {
            case .position: "Page"
            case .recent: "Date"
            }
        }
    }

    @Published var filter: Filter = .all
    @Published var sort: Sort = .position
    @Published private(set) var highlights: [DCHighlight] = []
    /// Mark types this list shows (highlights and notes, or bookmarks).
    let types: [DCHighlight.MarkType]

    private let highlightsProvider: () async -> [DCHighlight]
    private let onSelect: (DCHighlight) -> Void

    /// Whole-book page of a mark, once the book has been counted.
    let pageNumber: (DCHighlight) -> Int?

    init(types: [DCHighlight.MarkType] = [.highlight, .note, .bookMark],
         highlightsProvider: @escaping () async -> [DCHighlight],
         pageNumber: @escaping (DCHighlight) -> Int? = { _ in nil },
         onSelect: @escaping (DCHighlight) -> Void) {
        self.pageNumber = pageNumber
        self.types = types
        self.highlightsProvider = highlightsProvider
        self.onSelect = onSelect
    }

    /// The kind of mark the list is about, for its icon and empty message.
    var primaryType: DCHighlight.MarkType {
        types.first ?? .highlight
    }

    /// Color and note filters apply to highlights, not bookmarks.
    var showsFilters: Bool {
        types.contains(.highlight) && !marks.isEmpty
    }

    /// The filters worth offering: All, Notes if any mark has one, and each color in use.
    var availableFilters: [Filter] {
        var filters: [Filter] = [.all]
        if marks.contains(where: \.hasNote) {
            filters.append(.notes)
        }
        let styles = Set(marks.map(\.displayStyle))
        filters += DCHighlightStyle.allCases.filter(styles.contains).map(Filter.style)
        return filters
    }

    var filteredHighlights: [DCHighlight] {
        let shown = marks.filter { mark in
            switch filter {
            case .all: true
            case .notes: mark.hasNote
            case .style(let style): mark.displayStyle == style
            }
        }
        switch sort {
        case .position:
            return shown.sorted(by: isBefore)
        case .recent:
            return shown.sorted { $0.dateUpdated > $1.dateUpdated }
        }
    }

    /// Reading order: chapter, then whole-book page when both are known, then position in the chapter.
    private func isBefore(_ a: DCHighlight, _ b: DCHighlight) -> Bool {
        if a.spineIndex != b.spineIndex { return a.spineIndex < b.spineIndex }
        if let pageA = pageNumber(a), let pageB = pageNumber(b), pageA != pageB { return pageA < pageB }
        return Self.coordsKey(a.coords).lexicographicallyPrecedes(Self.coordsKey(b.coords))
    }

    /// A mark's start as numbers ("0000001>0000003>0000012,…" → [1, 3, 12]). Compared as strings,
    /// paths of different depths sort out of order.
    nonisolated static func coordsKey(_ coords: String) -> [Int] {
        let start = coords.split(separator: ",").first ?? ""
        return start.split(whereSeparator: { $0 == ">" || $0 == "|" }).compactMap { Int($0) }
    }

    /// Every mark of this list's types, before filtering.
    private var marks: [DCHighlight] {
        highlights.filter { types.contains($0.type) }
    }

    func loadIfNeeded() async {
        guard highlights.isEmpty else { return }
        highlights = await highlightsProvider()
        // A filter for a color that's no longer used would show nothing.
        if !availableFilters.contains(filter) {
            filter = .all
        }
    }

    func didSelect(_ highlight: DCHighlight) {
        onSelect(highlight)
    }
}
