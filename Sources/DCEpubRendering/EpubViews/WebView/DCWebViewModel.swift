//
//  DCWebViewModel.swift
//  DCEpubReaderKit
//
//  Created by Josep Cerdá Penadés on 26/11/25.
//

import Foundation
import DCEpubCore

@MainActor
final class DCWebViewModel: DCWebViewModelProtocol {

    var refresh: (() -> Void)?

    private let router: DCWebViewRouterProtocol

    init(router: DCWebViewRouterProtocol) {
        self.router = router
    }

    func showNoote(highlight: DCHighlight) {
        router.showNoote(highlight: highlight)
    }

    func searchBook(for text: String) {
        router.searchBook(for: text)
    }

    func openLink(_ url: URL) {
        router.openLink(url)
    }

    func saveHighlight(_ highlight: DCHighlight) async {
        await router.saveHighlight(highlight)
    }

    func loadHighlights() async -> [DCHighlight] {
        await router.loadHighlights()
    }

    func deleteHighlight(uuid: String) async {
        await router.deleteHighlight(uuid: uuid)
    }

    var currentBookId: String { router.currentBookId }
    var currentChapterId: String { router.currentChapterId }
    var currentSpineIndex: Int { router.currentSpineIndex }
}
