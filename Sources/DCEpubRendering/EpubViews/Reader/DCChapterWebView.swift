//
//  DCChapterWebView.swift
//  DCEpubReaderKit
//
//  Created by Josep Cerdá Penadés on 16/10/25.
//

import SwiftUI
import WebKit
import DCEpubCore

enum DCChapterViewAction {
    case totalPageCount(count: Int, spineIndex: Int)
    case currentPage(index: Int, totalPages: Int, spineIndex: Int)
    case canTouch(enable: Bool)
    case coordsFirstNodeOfPage(orientation: DCBookrOrientation, spineIndex: Int, coords: String, isBookMark: Bool)
    case navigateToNextChapter
    case navigateToPreviousChapter
    case showNote(highlight: DCHighlight)
    /// Open the book search for this text.
    case searchBook(query: String)
    /// Paged reader: the page on screen now belongs to `spineIndex`.
    case spineDidChange(spineIndex: Int)
    /// Size of the area a page is laid out in, for whole-book pagination.
    case pageLayout(size: CGSize)
    /// The reader tapped the page: show or hide the reader controls.
    case toggleChrome
    /// A link that isn't a footnote: another place in the book, or a web page.
    case openLink(URL)
}

struct DCChapterWebView: UIViewRepresentable {

    @ObservedObject var viewModel: DCChapterWebViewModel

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsAirPlayForMediaPlayback = false
        config.allowsInlineMediaPlayback = true
        // Like Books: the selection grows by character, across paragraphs, instead of snapping to whole blocks.
        config.selectionGranularity = .character
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        // config.preferences.javaScriptEnabled = true

        let webView = DCWebViewBuilder().build(frame: .zero,
                                               configuration: config,
                                               router: viewModel)
        if #available(iOS 14.0, *) {
            webView.configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        }
        #if DEBUG
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
        #endif
        webView.navigationDelegate = context.coordinator
        webView.scrollView.decelerationRate = .normal
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.allowsBackForwardNavigationGestures = false

        webView.scrollView.isPagingEnabled = true
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.alwaysBounceHorizontal = false
        webView.scrollView.alwaysBounceVertical = viewModel.userPreferences.getBookOrientation() == .vertical
        webView.scrollView.bounces = viewModel.userPreferences.getBookOrientation() == .vertical
        webView.scrollView.isDirectionalLockEnabled = true
        webView.scrollView.delegate = context.coordinator
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isUserInteractionEnabled = true // (scrolling stays managed by TabView disable)

        webView.setLineFocus(enabled: viewModel.userPreferences.getLineFocus(),
                             appearance: viewModel.appearance,
                             style: viewModel.userPreferences.getLineFocusStyle())
        context.coordinator.lazyWebView = webView
        context.coordinator.appliedAppearance = viewModel.appearance
        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleChromeTap(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        webView.addGestureRecognizer(tap)

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // A color-only theme change (the font weight is part of the view's id) recolors in place.
        if let applied = context.coordinator.appliedAppearance, applied != viewModel.appearance,
           let readerWebView = webView as? DCWebView {
            let appearance = viewModel.appearance
            let lineFocusStyle = readerWebView.lineFocus?.style
            context.coordinator.appliedAppearance = appearance
            Task { [weak readerWebView] in
                guard let readerWebView else { return }
                await readerWebView.applyTheme(appearance)
                if let lineFocusStyle {
                    readerWebView.setLineFocus(enabled: true, appearance: appearance, style: lineFocusStyle)
                    await readerWebView.lineFocus?.refresh(anchor: .keep)
                }
            }
        }
        // Avoid redundant loads using a tracker on the coordinator
        // (webView.url is unreliable with loadHTMLString)
        if context.coordinator.currentChapterURL != viewModel.chapterURL {
            let htmlContent = DCChapterHTMLBuilder.html(pathtofile: viewModel.chapterURL.path,
                                                        userPreferences: viewModel.userPreferences,
                                                        appearance: viewModel.appearance)
            webView.loadHTMLString(htmlContent, baseURL: viewModel.chapterURL.deletingLastPathComponent())
            context.coordinator.currentChapterURL = viewModel.chapterURL
            UIView.animate(
                withDuration: DCChapterWebView.Constants.fadeDuration
            ) {
                webView.alpha = 0
            }
            viewModel.onAction(.canTouch(enable: false))
        }
        context.coordinator.readAccessURL = viewModel.readAccessURL
    }

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(spineIndex: viewModel.spineIndex,
                                      userPreferences: viewModel.userPreferences,
                                      onAction: viewModel.onAction)
        coordinator.viewModel = viewModel
        viewModel.coordinator = coordinator
        return coordinator
    }
}
