//
//  DCReaderView+Toolbar.swift
//  DCEpubReaderKit
//
//  Created by Josep Cerdá Penadés on 31/10/25.
//

import SwiftUI

// MARK: - Floating controls

extension DCReaderView {

    /// Close, pages left in the chapter, and bookmark.
    var topChrome: some View {
        HStack(spacing: 12) {
            DCChromeButton(systemImage: "xmark", accessibilityLabel: "Close") {
                dismiss()
            }
            Spacer(minLength: 0)
            Text(viewModel.topStatusText)
                .opacity(viewModel.hasPagePosition || viewModel.transientStatus != nil ? 1 : 0)
                .font(.subheadline)
                .foregroundStyle(viewModel.textColor.opacity(0.6))
                .lineLimit(1)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: viewModel.topStatusText)
            Spacer(minLength: 0)
            DCChromeButton(systemImage: viewModel.isCurrentPageBookmarked ? "bookmark.fill" : "bookmark",
                           accessibilityLabel: viewModel.isCurrentPageBookmarked ? "Remove Bookmark" : "Add Bookmark") {
                viewModel.toggleBookmark()
            }
        }
        .padding(.horizontal, 16)
        .frame(height: DCReaderChrome.topInset)
    }

    /// Reading progress, page number and the reader menu.
    var bottomChrome: some View {
        ZStack {
            VStack(spacing: 6) {
                ProgressView(value: viewModel.readingProgress)
                    .progressViewStyle(.linear)
                    .tint(viewModel.textColor.opacity(0.5))
                    .frame(width: 170)
                Text(viewModel.progressText)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(viewModel.textColor.opacity(0.6))
            }
            .opacity(viewModel.hasPagePosition ? 1 : 0)
            .animation(.easeInOut(duration: 0.2), value: viewModel.hasPagePosition)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Progress")
            .accessibilityValue(viewModel.progressText)

            HStack {
                Spacer()
                readerMenu
            }
        }
        .padding(.horizontal, 16)
        .frame(height: DCReaderChrome.bottomInset)
    }

    private var readerMenu: some View {
        Menu {
            ControlGroup {
                Button {
                    viewModel.toggleLineFocus()
                } label: {
                    Label("Line Guide", systemImage: "text.line.first.and.arrowtriangle.forward")
                }
                Button {
                    Task { await viewModel.share() }
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
            Button {
                viewModel.showContents = true
            } label: {
                Label("Contents", systemImage: "list.bullet.rectangle.portrait")
            }
            Button {
                viewModel.showSearch = true
            } label: {
                Label("Search Book", systemImage: "magnifyingglass")
            }
            Button {
                viewModel.showSettings = true
            } label: {
                Label("Themes & Settings", systemImage: "textformat.size")
            }
        } label: {
            DCChromeButtonLabel(systemImage: "ellipsis")
        }
        .menuOrder(.fixed)
        // Menus tint their label with the accent color; match the other floating buttons.
        .tint(.primary)
        .accessibilityLabel("Reader Menu")
    }
}

// MARK: - Sheets

extension DCReaderView {
    var sheetContentsView: some View {
        DCContentsView(
            entries: viewModel.contentsEntries,
            currentSpineIndex: viewModel.currentSelection,
            pageNumber: { viewModel.bookPage(for: $0) },
            markPageNumber: { viewModel.bookPage(for: $0) },
            highlightsProvider: {
                await viewModel.allHighlights()
            },
            onSelectEntry: { entry in
                viewModel.navigate(to: entry)
            },
            onSelectMark: { highlight in
                viewModel.navigate(to: highlight)
            }
        )
    }

    var sheetSearchView: some View {
        NavigationStack {
            DCSearchViewBuilder().build(viewModel: viewModel.searchViewModel)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Close") {
                            viewModel.showSearch = false
                        }
                    }
                }
        }
    }

    var sheetSettingsView: some View {
        DCReaderSettingsViewBuilder().build(
            fontSize: $viewModel.textSize,
            textFont: $viewModel.textFont,
            theme: $viewModel.theme,
            followsSystemAppearance: $viewModel.followsSystemAppearance,
            orientation: $viewModel.orientation,
            pageTransition: $viewModel.pageTransition,
            lineFocus: $viewModel.lineFocus,
            lineFocusStyle: $viewModel.lineFocusStyle,
            systemIsDark: viewModel.systemIsDark,
            userPreferences: viewModel.userPreferences
        )
        .presentationDetents([.height(DCReaderChrome.settingsSheetHeight), .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Controls

/// Round floating button: Liquid Glass on iOS 26 and later, a material circle before.
struct DCChromeButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            DCChromeButtonLabel(systemImage: systemImage)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct DCChromeButtonLabel: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: DCReaderChrome.buttonSize, height: DCReaderChrome.buttonSize)
            .contentShape(Circle())
            .modifier(DCGlassCircle())
    }
}

private struct DCGlassCircle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: .circle)
        } else {
            content.background(.ultraThinMaterial, in: Circle())
        }
    }
}

/// System share sheet.
struct DCShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
