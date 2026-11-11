//
//  DCReaderChrome.swift
//  DCEpubReaderKit
//
//  Created by Liam Smith-Gales on 11/11/26.
//

import CoreGraphics

/// Layout of the floating reader controls. Pages fill the whole screen (so page turns cover it)
/// and keep their text clear of the controls with these insets, measured inside the safe area.
enum DCReaderChrome {
    /// Room for the close button, "pages left" label and bookmark button.
    static let topInset: CGFloat = 52
    /// Room for the progress bar, page number and menu button.
    static let bottomInset: CGFloat = 60
    static let horizontalInset: CGFloat = 24
    /// Gap between CSS columns in the paged reader (`columnGap` in `applyHorizontalPagination`).
    /// Each column is this much narrower than the web view, so the web view extends this far into
    /// the right margin to keep the text column centered.
    static let columnGap: CGFloat = 20
    /// Diameter of the round floating buttons.
    static let buttonSize: CGFloat = 44
    /// Default height of the Themes & Settings card (it can be dragged to full height).
    static let settingsSheetHeight: CGFloat = 560
}
