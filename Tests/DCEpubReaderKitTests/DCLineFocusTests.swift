//
//  DCLineFocusTests.swift
//  DCEpubReaderKit
//
//  Created by Liam Smith-Gales on 11/11/26.
//

import Foundation
import Testing
import UIKit
import WebKit
@testable import DCEpubRendering

@Suite("Line focus geometry")
struct DCLineFocusGeometryTests {

    @Test func maskIsClearOnlyAroundTheBand() {
        let locations = DCLineFocusController.maskLocations(band: 200...240, height: 800, feather: 20)
            .map(\.doubleValue)
        // A 20 pt feather straddles each band edge: 10 pt outside, 10 pt inside.
        let expected: [Double] = [0, 190, 210, 230, 250, 800].map { $0 / 800 }
        #expect(locations == expected)
    }

    @Test func maskStopsStayInsideTheViewAtTheEdges() {
        let top = DCLineFocusController.maskLocations(band: 0...30, height: 600, feather: 14).map(\.doubleValue)
        let bottom = DCLineFocusController.maskLocations(band: 580...600, height: 600, feather: 14).map(\.doubleValue)
        #expect(top.allSatisfy { (0...1).contains($0) })
        #expect(bottom.allSatisfy { (0...1).contains($0) })
        #expect(top == top.sorted())
        #expect(bottom == bottom.sorted())
    }

    @Test func bandStopsHalfwayToTheNeighbouringLines() {
        let bounds = CGRect(x: 0, y: 0, width: 300, height: 500)
        // 20 pt lines, 10 pt apart.
        let lines = [CGRect(x: 0, y: 100, width: 200, height: 20),
                     CGRect(x: 0, y: 130, width: 200, height: 20),
                     CGRect(x: 0, y: 160, width: 200, height: 20)]
        let middle = DCLineFocusController.band(for: 1, in: lines, bounds: bounds)
        #expect(middle == 125...155, "never reaches into the lines above or below")

        // The first and last lines mirror their only neighbour.
        #expect(DCLineFocusController.band(for: 0, in: lines, bounds: bounds) == 95...125)
        #expect(DCLineFocusController.band(for: 2, in: lines, bounds: bounds) == 155...185)
    }

    @Test func bandIsClampedToTheBoundsAndToALoneLine() {
        let bounds = CGRect(x: 0, y: 0, width: 300, height: 500)
        let atTop = DCLineFocusController.band(for: 0, in: [CGRect(x: 0, y: 0, width: 200, height: 20)], bounds: bounds)
        #expect(atTop.lowerBound == 0)
        // A lone line gets a small default padding; a wide gap never pads more than 40% of the line.
        let lone = DCLineFocusController.band(for: 0, in: [CGRect(x: 0, y: 100, width: 200, height: 20)], bounds: bounds)
        #expect(lone == 96...124)
        let spaced = [CGRect(x: 0, y: 100, width: 200, height: 20), CGRect(x: 0, y: 300, width: 200, height: 20)]
        #expect(DCLineFocusController.band(for: 0, in: spaced, bounds: bounds) == 92...128)
    }

    @Test func tapPicksTheLineUnderItOrTheNearest() {
        let lines = [CGRect(x: 0, y: 0, width: 100, height: 20),
                     CGRect(x: 0, y: 30, width: 100, height: 20),
                     CGRect(x: 0, y: 60, width: 100, height: 20)]
        #expect(DCLineFocusController.lineIndex(at: 35, in: lines) == 1)
        #expect(DCLineFocusController.lineIndex(at: 26, in: lines) == 1, "gap between lines goes to the nearest")
        #expect(DCLineFocusController.lineIndex(at: 400, in: lines) == 2)
        #expect(DCLineFocusController.lineIndex(at: 10, in: []) == nil)
    }
}

extension WebKitBackedTests {

@MainActor
@Suite("Line focus")
struct DCLineFocusWebTests {

    static let light = DCReaderAppearance(theme: .original, isDark: false)
    static let dark = DCReaderAppearance(theme: .original, isDark: true)

    private static let epubUtilURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("../../Sources/DCEpubRendering/Resources/EpubUtil.js")
        .standardizedFileURL

    /// A web view in a window (so it renders) with EpubUtil.js and `body` loaded.
    private func loadPage(body: String) async throws -> (DCWebView, UIWindow) {
        let script = try String(contentsOf: Self.epubUtilURL, encoding: .utf8)
        let html = """
        <html><head>
        <meta name='viewport' content='width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no'>
        <style>body { margin: 0; font: 16px/24px -apple-system; }</style>
        <script>\(script)</script></head><body>\(body)</body></html>
        """
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let webView = DCWebView(frame: window.bounds, configuration: WKWebViewConfiguration())
        window.addSubview(webView)
        window.makeKeyAndVisible()
        let loader = NavigationWaiter()
        webView.navigationDelegate = loader
        try await loader.load(html, in: webView)
        await webView.waitForLayout()
        return (webView, window)
    }

    @Test func measuresOneRectPerRenderedLine() async throws {
        let (webView, window) = try await loadPage(body: "<p>One <b>bold</b> line<br>Two<br>Three</p>")
        defer { window.isHidden = true }
        webView.setLineFocus(enabled: true, appearance: Self.light, style: .guide)
        let lineFocus = try #require(webView.lineFocus)

        await lineFocus.refresh(anchor: .first)

        // The <b> fragment is merged into its line rather than counted separately.
        #expect(lineFocus.lines.count == 3)
        #expect(lineFocus.lines.map(\.minY) == lineFocus.lines.map(\.minY).sorted())
        for (upper, lower) in zip(lineFocus.lines, lineFocus.lines.dropFirst()) {
            #expect(upper.maxY <= lower.minY + 0.5, "lines must not overlap")
        }
        #expect(lineFocus.focusedIndex == 0)
    }

    @Test func anchorsOnTheLastLineOrTheSearchMatch() async throws {
        let (webView, window) = try await loadPage(body: "<p>Alpha<br>Beta<br>Gamma whale<br>Delta</p>")
        defer { window.isHidden = true }
        webView.setLineFocus(enabled: true, appearance: Self.dark, style: .blur)
        let lineFocus = try #require(webView.lineFocus)

        await lineFocus.refresh(anchor: .last)
        #expect(lineFocus.focusedIndex == 3)

        _ = try await webView.evaluateJavaScript("highlightSearchOccurrence('whale', 0, false)")
        await lineFocus.refresh(anchor: .searchMatch)
        #expect(lineFocus.focusedIndex == 2)
    }

    @Test func skipsTextOutsideTheViewport() async throws {
        // 40 lines of 24px in a 480pt-tall view: only the first ~20 are on screen.
        let body = (1...40).map { "Line \($0)" }.joined(separator: "<br>")
        let (webView, window) = try await loadPage(body: "<p>\(body)</p>")
        defer { window.isHidden = true }
        webView.setLineFocus(enabled: true, appearance: Self.light, style: .guide)
        let lineFocus = try #require(webView.lineFocus)

        await lineFocus.refresh(anchor: .first)
        #expect((18...21).contains(lineFocus.lines.count), "got \(lineFocus.lines.count) lines")
        #expect(lineFocus.lines.allSatisfy { $0.minY < 480 })
    }

    /// Pages attach line focus before their web view has a size. The overlay must still end up
    /// covering the page, with the mask sized to it (it used to stay zero-sized, hiding the effect).
    @Test func effectCoversTheViewWhenAttachedBeforeLayout() async throws {
        let (sized, window) = try await loadPage(body: "<p>One<br>Two<br>Three</p>")
        defer { window.isHidden = true }
        let webView = DCWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.setLineFocus(enabled: true, appearance: Self.light, style: .guide)
        window.addSubview(webView)
        webView.frame = sized.frame
        let loader = NavigationWaiter()
        webView.navigationDelegate = loader
        let script = try String(contentsOf: Self.epubUtilURL, encoding: .utf8)
        try await loader.load("<html><head><meta name='viewport' content='width=device-width, initial-scale=1.0'><style>body{margin:0;font:16px/24px -apple-system;}</style><script>\(script)</script></head><body><p>One<br>Two<br>Three</p></body></html>", in: webView)
        await webView.waitForLayout()
        let lineFocus = try #require(webView.lineFocus)

        await lineFocus.refresh(anchor: .first)
        webView.layoutIfNeeded()

        let overlay = try #require(webView.subviews.compactMap { $0 as? DCLineFocusOverlayView }.first)
        // Extends past the web view so the effect has no visible edge.
        #expect(overlay.frame == DCLineFocusOverlayView.frame(covering: webView.bounds))
        #expect(overlay.frame.contains(webView.bounds))
        #expect(overlay.maskLocations.map(\.doubleValue) != [0, 0, 0, 0, 0, 1], "mask still covers everything")
        let outline = try #require(overlay.outlineFrame)
        let line = try #require(lineFocus.lines.first)
        #expect(outline.minY <= line.minY && outline.maxY >= line.maxY, "outline surrounds the focused line")
    }

    @Test func guideOutlinesTheLineAndBlurDoesNot() async throws {
        let (webView, window) = try await loadPage(body: "<p>One<br>Two</p><p>" + String(repeating: "Lorem ipsum dolor sit amet, consectetur adipiscing elit. ", count: 30) + "</p>")
        defer { window.isHidden = true }

        webView.setLineFocus(enabled: true, appearance: Self.light, style: .guide)
        await webView.lineFocus?.refresh(anchor: .first)
        let guide = try #require(webView.subviews.compactMap { $0 as? DCLineFocusOverlayView }.first)
        #expect(guide.style == .guide)
        #expect(guide.outlineFrame != nil)
        #expect(!guide.subviews.contains { $0 is UIVisualEffectView })

        // The test page's text is black, so blur it on the light (white) page.
        webView.setLineFocus(enabled: true, appearance: Self.light, style: .blur)
        await webView.lineFocus?.refresh(anchor: .first)
        let blur = try #require(webView.subviews.compactMap { $0 as? DCLineFocusOverlayView }.first)
        #expect(blur.style == .blur)
        #expect(blur.outlineFrame == nil)
        // A blurred snapshot in the theme's colors, not a tinted system material.
        #expect(!blur.subviews.contains { $0 is UIVisualEffectView })
        // The test runner has no host app, so WebKit doesn't draw and snapshots are blank here;
        // the content of the blur can only be checked in the app.
        #expect(blur.blurredImage != nil)
        #expect(webView.subviews.filter { $0 is DCLineFocusOverlayView }.count == 1, "switching style replaces the overlay")
    }

    @Test func disablingRemovesTheBlur() async throws {
        let (webView, window) = try await loadPage(body: "<p>Text</p>")
        defer { window.isHidden = true }
        webView.setLineFocus(enabled: true, appearance: Self.light, style: .guide)
        #expect(webView.subviews.contains { $0 is DCLineFocusOverlayView })

        webView.setLineFocus(enabled: false, appearance: Self.light, style: .guide)
        #expect(webView.lineFocus == nil)
        #expect(!webView.subviews.contains { $0 is DCLineFocusOverlayView })
    }
}
}
