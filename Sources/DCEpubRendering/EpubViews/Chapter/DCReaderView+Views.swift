//
//  DCReaderView+Toolbar.swift
//  DCEpubReaderKit
//
//  Created by Josep Cerdá Penadés on 31/10/25.
//

import SwiftUI

// MARK: - Floating controls

extension DCReaderView {

    /// Full controls when shown; otherwise just the chapter title, like Books while reading.
    var topChrome: some View {
        ZStack {
            Text(viewModel.readingTitle)
                .font(.subheadline)
                .foregroundStyle(viewModel.textColor.opacity(0.6))
                .lineLimit(1)
                .padding(.horizontal, DCReaderChrome.buttonSize + 28)
                .opacity(showsChrome || !viewModel.hasPagePosition ? 0 : 1)
                .accessibilityHidden(showsChrome)
            topControls
                .opacity(showsChrome ? 1 : 0)
                .allowsHitTesting(showsChrome)
                .accessibilityHidden(!showsChrome)
        }
        .animation(.easeInOut(duration: 0.2), value: showsChrome)
        .frame(height: DCReaderChrome.topInset)
    }

    /// Full controls when shown; otherwise just the page number.
    var bottomChrome: some View {
        ZStack {
            Text(viewModel.readingPageText)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(viewModel.textColor.opacity(0.6))
                .opacity(showsChrome ? 0 : 1)
                .accessibilityHidden(showsChrome)
            bottomControls
                .opacity(showsChrome ? 1 : 0)
                .allowsHitTesting(showsChrome)
                .accessibilityHidden(!showsChrome)
        }
        .animation(.easeInOut(duration: 0.2), value: showsChrome)
        .frame(height: DCReaderChrome.bottomInset)
    }

    /// Close, pages left in the chapter, and bookmark.
    private var topControls: some View {
        HStack(spacing: 12) {
            DCChromeButton(systemImage: "xmark", accessibilityLabel: L("Close")) {
                close()
            }
            Spacer(minLength: 0)
            Text(viewModel.topStatusText)
                .opacity(viewModel.hasPagePosition || viewModel.transientStatus != nil ? 1 : 0)
                .font(.subheadline)
                .foregroundStyle(viewModel.textColor.opacity(0.6))
                .lineLimit(1)
            Spacer(minLength: 0)
            DCChromeButton(systemImage: viewModel.isCurrentPageBookmarked ? "bookmark.fill" : "bookmark",
                           accessibilityLabel: viewModel.isCurrentPageBookmarked ? L("Remove Bookmark") : L("Add Bookmark")) {
                viewModel.toggleBookmark()
            }
        }
        .padding(.horizontal, 16)
    }

    /// Progress scrubber, page number and the reader menu.
    private var bottomControls: some View {
        ZStack {
            DCProgressScrubber(viewModel: viewModel)
                .opacity(viewModel.hasPagePosition ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: viewModel.hasPagePosition)

            HStack {
                Spacer()
                readerMenu
            }
        }
        .padding(.horizontal, 16)
    }

    private var readerMenu: some View {
        Menu {
            ControlGroup {
                if viewModel.configuration.showsLineGuide {
                    Button {
                        viewModel.toggleLineFocus()
                    } label: {
                        Label(L("Line Guide"), systemImage: "text.line.first.and.arrowtriangle.forward")
                    }
                }
                Button {
                    Task { await viewModel.share() }
                } label: {
                    Label(L("Share…"), systemImage: "square.and.arrow.up")
                }
            }
            Button {
                viewModel.showContents = true
            } label: {
                Label(L("Contents"), systemImage: "list.bullet.rectangle.portrait")
            }
            if viewModel.configuration.showsSearch {
                Button {
                    viewModel.showSearch = true
                } label: {
                    Label(L("Search Book"), systemImage: "magnifyingglass")
                }
            }
            Button {
                viewModel.showSettings = true
            } label: {
                Label(L("Themes & Settings"), systemImage: "textformat.size")
            }
        } label: {
            DCChromeButtonLabel(systemImage: "ellipsis")
        }
        .menuOrder(.fixed)
        // Menus tint their label with the accent color; match the other floating buttons.
        .tint(.primary)
        .accessibilityLabel(L("Reader Menu"))
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
            bookByline: viewModel.bookByline,
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
                        Button(L("Close")) {
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
            textLayout: $viewModel.textLayout,
            rotationLock: $viewModel.rotationLock,
            themeColors: $viewModel.themeColors,
            systemIsDark: viewModel.systemIsDark,
            userPreferences: viewModel.userPreferences,
            configuration: viewModel.configuration,
            windowScene: viewModel.windowScene
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

// MARK: - Progress scrubber

/// Books-style progress scrubber: drag to any page of the book, with the chapter and page shown
/// above the slider while dragging; the page opens when the slider is released.
struct DCProgressScrubber: View {

    @ObservedObject var viewModel: DCReaderViewModel
    /// The slider's position while dragging; `nil` follows the page on screen.
    @State private var dragFraction: Double?

    var body: some View {
        VStack(spacing: 6) {
            Slider(value: Binding(get: { dragFraction ?? viewModel.scrubberFraction },
                                  set: { dragFraction = $0 }),
                   in: 0...1) { editing in
                if editing {
                    dragFraction = dragFraction ?? viewModel.scrubberFraction
                } else if let fraction = dragFraction {
                    viewModel.jump(to: viewModel.scrubTarget(at: fraction))
                    // Keep the thumb where it was released until the new page reports its position.
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 600_000_000)
                        dragFraction = nil
                    }
                }
            }
            .tint(viewModel.textColor.opacity(0.5))
            .frame(width: 220)
            Text(viewModel.progressText)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(viewModel.textColor.opacity(0.6))
        }
        .animation(.easeInOut(duration: 0.15), value: dragFraction == nil)
        .animation(.easeInOut(duration: 0.2), value: viewModel.backButtonTitle)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Progress"))
        .accessibilityValue(viewModel.progressText)
        .accessibilityHint(L("Swipe up or down to move by chapter."))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: viewModel.jumpChapter(by: 1)
            case .decrement: viewModel.jumpChapter(by: -1)
            @unknown default: break
            }
        }
        // Outside the slider's accessibility element, so VoiceOver reaches the back button.
        // The preview takes the back button's place while dragging.
        .overlay(alignment: .top) {
            if let dragFraction {
                preview(for: viewModel.scrubTarget(at: dragFraction))
                    .offset(y: -64)
                    .transition(.opacity)
            } else if let backTitle = viewModel.backButtonTitle {
                backButton(title: backTitle)
                    .offset(y: -58)
                    .transition(.opacity)
            }
        }
    }

    private func backButton(title: String) -> some View {
        Button {
            viewModel.goBack()
        } label: {
            Label(title, systemImage: "arrow.uturn.backward")
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .foregroundStyle(viewModel.textColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.regularMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func preview(for target: DCReaderViewModel.ScrubTarget) -> some View {
        VStack(spacing: 2) {
            Text(viewModel.scrubTitle(for: target))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text(viewModel.scrubDetail(for: target))
                .font(.caption.monospacedDigit())
                .opacity(0.7)
        }
        .foregroundStyle(viewModel.textColor)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        // Long chapter titles truncate to the slider's width.
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .allowsHitTesting(false)
    }
}
