//
//  DCNotesView.swift
//  DCEpubReaderKit
//
//  Created by Josep Cerdá Penadés on 10/11/25.
//

import SwiftUI

/// Books-style note editor: the quoted passage above a text editor that opens with the keyboard up.
struct DCNotesView: View {

    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: DCNotesViewModel
    @FocusState private var editorFocused: Bool

    init(viewModel: DCNotesViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                quote
                TextEditor(text: $viewModel.note)
                    .focused($editorFocused)
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(viewModel.textColor)
                    .font(.body)
                    .overlay(alignment: .topLeading) {
                        if viewModel.note.isEmpty {
                            Text(L("Add a note"))
                                .foregroundStyle(viewModel.textColor.opacity(0.4))
                                // Lines the placeholder up with the editor's text inset.
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                    .accessibilityLabel(L("Note"))
                    .onChange(of: viewModel.note) { newNote in
                        viewModel.noteDidChange(newNote)
                    }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(viewModel.backgroundColor.ignoresSafeArea())
            .navigationTitle(L("Note"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(viewModel.backgroundColor, for: .navigationBar)
            .toolbarColorScheme(viewModel.isDark ? .dark : .light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Done")) {
                        viewModel.saveNow()
                        dismiss()
                    }
                }
            }
        }
        .task {
            // Focusing during the sheet's presentation animation is ignored, so wait for it to settle.
            try? await Task.sleep(nanoseconds: 350_000_000)
            editorFocused = true
        }
        .onDisappear {
            viewModel.saveNow()
        }
    }

    /// The passage the note is attached to, marked with its highlight color.
    private var quote: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(viewModel.quoteColor)
                .frame(width: 4)
            Text(viewModel.quotedText)
                .font(.callout)
                .foregroundStyle(viewModel.textColor.opacity(0.75))
                .lineLimit(6)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(format: L("Quote: %@"), viewModel.quotedText))
    }
}

#if DEBUG

#Preview {
    DCNotesViewBuilderMock().build()
}

#endif
