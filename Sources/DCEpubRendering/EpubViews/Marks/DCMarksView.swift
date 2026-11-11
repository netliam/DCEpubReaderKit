//
//  DCMarksView.swift
//  DCEpubReaderKit
//
//  Created by Josep Cerdá Penadés on 07/05/2026.
//

import SwiftUI
import DCEpubCore

struct DCMarksView: View {

    @ObservedObject var viewModel: DCMarksViewModel

    var body: some View {
        List {
            if viewModel.types.count > 1 {
                Picker("Filter", selection: $viewModel.selectedType) {
                    ForEach(viewModel.types, id: \.self) { type in
                        Text(title(for: type)).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
            }

            if viewModel.filteredHighlights.isEmpty {
                emptyState
                .listRowBackground(Color.clear)
            } else {
                ForEach(viewModel.filteredHighlights, id: \.uuid) { highlight in
                    Button {
                        viewModel.didSelect(highlight)
                    } label: {
                        markRow(highlight)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .task {
            await viewModel.loadIfNeeded()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: iconName(for: viewModel.selectedType))
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("No marks")
                .font(.headline)
            Text(emptyMessage(for: viewModel.selectedType))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private func markRow(_ highlight: DCHighlight) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: iconName(for: highlight.type))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 4) {
                    Text(primaryText(for: highlight))
                        .font(.body)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)

                    Text(secondaryText(for: highlight))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func primaryText(for highlight: DCHighlight) -> String {
        switch highlight.type {
        case .highlight:
            return highlight.text
        case .note:
            return highlight.note.isEmpty ? highlight.text : highlight.note
        case .bookMark:
            return highlight.chapterTitle.isEmpty ? highlight.chapterId : highlight.chapterTitle
        }
    }

    private func secondaryText(for highlight: DCHighlight) -> String {
        let chapterText = highlight.chapterTitle.isEmpty ? highlight.chapterId : highlight.chapterTitle

        switch highlight.type {
        case .highlight:
            return chapterText
        case .note:
            if highlight.note.isEmpty {
                return chapterText
            }
            return highlight.text.isEmpty ? chapterText : "\(chapterText) · \(highlight.text)"
        case .bookMark:
            return chapterText
        }
    }

    private func title(for type: DCHighlight.MarkType) -> String {
        switch type {
        case .highlight:
            return "Highlight"
        case .note:
            return "Note"
        case .bookMark:
            return "Bookmark"
        }
    }

    private func iconName(for type: DCHighlight.MarkType) -> String {
        switch type {
        case .highlight:
            return "highlighter"
        case .note:
            return "note.text"
        case .bookMark:
            return "bookmark"
        }
    }

    private func emptyMessage(for type: DCHighlight.MarkType) -> String {
        switch type {
        case .highlight:
            return "This book does not have highlights yet."
        case .note:
            return "This book does not have notes yet."
        case .bookMark:
            return "This book does not have bookmarks yet."
        }
    }
}
