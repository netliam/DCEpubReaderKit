//
//  DCReaderConfiguration.swift
//  DCEpubReaderKit
//
//  Created by Liam Smith-Gales on 11/11/26.
//

import UIKit

/// What a host app can set when it opens the reader (`DCReaderViewBuilder.build`). Every value has a
/// default that matches the reader's behavior without a configuration.
public struct DCReaderConfiguration {

    /// Where the reader keeps its settings, custom theme colors and last highlight color. Use a
    /// suite to keep them apart from the app's own defaults.
    public var defaults: UserDefaults = .standard
    /// The key for this book's highlights, bookmarks and position. `nil` uses the book's OPF
    /// identifier, which can be missing or shared by different editions.
    public var bookId: String?

    public var showsSearch = true
    public var showsLineGuide = true
    /// Rotation lock does nothing on Mac and is ignored on iPad when the window isn't full screen
    /// (the reader also hides it then).
    public var showsRotationLock = !ProcessInfo.processInfo.isMacCatalystApp
    /// Screen brightness does nothing on Mac.
    public var showsBrightness = !ProcessInfo.processInfo.isMacCatalystApp
    /// When off, pages slide and the Page Turn setting is hidden.
    public var allowsPageCurl = true

    /// Closes the reader. `nil` dismisses it (it was pushed or presented); set it when the reader
    /// has a window of its own (e.g. `openWindow` on Mac).
    public var onClose: (@MainActor () -> Void)?
    /// Opens a web or mail link from the book. `nil` opens it with `UIApplication.open`.
    public var onOpenExternalURL: (@MainActor (URL) -> Void)?
    /// Fonts offered in Customize besides the built-in ones.
    public var fonts: [DCReaderFont] = []
    /// The styles, colors and actions of the selection and highlight menus.
    public var highlightMenu = DCHighlightMenuConfiguration()

    public init() {}
}

/// A font the host app offers in the reader. Its files are loaded into the pages with `@font-face`.
public struct DCReaderFont: Equatable, Sendable {
    /// Shown in Customize; also the stored choice, so keep it stable.
    public let name: String
    /// The CSS `font-family` the files declare.
    public let cssFamily: String
    /// Font files (TTF/OTF) the pages can read. Empty for fonts the system already has.
    public let files: [URL]

    public init(name: String, cssFamily: String, files: [URL] = []) {
        self.name = name
        self.cssFamily = cssFamily
        self.files = files
    }

    /// How a choice of this font is stored with the reader settings.
    var storageKey: String { "custom:\(name)" }

    /// `@font-face` rules for its files and the rule that applies it to the text.
    var css: String {
        let family = cssFamily.replacingOccurrences(of: "\"", with: "")
        let faces = files.map { "@font-face { font-family: \"\(family)\"; src: url(\"\($0.absoluteString)\"); }" }
        return (faces + ["html body, html body * { font-family: \"\(family)\" !important; }"]).joined(separator: "\n")
    }
}
