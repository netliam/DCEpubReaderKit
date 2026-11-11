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
    static func html(pathtofile: String,
                     userPreferences: DCUserPreferencesProtocol,
                     appearance: DCReaderAppearance) -> String {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif

        guard let style = bundle.url(forResource: "Style", withExtension: "css"),
              let epubHelper = bundle.url(forResource: "EpubHelper", withExtension: "js"),
              let dohighlight = bundle.url(forResource: "dohighlight", withExtension: "js"),
              let jquery = bundle.url(forResource: "jquery-1.10.2", withExtension: "js"),
              let jqueryhighlight = bundle.url(forResource: "jquery.highlight", withExtension: "js"),
              let utils = bundle.url(forResource: "EpubUtil", withExtension: "js"),
              let contentsOfFile = pathtofile.removingPercentEncoding,
              var htmlContent = try? String(contentsOfFile: contentsOfFile, encoding: .utf8) else {
            return ""
        }

        let headInject =
        """
        <link rel='stylesheet' type='text/css' href=\"\(style)\">\n
        <script type='text/javascript' src=\"\(epubHelper)\"></script>\n
        <script type='text/javascript' src=\"\(dohighlight)\"></script>\n
        <script type='text/javascript' src=\"\(jquery)\"></script>\n
        <script type='text/javascript' src=\"\(jqueryhighlight)\"></script>\n
        <script type='text/javascript' src=\"\(utils)\"></script>\n
        \(themeStyle(for: appearance))\n
        <meta name='viewport'
            content='width=device-width,
            height=device-height,
            initial-scale=1.0,
            maximum-scale=1.0,
            user-scalable=no'>\n
        </head>
        """

        htmlContent = htmlContent.replacingOccurrences(of: "</head>", with: headInject)

        let fontName = userPreferences.getFontFamily().rawValue
        let fontSize = userPreferences.getFontSize().rawValue
        let classAttr = "class=\"\(fontName) \(fontSize) theme-\(appearance.theme.rawValue) mediaOverlayStyle0\""
        if htmlContent.range(of: "<html class=") == nil {
            htmlContent = htmlContent.replacingOccurrences(of: "<html", with: "<html \(classAttr)")
        }
        return htmlContent
    }

    /// Id of the injected theme `<style>`, so a loaded page can switch theme without reloading.
    static let themeStyleId = "dc-theme"

    private static func themeStyle(for appearance: DCReaderAppearance) -> String {
        "<style id=\"\(themeStyleId)\">\(themeCSS(for: appearance))</style>"
    }

    /// Text color and weight for the theme. The page background is drawn natively behind the
    /// (transparent) web view, so the page curl and the area around the text match.
    static func themeCSS(for appearance: DCReaderAppearance) -> String {
        // Highlight colors are light, so their text stays dark in dark themes.
        let highlightText = appearance.isDark
            ? "html .highlight-yellow, html .highlight-green, html .highlight-blue, html .highlight-pink, html .highlight-purple, html .highlight_search { color: #000 !important; }"
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
