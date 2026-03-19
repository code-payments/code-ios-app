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
                    Button("USDF (\(reserveBalance.converted.formatted()))") {
                        onSelectReserves()
                    }
                    .buttonStyle(.filled)
                }

                Button {
                    onSelectPhantom()
                } label: {
                    HStack(spacing: 4) {
                        Text("Solana USDC With")
                        Image.asset(.phantom)
                            .renderingMode(.template)
                            .resizable()
                            .frame(maxWidth: 20, maxHeight: 20)
                        Text("Phantom")
                    }
                }
                .buttonStyle(.filled)
                
                Button("Dismiss", action: onDismiss)
                    .buttonStyle(.subtle)
            }
            .padding()
        }
    }
}
