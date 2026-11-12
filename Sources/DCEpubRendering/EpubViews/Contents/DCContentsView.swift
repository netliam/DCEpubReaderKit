//
//  DCContentsView.swift
//  DCEpubReaderKit
//
//  Created by Liam Smith-Gales on 11/11/26.
//

import SwiftUI
import DCEpubCore

/// One table-of-contents entry, flattened with its nesting depth.
struct DCContentsEntry: Identifiable, Hashable {
    let id: Int
    let label: String
    let depth: Int
    /// Spine index the entry points into, when it resolves to a chapter of the book.
    let spineIndex: Int?
    /// The `#fragment` part of the entry's href, if any.
    let fragment: String?

    /// Flattens the TOC tree in reading order.
    static func entries(for book: DCEpubBook) -> [DCContentsEntry] {
        var entries: [DCContentsEntry] = []
        func visit(_ nodes: [DCTocNode], depth: Int) {
            for node in nodes {
                let fragment = node.href?.split(separator: "#", maxSplits: 1).dropFirst().first.map(String.init)
                entries.append(DCContentsEntry(id: entries.count,
                                               label: node.label,
                                               depth: depth,
                                               spineIndex: book.spineIndex(forTOCHref: node.href),
                                               fragment: fragment))
                visit(node.children, depth: depth + 1)
            }
        }
        visit(book.toc, depth: 0)
        return entries
    }
}

/// Contents, bookmarks and highlights in one sheet, like the Books "Contents" screen.
struct DCContentsView: View {

    enum Tab: Hashable {
        case contents
        case bookmarks
        case highlights
    }

    let entries: [DCContentsEntry]
    let currentSpineIndex: Int
    /// Whole-book page of an entry, once the book has been counted.
    let pageNumber: (DCContentsEntry) -> Int?
    /// Whole-book page of a bookmark or highlight, once the book has been counted.
    let markPageNumber: (DCHighlight) -> Int?
    /// "Title by Author", heading exported highlights.
    var bookByline: String = ""
    let highlightsProvider: () async -> [DCHighlight]
    let onSelectEntry: (DCContentsEntry) -> Void
    let onSelectMark: (DCHighlight) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab = .contents

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker(L("Show"), selection: $tab) {
                    Text(L("Contents")).tag(Tab.contents)
                    Text(L("Bookmarks")).tag(Tab.bookmarks)
                    Text(L("Highlights")).tag(Tab.highlights)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                switch tab {
                case .contents:
                    contentsList
                case .bookmarks:
                    DCMarksViewBuilder().build(types: [.bookMark],
                                               highlightsProvider: highlightsProvider,
                                               pageNumber: markPageNumber,
                                               onSelect: onSelectMark)
                case .highlights:
                    DCMarksViewBuilder().build(types: [.highlight, .note],
                                               highlightsProvider: highlightsProvider,
                                               pageNumber: markPageNumber,
                                               exportHeading: bookByline,
                                               onSelect: onSelectMark)
                }
            }
            .modifier(DCClearNavigationBackground())
            .navigationTitle(L("Contents"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(L("Close"))
                }
            }
        }
    }

    /// The entry for the chapter being read: the last entry that points into it.
    private var currentEntryId: Int? {
        entries.last { $0.spineIndex == currentSpineIndex }?.id
            ?? entries.last { ($0.spineIndex ?? .max) < currentSpineIndex }?.id
    }

    private var contentsList: some View {
        List {
            if entries.isEmpty {
                Text(L("This book has no table of contents."))
                    .foregroundStyle(.secondary)
            }
            ForEach(entries) { entry in
                Button {
                    onSelectEntry(entry)
                } label: {
                    HStack {
                        Text(entry.label)
                            .font(entry.depth == 0 ? .body.weight(.semibold) : .body)
                            .foregroundStyle(entry.spineIndex == nil ? .secondary : .primary)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 8)
                        if entry.id == currentEntryId {
                            Image(systemName: "book.fill")
                                .foregroundStyle(.tint)
                                .accessibilityLabel(L("Current chapter"))
                        }
                        if let page = pageNumber(entry) {
                            Text("\(page)")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.leading, CGFloat(entry.depth) * 16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(entry.spineIndex == nil)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}
