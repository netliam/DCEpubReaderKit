//
//  DCChapterHTMLBuilder.swift
//  DCEpubReaderKit
//
//  Created by Josep Cerdá Penadés on 16/10/25.
//

import Foundation

/// Builds the chapter HTML loaded by the reader web views: injects the reader stylesheet,
/// the JS helpers, the viewport and the theme's text style, and tags `<html>` with the user's
/// font/size classes.
enum DCChapterHTMLBuilder {
    /// - Parameter fixedLayout: The chapter is a fixed-layout page: it keeps its own design (no
    ///   reader stylesheet, theme text color or font classes) and is scaled to fit the screen.
    static func html(pathtofile: String,
                     userPreferences: DCUserPreferencesProtocol,
                     appearance: DCReaderAppearance,
                     fixedLayout: Bool = false,
                     fonts: [DCReaderFont] = []) -> String {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif

        guard let style = bundle.url(forResource: "Style", withExtension: "css"),
              let utils = bundle.url(forResource: "EpubUtil", withExtension: "js"),
              let contentsOfFile = pathtofile.removingPercentEncoding,
              var htmlContent = try? String(contentsOfFile: contentsOfFile, encoding: .utf8) else {
            return ""
        }
        htmlContent = withoutBookScripts(htmlContent)

        // Links resolve against the chapter file (see `linkAction` in EpubUtil.js); the page's base
        // URL is only its folder.
        let chapterURL = URL(fileURLWithPath: contentsOfFile).absoluteString
        let chapterURLLiteral = (try? JSONSerialization.data(withJSONObject: [chapterURL]))
            .flatMap { String(data: $0, encoding: .utf8) }
            .map { String($0.dropFirst().dropLast()) } ?? "\"\""
        let fontChoice = userPreferences.getFontChoice()
        // A host font: its rules are in the layout style; built-in fonts are classes on <html>.
        let hostFont = fonts.first { $0.storageKey == fontChoice }
        let headInject =
        """
        <script>window.dcChapterURL = \(chapterURLLiteral); window.dcAllowSpreads = \(userPreferences.getTextLayout().allowsSpreads);</script>\n
        <link rel='stylesheet' type='text/css' href=\"\(style)\">\n
        <script type='text/javascript' src=\"\(utils)\"></script>\n
        \(themeStyle(for: appearance))\n
        <style id="\(layoutStyleId)">\(userPreferences.getTextLayout().css)\n\(hostFont?.css ?? "")</style>\n
        <meta name='viewport'
            content='width=device-width,
            height=device-height,
            initial-scale=1.0,
            maximum-scale=1.0,
            user-scalable=no'>\n
        </head>
        """

        if fixedLayout {
            return fixedLayoutHTML(htmlContent, chapterURLLiteral: chapterURLLiteral,
                                   scripts: [utils])
        }

        htmlContent = htmlContent.replacingOccurrences(of: "</head>", with: headInject)

        let fontName = hostFont == nil ? userPreferences.getFontFamily().rawValue : ""
        let fontSize = userPreferences.getFontSize().rawValue
        let classAttr = "class=\"\(fontName) \(fontSize) theme-\(appearance.theme.rawValue) mediaOverlayStyle0\""
        if htmlContent.range(of: "<html class=") == nil {
            htmlContent = htmlContent.replacingOccurrences(of: "<html", with: "<html \(classAttr)")
        }
        return htmlContent
    }

    /// The chapter without its own scripts and inline event handlers: they'd run with the reader's
    /// message handlers (open links, show menus). The reader adds its handlers at runtime.
    static func withoutBookScripts(_ html: String) -> String {
        var html = html.replacingOccurrences(of: #"(?s)<script\b[^>]*/>|<script\b.*?</script\s*>"#, with: "",
                                             options: [.regularExpression, .caseInsensitive])
        // Only inside tags, so prose like "online=…" is left alone; one handler per pass.
        let handler = #"(<[a-zA-Z][^>]*?)\son[a-zA-Z]+\s*=\s*("[^"]*"|'[^']*'|[^\s>]+)"#
        while html.range(of: handler, options: .regularExpression) != nil {
            html = html.replacingOccurrences(of: handler, with: "$1", options: .regularExpression)
        }
        return html
    }

    // MARK: Fixed layout

    /// A fixed-layout page with the reader's scripts and the highlight styles, sized by its own
    /// viewport (see `applyFixedLayout` in EpubUtil.js).
    private static func fixedLayoutHTML(_ html: String, chapterURLLiteral: String, scripts: [URL]) -> String {
        let size = fixedLayoutSize(in: html)
        // The page's viewport would make the web view zoom it; the reader scales it itself.
        var html = html.replacingOccurrences(of: #"name\s*=\s*["']viewport["']"#,
                                             with: "name=\"dc-original-viewport\"",
                                             options: [.regularExpression, .caseInsensitive])
        let scriptTags = scripts.map { "<script type='text/javascript' src=\"\($0)\"></script>" }.joined(separator: "\n")
        let inject = """
        <script>window.dcChapterURL = \(chapterURLLiteral); window.dcFixedLayout = { width: \(size.width), height: \(size.height) };</script>
        \(scriptTags)
        <style>\(fixedLayoutCSS)</style>
        <meta name='viewport' content='width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no'>
        </head>
        """
        html = html.replacingOccurrences(of: "</head>", with: inject)
        return html
    }

    /// The page size a fixed-layout page declares: its viewport `width`/`height`, else an SVG
    /// `viewBox`. Zero when it has neither; the page is measured instead.
    static func fixedLayoutSize(in html: String) -> (width: Int, height: Int) {
        func number(_ pattern: String) -> Int? {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  let range = Range(match.range(at: 1), in: html) else { return nil }
            return Double(html[range]).map { Int($0.rounded()) }
        }
        let viewport = #"<meta[^>]*name\s*=\s*["']viewport["'][^>]*content\s*=\s*["'][^"']*"#
        let viewportReversed = #"<meta[^>]*content\s*=\s*["'][^"']*"#
        if let width = number(viewport + #"width\s*=\s*([0-9.]+)"#) ?? number(viewportReversed + #"width\s*=\s*([0-9.]+)[^>]*name\s*=\s*["']viewport"#),
           let height = number(viewport + #"height\s*=\s*([0-9.]+)"#) ?? number(viewportReversed + #"height\s*=\s*([0-9.]+)[^>]*name\s*=\s*["']viewport"#) {
            return (width, height)
        }
        if let width = number(#"<svg[^>]*viewBox\s*=\s*["'][-0-9.]+[ ,]+[-0-9.]+[ ,]+([0-9.]+)"#),
           let height = number(#"<svg[^>]*viewBox\s*=\s*["'][-0-9.]+[ ,]+[-0-9.]+[ ,]+[0-9.]+[ ,]+([0-9.]+)"#) {
            return (width, height)
        }
        return (0, 0)
    }

    /// Highlights and search marks on fixed-layout pages (the rest of Style.css would change
    /// the page's design).
    private static let fixedLayoutCSS = """
    .highlight_search { background: rgba(173, 216, 255, 0.6); }
    .highlight-highlight {
        background: var(--dc-hl, #FFEB6B);
        background: color-mix(in srgb, var(--dc-hl, #FFEB6B) 60%, transparent);
    }
    .highlight-underline { border-bottom: 2px solid var(--dc-hl, #F02814); }
    .highlight-squiggly { text-decoration: underline wavy var(--dc-hl, #F02814); text-decoration-skip-ink: none; }
    .highlight-strikethrough { text-decoration: line-through var(--dc-hl, #F02814); text-decoration-thickness: 2px; }
    """

    /// Id of the injected line spacing and justification `<style>`.
    static let layoutStyleId = "dc-layout"

    /// Id of the injected theme `<style>`, so a loaded page can switch theme without reloading.
    static let themeStyleId = "dc-theme"

    private static func themeStyle(for appearance: DCReaderAppearance) -> String {
        "<style id=\"\(themeStyleId)\">\(themeCSS(for: appearance))</style>"
    }

    /// Text color and weight for the theme. The page background is drawn natively behind the
    /// (transparent) web view, so the page curl and the area around the text match.
    static func themeCSS(for appearance: DCReaderAppearance) -> String {
        // Highlight colors are light, so their text stays dark in dark themes.
        let highlightText = appearance.hasDarkBackground
            ? "html .highlight-highlight, html .highlight_search { color: #000 !important; }"
            : ""
        return """
        html, body, p, div, span, li, td, th, blockquote, h1, h2, h3, h4, h5, h6 {
            color: \(appearance.cssTextColor) !important;
        }
        body { font-weight: \(appearance.theme.fontWeight) !important; }
        /* Pagination justifies body text; headings shouldn't inherit that. Zero specificity, so the book's own rules still win. */
        :where(h1, h2, h3, h4, h5, h6) { text-align: left; }
        \(highlightText)
        """
    }
}
