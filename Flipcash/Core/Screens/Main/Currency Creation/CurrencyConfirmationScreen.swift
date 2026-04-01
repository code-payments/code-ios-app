//
//  CurrencyConfirmationScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

struct CurrencyConfirmationScreen: View {
    let currencyName: String
    let backgroundColors: [Color]

    @State private var isShowingFundingSheet = false

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 0) {
                GeometryReader { geometry in
                    BillView(
                        fiat: try! Quarks(fiatDecimal: 20, currencyCode: .usd, decimals: 6),
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
        .navigationTitle(currencyName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingFundingSheet) {
            FundingSelectionSheet(
                reserveBalance: nil,
                onSelectReserves: {
                    isShowingFundingSheet = false
                    // TODO: RPC integration
                },
                onSelectPhantom: {
                    isShowingFundingSheet = false
                    // TODO: Phantom integration
                },
                onDismiss: {
                    isShowingFundingSheet = false
                }
            )
            .presentationDetents([.medium])
        }
    }
}
