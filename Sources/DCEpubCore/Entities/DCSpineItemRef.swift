//
//  DCSpineItemRef.swift
//  DCEpubReaderKit
//
//  Created by Josep Cerdá Penadés on 15/10/25.
//

public struct DCSpineItem: Sendable {
    public let idref: String
    public let linear: Bool
    /// The itemref's `properties`, e.g. `rendition:layout-pre-paginated page-spread-left`.
    public let properties: String?

    public init(idref: String, linear: Bool, properties: String? = nil) {
        self.idref = idref
        self.linear = linear
        self.properties = properties
    }

    static let mock: DCSpineItem = DCSpineItem(idref: "", linear: false)
}
