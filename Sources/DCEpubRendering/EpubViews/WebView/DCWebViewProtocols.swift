//
//  DCWebViewProtocols.swift
//  DCEpubReaderKit
//
//  Created by Josep Cerdá Penadés on 26/11/25.
//

import Foundation
import DCEpubCore

@MainActor
protocol DCWebViewModelProtocol {
    func showNoote(highlight: DCHighlight)
    /// Opens the book search with `text` (the selection menu's Search).
    func searchBook(for text: String)
    /// Follows a link that isn't a footnote: another place in the book, or a web page.
    func openLink(_ url: URL)
    func saveHighlight(_ highlight: DCHighlight) async
    func loadHighlights() async -> [DCHighlight]
    func deleteHighlight(uuid: String) async
    var currentBookId: String { get }
    var currentChapterId: String { get }
    var currentSpineIndex: Int { get }
    /// The book being read, for sharing a passage with its title.
    var currentBook: DCEpubBook? { get }
    var refresh: (() -> Void)? { get set }
}

@MainActor
protocol DCWebViewRouterProtocol {
    func showNoote(highlight: DCHighlight)
    /// Opens the book search with `text` (the selection menu's Search).
    func searchBook(for text: String)
    /// Follows a link that isn't a footnote: another place in the book, or a web page.
    func openLink(_ url: URL)
    func saveHighlight(_ highlight: DCHighlight) async
    func loadHighlights() async -> [DCHighlight]
    func deleteHighlight(uuid: String) async
    var currentBookId: String { get }
    var currentChapterId: String { get }
    var currentSpineIndex: Int { get }
    /// The book being read, for sharing a passage with its title.
    var currentBook: DCEpubBook? { get }
}
