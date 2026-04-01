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

                ColorEditorControl(colors: $backgroundColors)
                    .frame(maxHeight: .infinity)
                    .padding(.bottom, 20)
                    .fixedSize(horizontal: false, vertical: true)

                NavigationLink(value: CurrencyCreationPath.confirmation) {
                    Text("Continue")
                }
                .buttonStyle(.filled)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .navigationTitle(currencyName)
        .navigationBarTitleDisplayMode(.inline)
    }
}
