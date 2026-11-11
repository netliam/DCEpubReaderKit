//
//  DCReaderSettingsView.swift
//  DCEpubReaderKit
//
//  Created by Josep Cerdá Penadés on 29/10/25.
//

import SwiftUI

struct DCReaderSettingsView: View {

    @ObservedObject var viewModel: DCReaderSettingsViewModel

    init(viewModel: DCReaderSettingsViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("A")
                    .frame(height: 54)
                    .font(.system(size: 13))
                    .foregroundStyle(viewModel.textColor)
                    .padding(.leading, 16)
                Slider(value: $viewModel.fontSize,
                       in: 0...7, step: 1)
                .tint(viewModel.textColor)
                .frame(height: 8)
                .padding(.horizontal)
                .onChange(of: viewModel.fontSize) { newValue in
                    viewModel.userPreferences.setValue(key: .fontSize, type: newValue)
                    viewModel.fontSize = newValue
                }
                Text("A")
                    .frame(height: 54)
                    .font(.system(size: 32))
                    .foregroundStyle(viewModel.textColor)
                    .padding(.trailing, 16)
            }
            HStack(spacing: 0) {
                ForEach(DCFontFamily.allCases, id: \.self) { font in
                    Button {
                        viewModel.userPreferences.setValue(key: .fontFamily,
                                                           type: font.rawValue)
                        viewModel.textFont = font.rawValue
                    } label: {
                        Text(font.name)
                            .frame(height: 54)
                            .font(font.font)
                            .foregroundStyle(viewModel.textColor)
                            .frame(maxWidth: .infinity)
                            .overlay(
                                Rectangle()
                                    .stroke(Color.gray, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 0) {
                ForEach(DCDesktopMode.allCase, id: \.self) { desktop in
                    Button {
                        viewModel.userPreferences.setValue(key: .desktopMode,
                                                           type: desktop.mode)
                        viewModel.desktopMode = desktop.mode
                    } label: {
                        HStack(spacing: 0) {
                            Text(desktop.name)
                                .font(.system(size: 13))
                                .foregroundStyle(viewModel.textColor)
                                .padding()
                            Image(systemName: "sun.max.fill")
                                .foregroundStyle(desktop.iconColor)
                        }
                        .frame(height: 54)
                        .frame(maxWidth: .infinity)
                        .overlay(
                            Rectangle()
                                .stroke(Color.gray, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 0) {
                ForEach(DCBookrOrientation.allCases, id: \.self) { orientation in
                    Button {
                        viewModel.userPreferences.setValue(key: .bookOrientation,
                                                           type: orientation.rawValue)
                        viewModel.orientation = orientation.rawValue
                    } label: {
                        HStack(spacing: 0) {
                            Text(orientation.name)
                                .font(.system(size: 13))
                                .foregroundStyle(viewModel.textColor)
                                .padding()
                            orientation.icon
                        }
                        .frame(height: 54)
                        .frame(maxWidth: .infinity)
                        .overlay(
                            Rectangle()
                                .stroke(Color.gray, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            if viewModel.showsPageTransition {
                HStack(spacing: 0) {
                    ForEach(DCPageTransition.allCases, id: \.self) { transition in
                        Button {
                            viewModel.userPreferences.setValue(key: .pageTransition,
                                                               type: transition.rawValue)
                            viewModel.pageTransition = transition.rawValue
                        } label: {
                            HStack(spacing: 0) {
                                Text(transition.name)
                                    .font(.system(size: 13))
                                    .foregroundStyle(viewModel.textColor)
                                    .padding()
                                Image(systemName: transition.iconName)
                                    .foregroundStyle(viewModel.textColor)
                            }
                            .frame(height: 54)
                            .frame(maxWidth: .infinity)
                            .overlay(
                                Rectangle()
                                    .stroke(Color.gray, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.top, 16)
    }
}

#if DEBUG

#Preview {
    DCReaderSettingsViewBuilder()
        .build(
            fontSize: .constant(
                2
            ),
            textFont: .constant(
                ""
            ),
            desktopMode: .constant(
                ""
            ),
            orientation: .constant(
                ""
            ),
            pageTransition: .constant(
                ""
            ),
            userPreferences: DCUserPreferencesMock()
        )
}

#endif
