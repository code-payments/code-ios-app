//
//  CurrencyIconScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

struct CurrencyIconScreen: View {
    let currencyName: String
    @Binding var selectedImage: UIImage?
    let namespace: Namespace.ID
    let onContinue: () -> Void

    @State private var isShowingImagePicker = false

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 0) {
                Text("Upload Currency Icon")
                    .font(.appTextLarge)
                    .foregroundStyle(Color.textMain)
                    .padding(.top, 20)

                Text("Et nulla qui esse adipisicing veniam deserunt amet veniam veniam veniam cupidatat enim id")
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                    .padding(.horizontal, 20)

                Spacer()

                // Upload circle
                Button {
                    isShowingImagePicker = true
                } label: {
                    UploadCircle(selectedImage: selectedImage)
                }
                .buttonStyle(.plain)

                Text(currencyName)
                    .font(.appDisplaySmall)
                    .foregroundStyle(Color.textMain)
                    .padding(.top, 16)

                Spacer()

                Text("500x500 Recommended")
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.bottom, 12)

                Button("Next") {
                    onContinue()
                }
                .buttonStyle(.filled)
                .disabled(selectedImage == nil)
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - UploadCircle

private struct UploadCircle: View {
    let selectedImage: UIImage?

    var body: some View {
        Circle()
            .fill(Color(white: 0.2))
            .frame(width: 150, height: 150)
            .overlay {
                if let image = selectedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .clipShape(Circle())
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(Color.textSecondary)
                }
            }
    }
}
