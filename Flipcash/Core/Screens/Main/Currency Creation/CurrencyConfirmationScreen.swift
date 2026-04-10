//
//  CurrencyConfirmationScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

struct CurrencyConfirmationScreen: View {
    let currencyName: String
    let selectedImage: UIImage?
    @Binding var backgroundColors: [Color]

    @State private var isShowingFundingSheet = false

    // swiftlint:disable:next force_try
    private static let previewFiat = try! Quarks(fiatDecimal: 20, currencyCode: .usd, decimals: 6)

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 0) {
                ConfirmationHeader(
                    currencyName: currencyName,
                    selectedImage: selectedImage
                )
                .padding(.top, 20)
                .padding(.horizontal, 20)

                GeometryReader { geometry in
                    if geometry.size.width > 0, geometry.size.height > 0 {
                        BillView(
                            fiat: Self.previewFiat,
                            data: .placeholder35,
                            canvasSize: geometry.size,
                            backgroundColors: backgroundColors
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .padding(.top, 20)
                .padding(.horizontal, 20)

                Button("Buy $20 to Create Your Currency") {
                    isShowingFundingSheet = true
                }
                .buttonStyle(.filled)
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                CreationProgressBar(current: 5, total: CreationProgressBar.totalSteps)
            }
        }
        .sheet(isPresented: $isShowingFundingSheet) {
            FundingSelectionSheet(
                reserveBalance: nil,
                isCoinbaseAvailable: false,
                onSelectReserves: {
                    isShowingFundingSheet = false
                    // TODO: RPC integration
                },
                onSelectCoinbase: {
                    isShowingFundingSheet = false
                    // TODO: Coinbase integration
                },
                onSelectPhantom: {
                    isShowingFundingSheet = false
                    // TODO: Phantom integration
                },
                onDismiss: {
                    isShowingFundingSheet = false
                }
            )
        }
    }
}

// MARK: - ConfirmationHeader

private struct ConfirmationHeader: View {
    let currencyName: String
    let selectedImage: UIImage?

    var body: some View {
        VStack(spacing: 8) {
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
            .clipShape(Circle())

            Text(currencyName)
                .font(.appTextLarge)
                .foregroundStyle(Color.textMain)
        }
    }
}
