//
//  DCTextLayoutTests.swift
//  DCEpubReaderKit
//
//  Created by Liam Smith-Gales on 11/11/26.
//

import Foundation
import Testing
import DCEpubCore
import DCEpubParser
@testable import DCEpubRendering

/// Line spacing, margins and justification.
@Suite("Text layout settings")
struct DCTextLayoutTests {

    @Test func defaultsKeepTheBooksLayout() {
        let layout = DCTextLayout()
        #expect(layout.lineSpacing == .original)
        #expect(layout.margins == .normal)
        #expect(layout.justified)
        // Nothing to override, and the margins are the reader's long-standing inset.
        #expect(layout.css.isEmpty)
        #expect(layout.margins.inset == DCReaderChrome.horizontalInset)
    }

    @Test func cssSetsLineHeightAndAlignment() {
        let layout = DCTextLayout(lineSpacing: .relaxed, margins: .wide, justified: false)
        #expect(layout.css.contains("line-height: 1.75 !important"))
        #expect(layout.css.contains("text-align: start !important"))
        #expect(DCPageMargins.allCases.map(\.inset) == DCPageMargins.allCases.map(\.inset).sorted())
    }

    @Test func storedInUserDefaults() throws {
        let defaults = try #require(UserDefaults(suiteName: "DCTextLayoutTests-\(UUID().uuidString)"))
        #expect(defaults.getTextLayout() == DCTextLayout())
        defaults.setValue(key: .lineSpacing, type: DCLineSpacing.loose.rawValue)
        defaults.setValue(key: .pageMargins, type: DCPageMargins.narrow.rawValue)
        defaults.setValue(key: .justifyText, type: false)
        #expect(defaults.getTextLayout() == DCTextLayout(lineSpacing: .loose, margins: .narrow, justified: false))
    }

    @Test @MainActor func changingItLaysTheBookOutAgain() throws {
        let url = try #require(Bundle.module.url(forResource: "MinimalEPUB", withExtension: nil, subdirectory: "Fixtures"))
        let reader = DCReaderViewModel(book: try DCEpubParser.parse(from: url),
                                       spineIndex: 0,
                                       userPreferencesProtocol: DCUserPreferencesMock(),
                                       delegate: nil)
        let paged = reader.pagedConfigId
        let scrolling = reader.readerConfigId(for: 0)
        reader.textLayout.lineSpacing = .loose
        #expect(reader.pagedConfigId != paged)
        #expect(reader.readerConfigId(for: 0) != scrolling)
    }
}

/// Rotation lock: the setting and the orientation it locks to.
@MainActor
@Suite("Rotation lock")
struct DCRotationLockTests {
    @Test func locksToTheOrientationOnScreen() {
        #expect(DCReaderOrientationLock.mask(for: .portrait) == .portrait)
        #expect(DCReaderOrientationLock.mask(for: .landscapeLeft) == .landscapeLeft)
        #expect(DCReaderOrientationLock.mask(for: .landscapeRight) == .landscapeRight)
        #expect(DCReaderOrientationLock.mask(for: .unknown) == .portrait)
    }

    @Test func settingIsStoredAndUnlockedByDefault() throws {
        let defaults = try #require(UserDefaults(suiteName: "DCRotationLockTests-\(UUID().uuidString)"))
        #expect(defaults.getRotationLock() == false)
        defaults.setValue(key: .rotationLock, type: true)
        #expect(defaults.getRotationLock())
    }

    @Test func closingTheReaderUnlocks() throws {
        let url = try #require(Bundle.module.url(forResource: "MinimalEPUB", withExtension: nil, subdirectory: "Fixtures"))
        let preferences = DCUserPreferencesMock()
        preferences.rotationLock = true
        let reader = DCReaderViewModel(book: try DCEpubParser.parse(from: url), spineIndex: 0,
                                       userPreferencesProtocol: preferences, delegate: nil)
        reader.readerDidAppear()
        reader.readerDidDisappear()
        #expect(DCReaderOrientationLock.supportedOrientations == .all)
    }
}
