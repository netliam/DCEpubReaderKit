//
//  DCProgressScrubberTests.swift
//  DCEpubReaderKit
//
//  Created by Liam Smith-Gales on 11/11/26.
//

import Foundation
import Testing
import DCEpubCore
import DCEpubParser
@testable import DCEpubRendering

/// Mapping the progress scrubber's position to a page of the book and back.
@Suite("Progress scrubber")
struct DCProgressScrubberTests {

    private typealias Target = DCReaderViewModel.ScrubTarget
    /// Three chapters: 4, 0 (an empty cover page that lays out to nothing) and 6 pages.
    private let counts = [0: 4, 1: 0, 2: 6]

    @Test func endsOpenTheFirstAndLastPages() {
        #expect(DCReaderViewModel.scrubTarget(fraction: 0, counts: counts, chapterCount: 3)
                == Target(spineIndex: 0, pageIndex: 0, bookPage: 1, bookTotal: 10))
        #expect(DCReaderViewModel.scrubTarget(fraction: 1, counts: counts, chapterCount: 3)
                == Target(spineIndex: 2, pageIndex: 5, bookPage: 10, bookTotal: 10))
        // Out of range values (a slider overshoot) are clamped.
        #expect(DCReaderViewModel.scrubTarget(fraction: 1.4, counts: counts, chapterCount: 3).bookPage == 10)
    }

    @Test func everyPageIsReachableAndChaptersWithoutPagesAreSkipped() {
        var seen: [Target] = []
        for page in 1...10 {
            let fraction = Double(page - 1) / 9
            let target = DCReaderViewModel.scrubTarget(fraction: fraction, counts: counts, chapterCount: 3)
            #expect(target.bookPage == page)
            seen.append(target)
        }
        #expect(seen[3] == Target(spineIndex: 0, pageIndex: 3, bookPage: 4, bookTotal: 10))
        #expect(seen[4] == Target(spineIndex: 2, pageIndex: 0, bookPage: 5, bookTotal: 10))
        #expect(!seen.contains { $0.spineIndex == 1 })
    }

    @Test func movesByChapterUntilTheBookIsCounted() {
        let targets = [0, 0.4, 0.7, 1].map {
            DCReaderViewModel.scrubTarget(fraction: $0, counts: nil, chapterCount: 3)
        }
        #expect(targets.map(\.spineIndex) == [0, 1, 2, 2])
        #expect(targets.allSatisfy { $0.pageIndex == 0 && $0.bookPage == nil })
    }
}

/// The "Back to Page N" button after a jump.
@MainActor
@Suite("Back to previous page")
struct DCBackPositionTests {

    @Test func noBackButtonBeforeAnyJump() throws {
        let url = try #require(Bundle.module.url(forResource: "MinimalEPUB", withExtension: nil, subdirectory: "Fixtures"))
        let reader = DCReaderViewModel(book: try DCEpubParser.parse(from: url),
                                       spineIndex: 0,
                                       userPreferencesProtocol: DCUserPreferencesMock(),
                                       delegate: nil)
        #expect(reader.backPosition == nil)
        #expect(reader.backButtonTitle == nil)
    }

    @Test func jumpRemembersThePageItLeft() throws {
        let url = try #require(Bundle.module.url(forResource: "MinimalEPUB", withExtension: nil, subdirectory: "Fixtures"))
        let book = try DCEpubParser.parse(from: url)
        let reader = DCReaderViewModel(book: book,
                                       spineIndex: 0,
                                       userPreferencesProtocol: DCUserPreferencesMock(),
                                       delegate: nil)
        // On page 2 of 3 of the first chapter, at a known position.
        reader.handle(.currentPage(index: 2, totalPages: 3, spineIndex: 0), chapterURL: nil)
        reader.handle(.coordsFirstNodeOfPage(orientation: .horizontal, spineIndex: 0, coords: "0000001>0000003|0000012", isBookMark: false),
                      chapterURL: nil)
        #expect(reader.hasPagePosition)

        let lastChapter = book.spine.count - 1
        reader.jump(to: .init(spineIndex: lastChapter, pageIndex: 0, bookPage: nil, bookTotal: nil))
        let back = try #require(reader.backPosition)
        #expect(back.spineIndex == 0)
        #expect(back.pageIndex == 1)
        #expect(back.coords == "0000001>0000003|0000012")

        reader.goBack()
        #expect(reader.backPosition == nil)
    }

    @Test func afterARelayoutTheBackButtonNamesTheChapter() throws {
        let url = try #require(Bundle.module.url(forResource: "MinimalEPUB", withExtension: nil, subdirectory: "Fixtures"))
        let book = try DCEpubParser.parse(from: url)
        let reader = DCReaderViewModel(book: book, spineIndex: 0, userPreferencesProtocol: DCUserPreferencesMock(), delegate: nil)
        reader.handle(.currentPage(index: 1, totalPages: 3, spineIndex: 0), chapterURL: nil)
        reader.handle(.coordsFirstNodeOfPage(orientation: .horizontal, spineIndex: 0, coords: "0000001>0000001|0000000", isBookMark: false),
                      chapterURL: nil)
        reader.jump(to: .init(spineIndex: 0, pageIndex: 2, bookPage: nil, bookTotal: nil))
        // The reader reports the page it landed on.
        reader.handle(.currentPage(index: 3, totalPages: 3, spineIndex: 0), chapterURL: nil)
        let title = try #require(reader.backButtonTitle)
        reader.textLayout.lineSpacing = .loose
        // No page number from the old layout; still somewhere to go back to.
        let relaidOut = try #require(reader.backButtonTitle)
        #expect(!relaidOut.contains("Page"))
        #expect(title.hasPrefix("Back to"))
    }

    @Test func aReloadedChapterResumesAtTheLastPosition() throws {
        let url = try #require(Bundle.module.url(forResource: "MinimalEPUB", withExtension: nil, subdirectory: "Fixtures"))
        let book = try DCEpubParser.parse(from: url)
        let reader = DCReaderViewModel(book: book, spineIndex: 0, userPreferencesProtocol: DCUserPreferencesMock(), delegate: nil)
        let chapterURL = try #require(book.chapterURL(forSpineIndex: 0))
        #expect(reader.consumeInitialJump(for: 0, chapterURL: chapterURL) == nil)
        reader.handle(.coordsFirstNodeOfPage(orientation: .vertical, spineIndex: 0, coords: "0000001>0000002|0000000", isBookMark: false),
                      chapterURL: nil)
        #expect(reader.consumeInitialJump(for: 0, chapterURL: chapterURL) == .coords("0000001>0000002|0000000"))
    }
}
