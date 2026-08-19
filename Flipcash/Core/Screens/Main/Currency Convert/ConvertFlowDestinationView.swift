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

    @Environment(AppRouter.self) private var router

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
            // A finished convert lands back on the Wallet, per design — pop the
            // whole convert flow off the host stack and dismiss the token-info
            // card overlay it launched from.
            .environment(\.dismissParentContainer, {
                router.popToRoot()
                router.dismissExpandedCard()
            })
        }
    }
}
