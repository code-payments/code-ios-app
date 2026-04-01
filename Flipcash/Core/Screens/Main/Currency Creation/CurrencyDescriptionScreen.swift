//
//  CurrencyDescriptionScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

struct CurrencyDescriptionScreen: View {
    let currencyName: String
    let selectedIcon: Int
    @Binding var currencyDescription: String
    let namespace: Namespace.ID

    @FocusState private var isFocused: Bool

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 20) {
                // Geometry-matched header
                CurrencyHeader(
                    currencyName: currencyName,
                    iconName: CurrencyCreationIcons.name(for: selectedIcon),
                    namespace: namespace
                )
                .padding(.top, 20)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Describe Your Currency")
                        .font(.appTextLarge)
                        .foregroundStyle(Color.textMain)

                    Text("Tell people what your currency is about")
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Description input
                InputContainer(size: .custom(120)) {
                    TextEditor(text: $currencyDescription)
                        .font(.appTextBody)
                        .foregroundStyle(Color.textMain)
                        .scrollContentBackground(.hidden)
                        .focused($isFocused)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }

                Spacer()

                NavigationLink(value: CurrencyCreationPath.billCreation) {
                    Text("Continue")
                }
                .buttonStyle(.filled)
                .disabled(currencyDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 20)
        }
        .navigationTitle("Description")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { isFocused = true }
    }
}

// MARK: - CurrencyHeader

/// Reusable header showing the currency icon + name with geometry matching.
/// Used on screens 4+ where both icon and name are displayed.
private struct CurrencyHeader: View {
    let currencyName: String
    let iconName: String
    let namespace: Namespace.ID

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(white: 0.15))
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: iconName)
                        .font(.system(size: 18))
                        .foregroundStyle(Color.textMain)
                }
                .matchedGeometryEffect(id: "currencyIcon", in: namespace)

            Text(currencyName)
                .font(.appTextLarge)
                .foregroundStyle(Color.textMain)
                .matchedGeometryEffect(id: "currencyName", in: namespace)

            Spacer()
        }
    }
}
