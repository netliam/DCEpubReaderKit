//
//  DCOPFParser.swift
//  DCEpubReaderKit
//
//  Created by Josep Cerdá Penadés on 15/10/25.
//

import Foundation
import DCEpubCore

/// Parses an OPF package file and builds an `OPFPackage` model:
/// - Reads `<package version="...">`
/// - Parses `<metadata>` (dc:* and selected <meta> tags)
/// - Parses `<manifest>` items
/// - Parses `<spine>` itemrefs
/// - Parses `<guide>` references
/// - Resolves cover image using EPUB2/EPUB3 conventions and sensible fallbacks
public final class DCOPFParser: NSObject, XMLParserDelegate {

    // MARK: Public cover resolution outputs

    /// HREF of the cover image, exactly as declared in the OPF manifest (relative to OPF).
    public private(set) var coverImageHref: String?

    /// Absolute URL to the cover image on disk (resolved as `opfURL.deletingLastPathComponent() + href`).
    public private(set) var coverImageURL: URL?

    // MARK: Private state

    private let opfURL: URL
    private var pkg: DCOPFPackage
    private var textBuffer = String()

    // Section flags
    private var inMetadata = false
    private var inManifest = false
    private var inSpine = false
    private var inGuide = false

    // EPUB2 cover hint: <meta name="cover" content="cover-image-id-or-href" />
    private var pendingCoverRef: String?

    private var currentMetaProperty: String?

    /// Element depth (1 = `<package>`) and how many of the package's child elements have started.
    private var depth = 0
    private var packageChildren = 0

    // MARK: Init

    public init(opfURL: URL) {
        self.opfURL = opfURL
        self.pkg = DCOPFPackage(
            opfURL: opfURL,
            metadata: DCOPFMetadata(),
            manifest: [],
            spine: [],
            guide: []
        )
    }

    // MARK: API

    /// Parses the OPF at `opfURL` and returns a populated `DCOPFPackage`.
    /// - Throws: `DCEpubError.parseError` if the file can't be opened or isn't valid XML.
    public func parse() throws -> DCOPFPackage {
        guard let parser = XMLParser(contentsOf: opfURL) else {
            throw DCEpubError.parseError("Unable to open OPF at \(opfURL.path).")
        }

        // Reset one-shot state
        textBuffer.removeAll(keepingCapacity: false)
        inMetadata = false
        inManifest = false
        inSpine = false
        inGuide = false
        pendingCoverRef = nil
        depth = 0
        packageChildren = 0
        coverImageHref = nil
        coverImageURL = nil

        parser.delegate = self
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes = true
        parser.shouldResolveExternalEntities = false

        guard parser.parse() else {
            let reason = parser.parserError?.localizedDescription ?? "Unknown OPF parsing error."
            throw DCEpubError.parseError(reason)
        }
        return pkg
    }
}

// MARK: - XMLParserDelegate - attributes

extension DCOPFParser {
    public func parser(_ parser: XMLParser,
                       didStartElement name: String,
                       namespaceURI: String?,
                       qualifiedName qName: String?,
                       attributes attributeDict: [String: String] = [:]) {
        textBuffer.removeAll(keepingCapacity: true)
        let lowerName = name.lowercased()
        depth += 1
        if depth == 2 {
            packageChildren += 1
            if lowerName == "spine" { pkg.spineStep = 2 * packageChildren }
        }

        // Secciones: solo setea flags aquí (sin lógica adicional)
        switch lowerName {
        case "metadata": inMetadata = true
        case "manifest": inManifest = true
        case "spine":    inSpine = true
        case "guide":    inGuide = true
        default: break
        }

        // Deriva la lógica detallada a helpers para mantener baja la complejidad
        handlePackageStartIfNeeded(lowerName: lowerName, attributes: attributeDict)
        handleMetadataStartIfNeeded(lowerName: lowerName, attributes: attributeDict)
        handleManifestStartIfNeeded(lowerName: lowerName, attributes: attributeDict)
        handleSpineStartIfNeeded(lowerName: lowerName, attributes: attributeDict)
        handleGuideStartIfNeeded(lowerName: lowerName, attributes: attributeDict)
    }

    private func handlePackageStartIfNeeded(lowerName: String,
                                            attributes: [String: String]) {
        guard lowerName == "package" else { return }
        if let version = attributes["version"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !version.isEmpty {
            pkg.metadata.version = version
        }
    }

    private func handleMetadataStartIfNeeded(lowerName: String,
                                             attributes: [String: String]) {
        guard inMetadata else { return }

        if lowerName == "meta" {
            // Guarda el property para usarlo en didEndElement (p.ej. dcterms:modified)
            currentMetaProperty = attributes["property"]?.lowercased()

            // Pista EPUB2: <meta name="cover" content="cover-id-or-href" />
            if let metaName = attributes["name"]?.lowercased(), metaName == "cover" {
                let value = attributes["content"]?.trimmingCharacters(in: .whitespacesAndNewlines)
                pendingCoverRef = value
            }
        }
    }

    private func handleManifestStartIfNeeded(lowerName: String,
                                             attributes: [String: String]) {
        guard inManifest, lowerName == "item" else { return }
        let item = DCManifestItem(
            id: attributes["id"] ?? UUID().uuidString,
            href: attributes["href"] ?? "",
            mediaType: attributes["media-type"] ?? attributes["mediaType"] ?? "",
            properties: attributes["properties"]
        )
        pkg.manifest.append(item)
    }

    private func handleSpineStartIfNeeded(lowerName: String,
                                          attributes: [String: String]) {
        guard inSpine, lowerName == "itemref" else { return }
        let idref = attributes["idref"] ?? ""
        let linear = (attributes["linear"] ?? "yes").lowercased() != "no"
        pkg.spine.append(DCSpineItem(idref: idref, linear: linear, properties: attributes["properties"]))
    }

    private func handleGuideStartIfNeeded(lowerName: String,
                                          attributes: [String: String]) {
        guard inGuide, lowerName == "reference" else { return }
        if let href = attributes["href"] {
            pkg.guide.append(DCGuideRef(type: attributes["type"], title: attributes["title"], href: href))
        }
    }
}

// MARK: - XMLParserDelegate
// MARK: - func parser(_ parser: XMLParser, foundCharacters string: String)
// MARK: - func parser(_ parser: XMLParser, didEndElement...

extension DCOPFParser {
    public func parser(_ parser: XMLParser, foundCharacters string: String) {
        textBuffer.append(string)
    }

    public func parser(_ parser: XMLParser,
                       didEndElement name: String,
                       namespaceURI: String?,
                       qualifiedName qName: String?) {

        let lower = name.lowercased()
        depth -= 1

        if inMetadata {
            handleMetadataEndElement(lower: lower, qName: qName, namespaceURI: namespaceURI)
        }

        if isSectionClosing(lower) {
            handleSectionClosure(lower)
        }

        textBuffer.removeAll(keepingCapacity: true)
    }

    /// True if element belongs to Dublin Core (by namespace URI or qName prefix).
    private func isDublinCore(namespaceURI: String?, qName: String?) -> Bool {
        let isDCNamespace = (namespaceURI == "http://purl.org/dc/elements/1.1/")
        let isDCByQName = (qName?.lowercased().hasPrefix("dc:") ?? false)
        return isDCNamespace || isDCByQName
    }

    private func handleMetadataEndElement(lower: String,
                                          qName: String?,
                                          namespaceURI: String?) {
        if isDublinCore(namespaceURI: namespaceURI, qName: qName) {
            handleDublinCoreEnd(lower: lower)
            return
        }

        // Non-DC: handle <meta ...> endings (e.g., dcterms:modified)
        guard lower == "meta" else { return }
        handleMetaPropertyEnd()
    }

    /// Handles end of Dublin Core elements without branching via switch.
    /// Uses a lookup table to keep cyclomatic complexity low.
    private func handleDublinCoreEnd(lower: String) {
        let trimmed = textBuffer.trimmed()
        let raw = textBuffer  // keep raw for fields that may contain HTML (e.g., description)

        let actions: [String: () -> Void] = [
            "title": { self.pkg.metadata.title = coalesce(self.pkg.metadata.title, with: trimmed) },
            "creator": { if !trimmed.isEmpty { self.pkg.metadata.creators.append(trimmed) } },
            "language": { self.pkg.metadata.language = coalesce(self.pkg.metadata.language, with: trimmed) },
            "identifier": { if !trimmed.isEmpty { self.pkg.metadata.identifiers.append(trimmed) } },
            "date": { self.pkg.metadata.date = coalesce(self.pkg.metadata.date, with: trimmed) },
            "publisher": { self.pkg.metadata.publisher = coalesce(self.pkg.metadata.publisher, with: trimmed) },
            "description": {
                self.pkg.metadata.descriptionHTML = coalesce(self.pkg.metadata.descriptionHTML, with: raw)
            }
        ]

        actions[lower]?()
    }

    /// Finalizes non-DC <meta> elements (e.g., <meta property=\"dcterms:modified\">…</meta>)
    private func handleMetaPropertyEnd() {
        defer { currentMetaProperty = nil }

        guard let property = currentMetaProperty else { return }

        if property == "rendition:layout" {
            let layout = textBuffer.trimmed()
            if !layout.isEmpty {
                pkg.metadata.renditionLayout = layout
            }
        }

        if property == "dcterms:modified" {
            let modified = textBuffer.trimmed()
            if !modified.isEmpty, (pkg.metadata.date ?? "").isEmpty {
                pkg.metadata.date = modified
            }
        }
    }

    private func isSectionClosing(_ lower: String) -> Bool {
        return lower == "metadata" || lower == "manifest" || lower == "spine" || lower == "guide"
    }

    private func handleSectionClosure(_ lower: String) {
        switch lower {
        case "metadata":
            inMetadata = false

        case "manifest":
            inManifest = false
            applyPendingCoverHintIfNeeded()
            resolveCoverImageIfNeeded()
            materializeCoverURLIfAvailable()

        case "spine":
            inSpine = false

        case "guide":
            inGuide = false

        default:
            break
        }
    }

    private func applyPendingCoverHintIfNeeded() {
        guard let ref = pendingCoverRef?.trimmed(), !ref.isEmpty else { return }

        if let idxById = pkg.manifest.firstIndex(where: { $0.id == ref }) {
            var manifest = pkg.manifest[idxById]
            let existing = (manifest.properties ?? "")
            if !existing.lowercased().contains("cover-image") {
                manifest.properties = existing.isEmpty ? "cover-image" : existing + " cover-image"
                pkg.manifest[idxById] = manifest
            }
        } else if let idxByHref = pkg.manifest.firstIndex(where: { $0.href == ref || $0.href.hasSuffix(ref) }) {
            var manifest = pkg.manifest[idxByHref]
            let existing = (manifest.properties ?? "")
            if !existing.lowercased().contains("cover-image") {
                manifest.properties = existing.isEmpty ? "cover-image" : existing + " cover-image"
                pkg.manifest[idxByHref] = manifest
            }
        }

        pendingCoverRef = nil
    }

    private func resolveCoverImageIfNeeded() {
        guard coverImageHref == nil else { return }

        // 1) Prefer item flagged as cover-image (EPUB3)
        if let coverItem = pkg.manifest.first(where: { ($0.properties ?? "").lowercased().contains("cover-image") }) {
            coverImageHref = coverItem.href
            return
        }

        // 2) Fallback: metadata.coverHint (if your model uses it)
        if let hint = pkg.metadata.coverHint, !hint.isEmpty {
            if let item = pkg.manifest.first(where: { $0.id == hint || $0.href == hint || $0.href.hasSuffix(hint) }) {
                coverImageHref = item.href
                return
            }
        }

        // 3) Heuristic: any image whose id or href contains "cover"
        if let item = pkg.manifest.first(where: {
            isImageMediaType($0.mediaType, href: $0.href) &&
            ($0.id.lowercased().contains("cover") || $0.href.lowercased().contains("cover"))
        }) {
            coverImageHref = item.href
        }
    }

    private func materializeCoverURLIfAvailable() {
        guard let href = coverImageHref, !href.isEmpty else { return }
        let base = opfURL.deletingLastPathComponent()
        coverImageURL = base.appendingPathComponent(href).standardizedFileURL
        // Optionally expose as hint
        pkg.metadata.coverHint = coverImageURL?.path
    }
}

// MARK: - Helpers

/// Detect whether a manifest entry is an image, being permissive with bad or missing media-type.
private func isImageMediaType(_ mediaType: String, href: String) -> Bool {
    let media = mediaType.lowercased()
    if media.hasPrefix("image/") { return true }

    // Some EPUBs have incorrect or missing media-type; infer from extension.
    let ext = (href as NSString).pathExtension.lowercased()
    let known: Set<String> = ["jpg", "jpeg", "png", "gif", "svg", "webp", "heic", "heif", "avif"]
    return known.contains(ext)
}

/// If `new` has non-empty trimmed content and `current` is empty, return `new`; otherwise keep `current`.
private func coalesce(_ current: String?, with new: String) -> String {
    let trimmed = new.trimmed()
    if trimmed.isEmpty { return current ?? "" }
    return (current?.isEmpty ?? true) ? trimmed : (current ?? "")
}

private extension XMLParser {
    /// Access to the current element's attributes in `didEndElement` (best-effort; nil if unavailable).
    var attributeDict: [String: String]? { return nil /* XMLParser does not expose this here; kept for clarity */ }
}

private extension String {
    func trimmed() -> String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
