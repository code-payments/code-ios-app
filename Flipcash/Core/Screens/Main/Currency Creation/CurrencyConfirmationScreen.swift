//
//  CurrencyConfirmationScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

struct CurrencyConfirmationScreen: View {
    let currencyName: String
    @Binding var backgroundColors: [Color]

    @State private var isShowingFundingSheet = false

    // swiftlint:disable:next force_try
    private static let previewFiat = try! Quarks(fiatDecimal: 20, currencyCode: .usd, decimals: 6)

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 0) {
                GeometryReader { geometry in
                    BillView(
                        fiat: Self.previewFiat,
                        data: .placeholder35,
                        canvasSize: CGSize(
                            width: geometry.size.width,
                            height: geometry.size.height
                        ),
                        backgroundColors: backgroundColors
                    )
                    .frame(maxWidth: .infinity)
                }
                .padding(.top, 20)

                Spacer()

                Button("Buy $20 to Create Your Currency") {
                    isShowingFundingSheet = true
                }
                .buttonStyle(.filled)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
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
