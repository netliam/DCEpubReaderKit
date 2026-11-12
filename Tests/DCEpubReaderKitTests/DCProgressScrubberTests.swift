//
//  DCProgressScrubberTests.swift
//  DCEpubReaderKit
//
//  Created by Liam Smith-Gales on 11/11/26.
//

import Foundation
import Testing
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
