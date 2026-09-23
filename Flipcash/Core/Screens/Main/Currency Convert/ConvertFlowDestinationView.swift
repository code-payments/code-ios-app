//
//  ConvertFlowDestinationView.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore

/// Sub-flow dispatcher for the convert stack. Registered via
/// `.navigationDestination(for: ConvertFlowPath.self)` on `ConvertAmountScreen`.
struct ConvertFlowDestinationView: View {

    let path: ConvertFlowPath

    var body: some View {
        switch path {
        case .confirmation(let sourceMint, let destinationMint, let destinationName, let amount, let sellFeeBps, let pinnedState):
            ConvertConfirmationScreen(
                sourceMint: sourceMint,
                destinationMint: destinationMint,
                destinationName: destinationName,
                amount: amount,
                sellFeeBps: sellFeeBps,
                pinnedState: pinnedState
            )

        case .processing(let swapId, let destinationMint, let destinationName, let amount):
            SwapProcessingScreen(
                swapId: swapId,
                swapType: .convert,
                targetMint: destinationMint,
                currencyName: destinationName,
                amount: amount
            )
        }
    }
}
