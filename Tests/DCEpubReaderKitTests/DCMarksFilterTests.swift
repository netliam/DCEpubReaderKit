//
//  DCMarksFilterTests.swift
//  DCEpubReaderKit
//
//  Created by Liam Smith-Gales on 11/11/26.
//

import Foundation
import Testing
import DCEpubCore
@testable import DCEpubRendering

/// Filtering and sorting the Highlights and Bookmarks lists.
@MainActor
@Suite("Highlights list filters")
struct DCMarksFilterTests {

    private func mark(_ uuid: String, _ type: DCHighlight.MarkType = .highlight, spine: Int, coords: String,
                      style: DCHighlightStyle? = .yellow, note: String = "", updated: Double) -> DCHighlight {
        DCHighlight(uuid: uuid, bookId: "b", chapterId: "c\(spine)", spineIndex: spine, type: type,
                    text: uuid, coords: coords, note: note, style: style, dateUpdated: updated)
    }

    private var marks: [DCHighlight] {
        [
            mark("late-green", spine: 2, coords: "0000001>0000002|0000004", style: .green, updated: 10),
            mark("early-yellow", spine: 0, coords: "0000001>0000009|0000000", updated: 30),
            mark("early-note", .note, spine: 0, coords: "0000001>0000010|0000003", style: .underline, note: "Hm", updated: 20),
            mark("green-with-note", spine: 1, coords: "0000001>0000001|0000000", style: .green, note: "Yes", updated: 40),
            mark("bookmark", .bookMark, spine: 1, coords: "0000001>0000000|0000000", style: nil, updated: 50)
        ]
    }

    private func loaded(types: [DCHighlight.MarkType]) async -> DCMarksViewModel {
        let marks = self.marks
        let viewModel = DCMarksViewModel(types: types, highlightsProvider: { marks }, onSelect: { _ in })
        await viewModel.loadIfNeeded()
        return viewModel
    }

    @Test func defaultsToEveryHighlightInReadingOrder() async {
        let viewModel = await loaded(types: [.highlight, .note])
        #expect(viewModel.filteredHighlights.map(\.uuid) == ["early-yellow", "early-note", "green-with-note", "late-green"])
    }

    @Test func sortsByMostRecentlyChanged() async {
        let viewModel = await loaded(types: [.highlight, .note])
        viewModel.sort = .recent
        #expect(viewModel.filteredHighlights.map(\.uuid) == ["green-with-note", "early-yellow", "early-note", "late-green"])
    }

    @Test func offersOnlyFiltersThatMatchSomething() async {
        let viewModel = await loaded(types: [.highlight, .note])
        #expect(viewModel.availableFilters == [.all, .notes, .look(.highlight, "#FFEB6B"), .look(.highlight, "#C0ED72"),
                                               .look(.underline, "#F02814")])
        #expect(viewModel.showsFilters)
    }

    @Test func filtersByColorAndByNote() async {
        let viewModel = await loaded(types: [.highlight, .note])
        viewModel.filter = .look(.highlight, "#C0ED72")
        #expect(viewModel.filteredHighlights.map(\.uuid) == ["green-with-note", "late-green"])
        // Any highlight with a note counts, whatever its type.
        viewModel.filter = .notes
        #expect(viewModel.filteredHighlights.map(\.uuid) == ["early-note", "green-with-note"])
    }

    @Test func readingOrderComparesCoordsAsNumbers() async {
        // As strings, the deeper path ("…>0000003>…") would sort before the shallower one.
        let shallow = mark("shallow", spine: 0, coords: "0000001>0000002>0000005,0000001>0000002>0000009", updated: 0)
        let deep = mark("deep", spine: 0, coords: "0000001>0000003>0000001>0000000,0000001>0000003>0000001>0000004", updated: 0)
        let viewModel = DCMarksViewModel(types: [.highlight], highlightsProvider: { [deep, shallow] }, onSelect: { _ in })
        await viewModel.loadIfNeeded()
        #expect(viewModel.filteredHighlights.map(\.uuid) == ["shallow", "deep"])
        #expect(DCMarksViewModel.coordsKey("0000001>0000003>0000012,0000001>0000003>0000020") == [1, 3, 12])
    }

    @Test func readingOrderUsesPageNumbersWhenKnown() async {
        let first = mark("first", spine: 0, coords: "0000009>0000000", updated: 0)
        let second = mark("second", spine: 0, coords: "0000001>0000000", updated: 0)
        let pages = ["first": 3, "second": 4]
        let viewModel = DCMarksViewModel(types: [.highlight], highlightsProvider: { [second, first] },
                                         pageNumber: { pages[$0.uuid] }, onSelect: { _ in })
        await viewModel.loadIfNeeded()
        #expect(viewModel.filteredHighlights.map(\.uuid) == ["first", "second"])
    }

    @Test func bookmarksSortButDoNotFilter() async {
        let viewModel = await loaded(types: [.bookMark])
        #expect(!viewModel.showsFilters)
        #expect(viewModel.filteredHighlights.map(\.uuid) == ["bookmark"])
    }
}

/// Sharing all highlights and notes from the Highlights list.
@MainActor
@Suite("Export highlights")
struct DCMarksExportTests {
    @Test func exportsTheListedHighlightsUnderTheirChapters() async {
        let marks = [
            DCHighlight(uuid: "a", bookId: "b", chapterId: "c1", spineIndex: 0, type: .highlight,
                        text: " First passage. ", coords: "0000001>0000001|0000000", chapterTitle: "One", style: .yellow),
            DCHighlight(uuid: "b", bookId: "b", chapterId: "c1", spineIndex: 0, type: .note,
                        text: "Second", coords: "0000001>0000002|0000000", note: "My thought", chapterTitle: "One", style: .green),
            DCHighlight(uuid: "c", bookId: "b", chapterId: "c2", spineIndex: 1, type: .highlight,
                        text: "Third", coords: "0000001>0000001|0000000", chapterTitle: "Two", style: .yellow)
        ]
        let pages = ["a": 3, "b": 4]
        let viewModel = DCMarksViewModel(types: [.highlight, .note], highlightsProvider: { marks },
                                         pageNumber: { pages[$0.uuid] }, exportHeading: "Book by Author",
                                         onSelect: { _ in })
        await viewModel.loadIfNeeded()
        #expect(viewModel.canExport)
        #expect(viewModel.exportText == """
        Book by Author

        ONE
        “First passage.” (p. 3)

        “Second” (p. 4)
        Note: My thought

        TWO
        “Third”
        """)

        // It shares what the list shows.
        viewModel.filter = .notes
        #expect(viewModel.exportText == "Book by Author\n\nONE\n“Second” (p. 4)\nNote: My thought")
    }

    @Test func bookmarksDoNotExport() async {
        let viewModel = DCMarksViewModel(types: [.bookMark], highlightsProvider: { [] }, onSelect: { _ in })
        await viewModel.loadIfNeeded()
        #expect(!viewModel.canExport)
    }

    @Test func colorsFromElsewhereGetAFilterAfterThePalettes() async {
        let crimson = DCHighlight(uuid: "web", bookId: "b", chapterId: "c0", spineIndex: 0, type: .highlight,
                                  text: "w", coords: "0000001>0000001|0000000", annotationStyle: .squiggly, color: "#dc143c")
        let yellow = DCHighlight(uuid: "y", bookId: "b", chapterId: "c0", spineIndex: 0, type: .highlight,
                                 text: "y", coords: "0000001>0000002|0000000", style: .yellow)
        let viewModel = DCMarksViewModel(types: [.highlight], highlightsProvider: { [crimson, yellow] }, onSelect: { _ in })
        await viewModel.loadIfNeeded()
        #expect(viewModel.availableFilters == [.all, .look(.highlight, "#FFEB6B"), .look(.squiggly, "#DC143C")])
        #expect(viewModel.name(of: .squiggly, color: "#DC143C") == "Squiggly")
        viewModel.filter = DCMarksViewModel.Filter.look(.squiggly, "#DC143C")
        #expect(viewModel.filteredHighlights.map { $0.uuid } == ["web"])
    }
}
