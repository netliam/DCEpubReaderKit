//
//  DCEpubBook.swift
//  DCEpubReaderKit
//
//  Created by Josep Cerdá Penadés on 15/10/25.
//

import Foundation
import CryptoKit

private extension String {
    func sha256() -> String {
        let data = Data(self.utf8)
        if #available(iOS 13.0, macOS 10.15, *) {
            let digest = SHA256.hash(data: data)
            return digest.map { String(format: "%02x", $0) }.joined()
        }
        return self
    }
}

public struct DCEpubBook: Sendable {
    public let packagePath: String
    public let metadata: DCOPFMetadata
    public let manifest: [DCManifestItem]
    public let spine: [DCSpineItem]
    public let toc: [DCTocNode]
    public let resourcesRoot: URL

    public init(packagePath: String,
                metadata: DCOPFMetadata,
                manifest: [DCManifestItem],
                spine: [DCSpineItem],
                toc: [DCTocNode],
                resourcesRoot: URL) {
        self.packagePath = packagePath
        self.metadata = metadata
        self.manifest = manifest
        self.spine = spine
        self.toc = toc
        self.resourcesRoot = resourcesRoot
    }
}

// MARK: - Helpers to resolve absolute URLs for chapters and resources.

extension DCEpubBook {

    // MARK: Identifiers

    public var uniqueIdentifier: String {
        // 1. Look for an explicit UUID in the identifiers (string-based)
        if let uuid = metadata.identifiers.first(where: {
            let lower = $0.lowercased()
            return lower.hasPrefix("urn:uuid:") || isUUID(lower)
        }) {
            return normalizeUUID(uuid)
        }

        // 2. Any available identifier
        if let identifier = metadata.identifiers.first, !identifier.isEmpty {
            return identifier
        }

        // 3. Deterministic fallback (last resort)
        return fallbackIdentifier
    }

    private var fallbackIdentifier: String {
        let base = [
            metadata.title ?? "",
            metadata.creators.joined(separator: ","),
            spine.map { $0.idref }.joined()
        ].joined(separator: "|")

        return base.sha256()
    }

    private func isUUID(_ value: String) -> Bool {
        let cleaned = value.replacingOccurrences(of: "urn:uuid:", with: "")
        return UUID(uuidString: cleaned) != nil
    }

    private func normalizeUUID(_ value: String) -> String {
        if value.lowercased().hasPrefix("urn:uuid:") {
            return String(value.dropFirst("urn:uuid:".count))
        }
        return value
    }

    // MARK: Paths

    /// Directory that contains the OPF (base directory for all manifest hrefs).
    /// Example: .../UnzippedBook/OEBPS/
    public var opfDirectoryURL: URL {
        resourcesRoot
            .appendingPathComponent(packagePath)
            .deletingLastPathComponent()
            .standardizedFileURL
    }

    /// Returns the absolute file URL for a manifest `href` (relative to the OPF directory).
    public func resourceURL(forHref href: String) -> URL {
        opfDirectoryURL
            .appendingPathComponent(href)
            .standardizedFileURL
    }

    // MARK: Chapters

    /// Returns the absolute URL for a chapter by spine index.
    public func chapterURL(forSpineIndex index: Int) -> URL? {
        guard index >= 0 && index < spine.count else { return nil }
        let idref = spine[index].idref
        guard let item = manifest.first(where: { $0.id == idref }) else { return nil }
        return resourceURL(forHref: item.href)
    }

    /// The spine index of the chapter at `url` (a file URL; any `#fragment` is ignored).
    public func spineIndex(forChapterURL url: URL) -> Int? {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        let target = (components?.url ?? url).standardizedFileURL.path
        return spine.indices.first { chapterURL(forSpineIndex: $0)?.standardizedFileURL.path == target }
    }

    /// Returns the absolute URL for a chapter by manifest `idref`.
    public func chapterURL(forIdRef idref: String) -> URL? {
        guard let item = manifest.first(where: { $0.id == idref }) else { return nil }
        return resourceURL(forHref: item.href)
    }

    // Small helper to avoid using large tuples when correlating TOC and spine
    private struct HrefLookup: Equatable {
        let idref: String
        let hrefLower: String
        let lastLower: String
    }

    // MARK: TOC ↔ Spine correlation

    /// Finds the TOC node that corresponds to a given spine `idref`.
    /// Strategy:
    /// 1) Resolve the manifest item by `idref` to get its `href` (e.g., "Text/chapter10.xhtml").
    /// 2) Search the TOC tree for the first node whose `href` (without fragment) either:
    ///    - contains the manifest href (case-insensitive),
    ///    - contains the last path component of the manifest href,
    ///    - or contains the `idref` itself.
    public func tocNode(forSpineIdRef idref: String) -> DCTocNode? {
        guard let manifestItem = manifest.first(where: { $0.id == idref }) else { return nil }
        let targetHref = manifestItem.href
        let targetNoFrag = dropFragment(targetHref)
        let targetLower = targetNoFrag.lowercased()
        let targetLastLower = lastPathComponent(targetNoFrag).lowercased()

        return findInTOC(toc, matching: { node in
            guard let nodeHref = node.href?.lowercased(), !nodeHref.isEmpty else { return false }
            let nodeNoFrag = dropFragment(nodeHref)
            return nodeNoFrag.contains(targetLower)
                || nodeNoFrag.contains(targetLastLower)
                || nodeNoFrag.contains(idref.lowercased())
        })
    }

    /// Returns a human-friendly chapter title for a `spine idref`, if available from the TOC.
    public func chapterTitle(forSpineIdRef idref: String) -> String? {
        return tocNode(forSpineIdRef: idref)?.label
    }

    /// Returns a human-friendly chapter title for a `spine` index.
    public func chapterTitle(forSpineIndex index: Int) -> String? {
        guard index >= 0 && index < spine.count else { return nil }
        return chapterTitle(forSpineIdRef: spine[index].idref)
    }

    /// Resolves a TOC `href` (may include a fragment) to a `spine` index, if possible.
    public func spineIndex(forTOCHref href: String?) -> Int? {
        guard let href, !href.isEmpty else { return nil }

        // Normalize target
        let targetNoFrag = dropFragment(href)
        let targetLower = targetNoFrag.lowercased()
        let targetLastLower = lastPathComponent(targetNoFrag).lowercased()

        // Build a lookup of (idref, normalizedHref, lastComponentLower) without large tuples
        let hrefByIdref: [HrefLookup] = spine.compactMap { item in
            guard let mfst = manifest.first(where: { $0.id == item.idref }) else { return nil }
            let hNoFrag = dropFragment(mfst.href)
            return HrefLookup(
                idref: item.idref,
                hrefLower: hNoFrag.lowercased(),
                lastLower: lastPathComponent(hNoFrag).lowercased()
            )
        }

        // 1. - Contains match between normalized full paths (both directions)
        if let match = hrefByIdref.first(where: { pair in
            targetLower.contains(pair.hrefLower) || pair.hrefLower.contains(targetLower)
        }) {
            return spine.firstIndex(
                where: {
                    $0.idref == match.idref
                }
            )
        }

        // 2.- Last path component match
        if let match = hrefByIdref.first(where: { pair in
            pair.lastLower == targetLastLower
                || targetLastLower.contains(pair.lastLower)
                || pair.lastLower.contains(targetLastLower)
        }) {
            return spine.firstIndex(where: { $0.idref == match.idref })
        }

        // 3.- Fallback: `idref` occurrence within the target href
        if let match = hrefByIdref.first(where: { pair in
            targetLower.contains(pair.idref.lowercased())
        }) {
            return spine.firstIndex(where: { $0.idref == match.idref })
        }

        return nil
    }

    // MARK: Metadata

    public var bookTitle: String {
        metadata.title ?? ""
    }

    // MARK: - Private helpers

    /// Depth-first search over a TOC tree using a predicate.
    private func findInTOC(_ nodes: [DCTocNode], matching predicate: (DCTocNode) -> Bool) -> DCTocNode? {
        for node in nodes {
            if predicate(node) { return node }
            if let found = findInTOC(node.children, matching: predicate) {
                return found
            }
        }
        return nil
    }

    /// Returns `href` without a trailing `#fragment`.
    private func dropFragment(_ href: String) -> String {
        if let idx = href.firstIndex(of: "#") {
            return String(href[..<idx])
        }
        return href
    }

    /// Returns the last path component of an `href`-like string.
    private func lastPathComponent(_ href: String) -> String {
        if let comp = URL(string: href)?.lastPathComponent, !comp.isEmpty {
            return comp
        }
        return href.split(separator: "/").last.map(String.init) ?? href
    }
}

// MARK: - Mocks

public extension DCEpubBook {
    static let mock: DCEpubBook = DCEpubBook(
        packagePath: "",
        metadata: .mock,
        manifest: [.mock],
        spine: [.mock],
        toc: [.mock],
        resourcesRoot: URL(
            string: "https://"
        )!
    )
}
