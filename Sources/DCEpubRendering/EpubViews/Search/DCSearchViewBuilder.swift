//
//  DCSearchViewBuilder.swift
//  DCEpubReaderKit
//
//  Created by Liam Smith-Gales on 11/11/26.
//

import SwiftUI

final class DCSearchViewBuilder {
    /// The view model is owned by the reader so the query and results survive closing the sheet.
    @MainActor
    func build(viewModel: DCSearchViewModel) -> DCSearchView {
        DCSearchView(viewModel: viewModel)
    }
}
