//
//  DCLocalization.swift
//  DCEpubReaderKit
//
//  Created by Liam Smith-Gales on 11/11/26.
//

import Foundation

/// A UI string from the package's own `Localizable.xcstrings`. SwiftUI's string literals would
/// look in the app's bundle instead. Keys with values use format specifiers (`"Page %lld"`) with
/// `String(format:)`, so every key in code is a literal in the catalog (a test checks).
func L(_ key: String) -> String {
    Bundle.module.localizedString(forKey: key, value: nil, table: nil)
}
