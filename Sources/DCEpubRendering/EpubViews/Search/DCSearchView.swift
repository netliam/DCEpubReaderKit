//
//  DCSearchView.swift
//  DCEpubReaderKit
//
//  Created by Liam Smith-Gales on 11/11/26.
//

import SwiftUI
import DCEpubCore

struct DCSearchView: View {

    @ObservedObject var viewModel: DCSearchViewModel

    init(viewModel: DCSearchViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        List {
            ForEach(viewModel.sections) { section in
                Section(section.title) {
                    ForEach(section.results) { result in
                        Button {
                            viewModel.select(result)
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(snippet(for: result))
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if let page = viewModel.pageNumber(result) {
                                    Text("\(page)")
                                        .font(.subheadline.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                        .accessibilityLabel(String(format: L("Page %lld"), page))
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if viewModel.hasReachedLimit {
                Text(String(format: L("Showing the first %lld results. Refine your search to see more."), viewModel.resultLimit))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if viewModel.isSearching && viewModel.sections.isEmpty {
                ProgressView()
            } else if viewModel.showsNoResults {
                Text(String(format: L("No results for “%@”."), viewModel.searchedQuery))
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
        .searchable(text: $viewModel.query,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: L("Search in book"))
        .onChange(of: viewModel.query) { _ in
            viewModel.queryDidChange()
        }
        .navigationTitle(L("Search"))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Context with the match emphasised.
    private func snippet(for result: DCSearchResult) -> AttributedString {
        var snippet = AttributedString(result.prefix)
        var match = AttributedString(result.match)
        match.inlinePresentationIntent = .stronglyEmphasized
        match.backgroundColor = Color.orange.opacity(0.3)
        snippet.append(match)
        snippet.append(AttributedString(result.suffix))
        return snippet
    }
}
