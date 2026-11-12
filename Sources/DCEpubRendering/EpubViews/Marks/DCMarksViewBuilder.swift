//
//  DCMarksViewBuilder.swift
//  DCEpubReaderKit
//
//  Created by Josep Cerdá Penadés on 07/05/2026.
//

import SwiftUI
import DCEpubCore

@MainActor
final class DCMarksViewBuilder {
    func build(types: [DCHighlight.MarkType] = [.highlight, .note, .bookMark],
               highlightsProvider: @escaping () async -> [DCHighlight],
               pageNumber: @escaping (DCHighlight) -> Int? = { _ in nil },
               exportHeading: String? = nil,
               onSelect: @escaping (DCHighlight) -> Void) -> DCMarksView {
        let viewModel = DCMarksViewModel(
            types: types,
            highlightsProvider: highlightsProvider,
            pageNumber: pageNumber,
            exportHeading: exportHeading,
            onSelect: onSelect
        )
        return DCMarksView(viewModel: viewModel)
    }
}
