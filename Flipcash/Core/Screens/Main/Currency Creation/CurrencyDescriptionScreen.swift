//
//  CurrencyDescriptionScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

struct CurrencyDescriptionScreen: View {
    let currencyName: String
    let selectedImage: UIImage?
    @Binding var currencyDescription: String
    let namespace: Namespace.ID
    let onContinue: () -> Void

    @FocusState private var isFocused: Bool

    private let characterLimit = 500

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        CurrencyHeader(
                            currencyName: currencyName,
                            selectedImage: selectedImage,
                            namespace: namespace
                        )
                        .padding(.top, 20)

                        Text("Provide a description for\nyour currency")
                            .font(.appTextLarge)
                            .foregroundStyle(Color.textMain)
                            .padding(.top, 20)

                        TextField("Description", text: $currencyDescription, axis: .vertical)
                            .font(.appTextMedium)
                            .foregroundStyle(Color.textMain)
                            .focused($isFocused)
                            .padding(.top, 16)
                            .onChange(of: currencyDescription) { _, newValue in
                                if newValue.count > characterLimit {
                                    currencyDescription = String(newValue.prefix(characterLimit))
                                }
                            }
                    }
                    .padding(.horizontal, 20)
                }
                .scrollDismissesKeyboard(.interactively)
                .scrollIndicators(.hidden)

                Text("\(characterLimit - currencyDescription.count) characters")
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)

                Button("Next", action: onContinue)
                    .buttonStyle(.filled)
                    .disabled(currencyDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
            }
        }
        .onAppear { isFocused = true }
    }
}

// MARK: - CurrencyHeader

private struct CurrencyHeader: View {
    let currencyName: String
    let selectedImage: UIImage?
    let namespace: Namespace.ID

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(white: 0.15))

                if let image = selectedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.textMain)
                }
            }
            .frame(width: 44, height: 44)
            .compositingGroup()
            .clipShape(Circle())
            .matchedGeometryEffect(id: "currencyIcon", in: namespace)

            Text(currencyName)
                .font(.appTextLarge)
                .foregroundStyle(Color.textMain)
                .matchedGeometryEffect(id: "currencyName", in: namespace)

            Spacer()
        }
    }
}
