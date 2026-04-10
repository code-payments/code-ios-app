//
//  CurrencyBillCreationScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

struct CurrencyBillCreationScreen: View {
    let currencyName: String
    @Binding var backgroundColors: [Color]
    let onContinue: () -> Void

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

                ColorEditorControl(colors: $backgroundColors)
                    .frame(maxHeight: .infinity)
                    .padding(.bottom, 20)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Continue", action: onContinue)
                    .buttonStyle(.filled)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                CreationProgressBar(current: 4, total: CreationProgressBar.totalSteps)
            }
        }
    }
}
