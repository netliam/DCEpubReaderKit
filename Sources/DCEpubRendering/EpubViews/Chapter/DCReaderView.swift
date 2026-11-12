//
//  DCReaderChapterView.swift
//  DCEpubReaderKit
//
//  Created by Josep Cerdá Penadés on 16/10/25.
//

import SwiftUI
import DCEpubCore

/// The reader, laid out like Apple Books: pages fill the screen and a few floating controls sit
/// on top of them (close, pages left, bookmark; progress and a menu at the bottom).
public struct DCReaderView: View {

    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @ObservedObject var viewModel: DCReaderViewModel

    init(viewModel: DCReaderViewModel) {
        self.viewModel = viewModel
    }

    /// The full controls show when toggled on, and always with VoiceOver (it can't tap to reveal them).
    var showsChrome: Bool {
        viewModel.isChromeVisible || voiceOverEnabled
    }

    public var body: some View {
        ZStack {
            viewModel.backgroundColor
                .ignoresSafeArea()
            if viewModel.isPagedMode {
                // Edge to edge, so the page turn covers the whole screen. Pages inset their text
                // by the safe area plus `DCReaderChrome` to stay clear of the controls.
                DCPagedReaderView(viewModel: viewModel)
                    .ignoresSafeArea()
            } else {
                scrollingReader
            }
        }
        .overlay(alignment: .top) {
            topChrome
        }
        .overlay(alignment: .bottom) {
            bottomChrome
        }
        .background(DCWindowSceneReader { viewModel.windowScene = $0 })
        .background(keyboardShortcuts)
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $viewModel.showSettings) {
            sheetSettingsView
        }
        .sheet(isPresented: $viewModel.showContents) {
            sheetContentsView
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $viewModel.showSearch) {
            sheetSearchView
        }
        .sheet(isPresented: $viewModel.showShare) {
            DCShareSheet(items: [viewModel.shareText])
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $viewModel.showNote) {
            if let highlight = viewModel.pendingNoteHighlight {
                DCNotesViewBuilder().build(
                    highlight: highlight,
                    readerContext: viewModel,
                    userPreferences: viewModel.userPreferences,
                    appearance: viewModel.appearance
                )
            }
        }
        .onAppear {
            viewModel.systemIsDark = colorScheme == .dark
            viewModel.readerDidAppear()
        }
        .onChange(of: colorScheme) { newValue in
            viewModel.systemIsDark = newValue == .dark
        }
        .onChange(of: viewModel.currentSelection) { _ in
            viewModel.handleSelectionDidChange()
        }
        .task {
            await viewModel.loadBookmarks()
        }
        .onDisappear {
            viewModel.readerDidDisappear()
        }
    }

    /// Vertical (scrolling) mode: one scrolling web view per chapter.
    private var scrollingReader: some View {
        TabView(selection: $viewModel.currentSelection) {
            ForEach(0..<viewModel.bookSpines.count, id: \.self) { idx in
                Group {
                    if let chapterURL = viewModel.chapterURL(for: idx) {
                        chapterView(chapterURL, idx: idx)
                            .padding(.horizontal, viewModel.textLayout.margins.inset)
                            .padding(.top, DCReaderChrome.topInset)
                            .padding(.bottom, DCReaderChrome.bottomInset)
                            .id(viewModel.readerConfigId(for: idx))
                    } else {
                        Text(String(format: L("Unable to open section %lld."), idx + 1))
                            .foregroundStyle(viewModel.textColor)
                            .padding()
                    }
                }
                .tag(idx)
                .gesture(viewModel.gesture)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    private func chapterView(_ chapterURL: URL, idx: Int) -> some View {
        let view = DCChapterWebViewBuilder().build(
            chapterURL: chapterURL,
            readAccessURL: viewModel.opfDirectoryURL,
            spineIndex: idx,
            userPreferences: viewModel.userPreferences,
            appearance: viewModel.appearance,
            readerContext: viewModel
        ) { [weak viewModel] action in
            viewModel?.handle(action, chapterURL: chapterURL)
        }
        return view
            .onAppear { [weak viewModel] in
                viewModel?.registerChapterViewModel(view.viewModel, for: idx)
            }
    }
}

// MARK: - Closing and keyboard

extension DCReaderView {
    /// Closes the reader: the host's `onClose` (its own window), or dismiss (pushed or presented).
    func close() {
        if let onClose = viewModel.configuration.onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    /// ⌘F searches and Esc closes. Page turning keys are on the pager (`DCPagedReaderController`).
    var keyboardShortcuts: some View {
        ZStack {
            if viewModel.configuration.showsSearch {
                Button("") { viewModel.showSearch = true }
                    .keyboardShortcut("f", modifiers: .command)
            }
            Button("") { close() }
                .keyboardShortcut(.cancelAction)
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Reports the window scene the reader is shown in, as it moves between windows.
struct DCWindowSceneReader: UIViewRepresentable {
    let onChange: (UIWindowScene?) -> Void

    func makeUIView(context: Context) -> View {
        let view = View()
        view.onChange = onChange
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: View, context: Context) {
        view.onChange = onChange
    }

    final class View: UIView {
        var onChange: ((UIWindowScene?) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            onChange?(window?.windowScene)
        }
    }
}

#if DEBUG

#Preview {
    NavigationStack {
        DCReaderViewBuilderMock.build(.mock, spineIndex: 0)
    }
}

#endif
