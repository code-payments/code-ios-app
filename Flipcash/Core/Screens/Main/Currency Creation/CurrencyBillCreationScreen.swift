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

                ColorEditorControl(colors: $backgroundColors)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 20)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                CreationProgressBar(current: 4, total: CreationProgressBar.totalSteps)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button("Done", action: onContinue)
            }
        }
    }
}
