//
//  DCReaderChapterView.swift
//  DCEpubReaderKit
//
//  Created by Josep Cerdá Penadés on 16/10/25.
//

import SwiftUI
import DCEpubCore

public struct DCReaderView: View {

    private enum Constants {
        static let frameSize: CGFloat = 32
    }

    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: DCReaderViewModel

    init(viewModel: DCReaderViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ZStack {
            viewModel.backgroundColor
                .ignoresSafeArea(edges: .all)
            Group {
                if viewModel.isPagedMode {
                    DCPagedReaderView(viewModel: viewModel)
                } else {
                    TabView(selection: $viewModel.currentSelection) {
                        ForEach(0..<viewModel.bookSpines.count, id: \.self) { idx in
                            Group {
                                if let chapterURL = viewModel.chapterURL(for: idx) {
                                    VStack {
                                        chapterView(chapterURL, idx: idx)
                                        .padding(.horizontal, 24)
                                        .padding(.vertical, 12)
                                        .id(viewModel.readerConfigId(for: idx))
                                        if viewModel.totalPages > 1 {
                                            Text(viewModel.pageInfo)
                                                .font(.system(size: 14))
                                                .foregroundStyle(viewModel.textColor)
                                                .opacity(viewModel.canTouch ? 1 : 0)
                                                .animation(.easeInOut(duration: 0.25),
                                                           value: viewModel.canTouch)
                                        }
                                    }
                                } else {
                                    Text("Unable to resolve chapter at spine index \(idx).")
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
            }
            .navigationBarBackButtonHidden(true)
            .toolbar {
                toolbarView
            }
            .sheet(isPresented: $viewModel.showSettings) {
                sheetSettingsView
            }
            .sheet(isPresented: $viewModel.showMarks) {
                sheetMarksView
            }
            .sheet(isPresented: $viewModel.showSearch) {
                sheetSearchView
            }
            .sheet(isPresented: $viewModel.showNote) {
                if let highlight = viewModel.pendingNoteHighlight {
                    DCNotesViewBuilder().build(
                        highlight: highlight,
                        readerContext: viewModel,
                        userPreferences: viewModel.userPreferences
                    )
                }
            }
        }
        .onChange(of: viewModel.currentSelection) { _ in
            viewModel.handleSelectionDidChange()
        }
    }

    private func chapterView(_ chapterURL: URL, idx: Int) -> some View {
        let view = DCChapterWebViewBuilder().build(
            chapterURL: chapterURL,
            readAccessURL: viewModel.opfDirectoryURL,
            spineIndex: idx,
            userPreferences: viewModel.userPreferences,
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

#if DEBUG

#Preview {
    NavigationStack {
        DCReaderViewBuilderMock.build(.mock, spineIndex: 0)
    }
}

#endif
