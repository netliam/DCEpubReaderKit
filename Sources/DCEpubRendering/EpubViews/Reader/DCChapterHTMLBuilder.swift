//
//  DCChapterHTMLBuilder.swift
//  DCEpubReaderKit
//
//  Created by Josep Cerdá Penadés on 16/10/25.
//

import Foundation

/// Builds the chapter HTML loaded by the reader web views: injects the reader stylesheet,
/// the JS helpers and the viewport, and tags `<html>` with the user's font/size/theme classes.
enum DCChapterHTMLBuilder {
    static func html(pathtofile: String, userPreferences: DCUserPreferencesProtocol) -> String {
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
        let nightOrDayMode = userPreferences.getDesktopMode().mode
        let classAttr = "class=\"\(fontName) \(fontSize) \(nightOrDayMode) mediaOverlayStyle0\""
        if htmlContent.range(of: "<html class=") == nil {
            htmlContent = htmlContent.replacingOccurrences(of: "<html", with: "<html \(classAttr)")
        }
        return htmlContent
    }
}
