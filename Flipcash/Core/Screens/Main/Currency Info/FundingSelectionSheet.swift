//
//  FundingSelectionSheet.swift
//  Code
//
//  Created by Claude on 2025-02-04.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct FundingSelectionSheet: View {
    let reserveBalance: ExchangedFiat?
    let onSelectReserves: () -> Void
    let onSelectPhantom: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        PartialSheet {
            VStack {
                HStack {
                    Text("Select Purchase Method")
                        .font(.appBarButton)
                        .foregroundStyle(Color.textMain)
                    Spacer()
                }
                .padding(.vertical, 20)

                if let reserveBalance, reserveBalance.hasDisplayableValue() {
                    CodeButton(style: .filled, title: "USD Reserves (\(reserveBalance.converted.formatted()))") {
                        onSelectReserves()
                    }
                }

                CodeButton(style: .filledCustom(Image.asset(.phantom), "Phantom"), title: "Solana USDC With") {
                    onSelectPhantom()
                }

                CodeButton(style: .subtle, title: "Dismiss") {
                    onDismiss()
                }
            }
            .padding()
        }
    }
}
