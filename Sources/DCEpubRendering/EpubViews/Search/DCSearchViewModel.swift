//
//  DCSearchViewModel.swift
//  DCEpubReaderKit
//
//  Created by Liam Smith-Gales on 11/11/26.
//

import SwiftUI
import DCEpubCore

/// Results of one chapter, in reading order.
struct DCSearchSection: Identifiable {
    let spineIndex: Int
    let title: String
    let results: [DCSearchResult]

    var id: Int { spineIndex }
}

@MainActor
final class DCSearchViewModel: ObservableObject {

    private enum Constants {
        static let debounce: UInt64 = 300_000_000
    }

    @Published var query: String = ""
    @Published private(set) var sections: [DCSearchSection] = []
    @Published private(set) var resultCount: Int = 0
    @Published private(set) var isSearching: Bool = false
    /// The query the current results belong to (the text field may already have moved on).
    @Published private(set) var searchedQuery: String = ""
    /// Bumped when exact pages arrive for the results, so their page numbers are redrawn.
    @Published private(set) var pagesRevision = 0
    /// Called with every new set of results, so their exact pages can be found.
    var onResults: (([DCSearchResult], String) -> Void)?

    let resultLimit = DCEpubSearchEngine.defaultResultLimit

    private let engine: DCEpubSearchEngine
    /// Estimated whole-book page of a result, when the book has been counted.
    let pageNumber: (DCSearchResult) -> Int?
    private let onSelect: (DCSearchResult, String) -> Void
    private var searchTask: Task<Void, Never>?

    init(engine: DCEpubSearchEngine,
         pageNumber: @escaping (DCSearchResult) -> Int? = { _ in nil },
         onSelect: @escaping (DCSearchResult, String) -> Void) {
        self.engine = engine
        self.pageNumber = pageNumber
        self.onSelect = onSelect
    }

    var hasReachedLimit: Bool {
        resultCount >= resultLimit
    }

    var showsNoResults: Bool {
        !isSearching && !searchedQuery.isEmpty && resultCount == 0
    }

    func queryDidChange() {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            apply([], for: "")
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task { [weak self, engine] in
            // Debounce typing; cancelling this task also stops the engine between chapters.
            try? await Task.sleep(nanoseconds: Constants.debounce)
            guard !Task.isCancelled else { return }
            let results = await engine.search(trimmed)
            guard !Task.isCancelled, let self else { return }
            self.apply(results, for: trimmed)
            self.isSearching = false
        }
    }

    func pagesDidChange() {
        pagesRevision += 1
    }

    func select(_ result: DCSearchResult) {
        onSelect(result, searchedQuery)
    }

    private func apply(_ results: [DCSearchResult], for query: String) {
        searchedQuery = query
        resultCount = results.count
        // Results arrive in reading order, so each chapter's matches are contiguous.
        var sections: [DCSearchSection] = []
        var current: [DCSearchResult] = []
        for result in results {
            if let last = current.last, last.spineIndex != result.spineIndex {
                sections.append(Self.section(for: current))
                current = []
            }
            current.append(result)
        }
        if !current.isEmpty {
            sections.append(Self.section(for: current))
        }
        self.sections = sections
        onResults?(results, query)
    }

    private static func section(for results: [DCSearchResult]) -> DCSearchSection {
        let first = results[0]
        let title = first.chapterTitle.isEmpty ? "Section \(first.spineIndex + 1)" : first.chapterTitle
        return DCSearchSection(spineIndex: first.spineIndex, title: title, results: results)
    }
}
