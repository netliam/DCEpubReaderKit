//
//  DCEpubParser.swift
//  DCEpubReaderKit
//
//  Created by Josep Cerdá Penadés on 15/10/25.
//

import Foundation
import DCEpubCore

/// High-level EPUB parser that orchestrates:
/// 1) Reading `META-INF/container.xml` to locate the OPF,
/// 2) Parsing the OPF for metadata, manifest and spine,
/// 3) Resolving the Table of Contents (EPUB2 NCX or EPUB3 nav.xhtml).
public struct DCEpubParser {

    /// Parses an unzipped EPUB directory and returns a fully populated `EpubBook`.
    /// - Parameter unzipRoot: Root folder of the **unzipped** EPUB.
    /// - Returns: `EpubBook` containing metadata, manifest, spine and TOC.
    /// - Throws: `EpubError` variants when required files are missing or cannot be parsed.
    public static func parse(from unzipRoot: URL) throws -> DCEpubBook {
        // 1) container.xml → OPF relative path
        let container = DCContainerXMLParser()
        let opfRelativePath = try container.parse(url: unzipRoot)

        let opfURL = unzipRoot.appendingPathComponent(opfRelativePath)
        guard FileManager.default.fileExists(atPath: opfURL.path) else {
            throw DCEpubError.missingOPF
        }

        // 2) OPF → package (metadata, manifest, spine)
        let opf = DCOPFParser(opfURL: opfURL)
        let package = try opf.parse()

        // 3) TOC → EPUB2 (NCX) or EPUB3 (nav.xhtml)
        let manifest = package.manifest
        let opfDirectory = opfURL.deletingLastPathComponent()

        // EPUB2: item where media-type == application/x-dtbncx+xml
        let ncxItem = manifest.first { $0.mediaType == "application/x-dtbncx+xml" }

        // EPUB3: item where properties include the token "nav"
        let navItem = manifest.first {
            guard let props = $0.properties else { return false }
            return props.split(separator: " ").map(String.init).contains("nav")
        }

        var toc: [DCTocNode] = []
        if let ncx = ncxItem {
            let ncxURL = opfDirectory.appendingPathComponent(ncx.href)
            let ncxParser = DCNCXParser()
            toc = (try? ncxParser.parse(ncxURL: ncxURL)) ?? []
        } else if let nav = navItem {
            let navURL = opfDirectory.appendingPathComponent(nav.href)
            let navParser = DCNavXHTMLParser()
            toc = (try? navParser.parse(navURL: navURL)) ?? []
        }

        // 4) Build the final model
        let book = DCEpubBook(
            packagePath: opfRelativePath,
            metadata: package.metadata,
            manifest: manifest,
            spine: package.spine,
            toc: toc,
            resourcesRoot: unzipRoot,
            spineStep: package.spineStep
        )

        return book
    }
}
