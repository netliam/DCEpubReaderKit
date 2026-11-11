//
//  DCBookPageEstimateTests.swift
//  DCEpubReaderKit
//
//  Created by Liam Smith-Gales on 11/11/26.
//

import Testing
@testable import DCEpubRendering

@Suite("Whole-book page estimate")
struct DCBookPageEstimateTests {

    @Test func usesTheCountWhenComplete() {
        let counts = [0: 2, 1: 10, 2: 4]
        #expect(DCReaderViewModel.estimatedPageCounts(current: counts, previous: [:], chapterCount: 3,
                                                      currentChapter: (1, 10)) == counts)
    }

    @Test func nothingToShowBeforeTheFirstCompleteCount() {
        #expect(DCReaderViewModel.estimatedPageCounts(current: [0: 2], previous: [:], chapterCount: 3,
                                                      currentChapter: (0, 2)) == nil)
    }

    /// After a text-size change the book is recounted; until then, chapters not counted yet are
    /// scaled by how much the counted ones grew, so the label keeps showing page numbers.
    @Test func scalesUncountedChaptersFromThePreviousCount() {
        let previous = [0: 2, 1: 10, 2: 20]
        // Larger text: chapter 0 now has 3 pages (counted) and the chapter on screen, 1, has 15.
        let estimate = DCReaderViewModel.estimatedPageCounts(current: [0: 3], previous: previous, chapterCount: 3,
                                                             currentChapter: (1, 15))
        // Counted 18 new pages where there were 12: scale 1.5, so chapter 2 is estimated at 30.
        #expect(estimate == [0: 3, 1: 15, 2: 30])
    }
}
