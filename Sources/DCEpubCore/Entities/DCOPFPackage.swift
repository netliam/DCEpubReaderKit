//
//  DCOPFPackage.swift
//  DCEpubReaderKit
//
//  Created by Josep Cerdá Penadés on 15/10/25.
//

import Foundation

public struct DCOPFPackage {
    public let opfURL: URL
    public var metadata: DCOPFMetadata
    public var manifest: [DCManifestItem]
    public var spine: [DCSpineItem]
    public var guide: [DCGuideRef]
    /// The CFI step of `<spine>` inside `<package>`: 2 × its position among the package's child
    /// elements (6 when it's the third, as in most books).
    public var spineStep: Int

    public init(opfURL: URL,
                metadata: DCOPFMetadata,
                manifest: [DCManifestItem],
                spine: [DCSpineItem],
                guide: [DCGuideRef],
                spineStep: Int = 6) {
        self.opfURL = opfURL
        self.metadata = metadata
        self.manifest = manifest
        self.spine = spine
        self.guide = guide
        self.spineStep = spineStep
    }
}
