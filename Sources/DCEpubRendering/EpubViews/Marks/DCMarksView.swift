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
    /// The exported highlights while the share sheet is up.
    @State private var shareText: String?

    var body: some View {
        List {
            filterBar
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)

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
        .sheet(isPresented: Binding(get: { shareText != nil }, set: { if !$0 { shareText = nil } })) {
            DCShareSheet(items: [shareText ?? ""])
                .presentationDetents([.medium, .large])
        }
    }

    /// Filter chips (highlights only) and the sort menu.
    private var filterBar: some View {
        HStack(spacing: 8) {
            if viewModel.showsFilters {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.availableFilters, id: \.self) { filter in
                            filterChip(filter)
                        }
                    }
                }
            } else {
                Spacer(minLength: 0)
            }
            Menu {
                Picker(L("Sort By"), selection: $viewModel.sort) {
                    ForEach(DCMarksViewModel.Sort.allCases, id: \.self) { sort in
                        Text(sort.title).tag(sort)
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(L("Sort By"))
            .accessibilityValue(viewModel.sort.title)

            if viewModel.canExport {
                Button {
                    shareText = viewModel.exportText
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                // In a List row, buttons without their own style don't get their taps.
                .buttonStyle(.borderless)
                .accessibilityLabel(L("Share Highlights and Notes"))
            }
        }
    }

    private func filterChip(_ filter: DCMarksViewModel.Filter) -> some View {
        let isSelected = viewModel.filter == filter
        return Button {
            viewModel.filter = filter
        } label: {
            Group {
                switch filter {
                case .all:
                    Text(L("All"))
                case .notes:
                    Label(L("Notes"), systemImage: "note.text")
                case let .look(style, color):
                    let swatch = Color(uiColor: UIColor(hex: color) ?? .label)
                    if style == .highlight {
                        Circle()
                            .fill(swatch)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: style.systemImage)
                            .foregroundStyle(swatch)
                    }
                }
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(isSelected ? Color.primary.opacity(0.15) : Color.primary.opacity(0.05), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(isSelected ? 0.4 : 0), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(for: filter))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func accessibilityLabel(for filter: DCMarksViewModel.Filter) -> String {
        switch filter {
        case .all: L("All")
        case .notes: L("Notes")
        case let .look(style, color): viewModel.name(of: style, color: color)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: iconName(for: viewModel.primaryType))
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(viewModel.filter == .all ? L("No marks") : L("No matches"))
                .font(.headline)
            Text(viewModel.filter == .all
                 ? emptyMessage(for: viewModel.primaryType)
                 : L("Nothing in this book matches this filter."))
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
                Image(systemName: highlight.hasNote ? "note.text" : iconName(for: highlight.type))
                    .foregroundStyle(iconColor(for: highlight))
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

                if let page = viewModel.pageNumber(highlight) {
                    Text("\(page)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(String(format: L("Page %lld"), page))
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    /// Highlights and notes show their color; bookmarks stay neutral.
    private func iconColor(for highlight: DCHighlight) -> Color {
        guard highlight.type != .bookMark, let swatch = UIColor(hex: highlight.color) else { return .secondary }
        return Color(uiColor: swatch)
    }

    private func primaryText(for highlight: DCHighlight) -> String {
        if highlight.type != .bookMark, highlight.hasNote {
            return highlight.note
        }
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
        if highlight.type != .bookMark, highlight.hasNote {
            return highlight.text.isEmpty ? chapterText : "\(chapterText) · \(highlight.text)"
        }

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
            return L("This book does not have highlights yet.")
        case .note:
            return L("This book does not have notes yet.")
        case .bookMark:
            return L("This book does not have bookmarks yet.")
        }
    }
}
