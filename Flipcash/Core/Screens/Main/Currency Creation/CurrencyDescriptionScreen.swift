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

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 20) {
                CurrencyHeader(
                    currencyName: currencyName,
                    selectedImage: selectedImage,
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

                Button("Next") {
                    onContinue()
                }
                .buttonStyle(.filled)
                .disabled(currencyDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 20)
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
            Circle()
                .fill(Color(white: 0.15))
                .frame(width: 44, height: 44)
                .overlay {
                    if let image = selectedImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .clipShape(Circle())
                    } else {
                        Image(systemName: "photo")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.textMain)
                    }
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
