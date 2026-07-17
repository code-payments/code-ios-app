//
//  BuyFlowDestinationView.swift
//  Flipcash
//
//  Created by Raul Riera on 2026-05-12.
//

import SwiftUI
import FlipcashCore

/// Sub-flow dispatcher for the `.buy` stack. Registered via
/// `.navigationDestination(for: BuyFlowPath.self)` on the stack root.
struct BuyFlowDestinationView: View {

    let path: BuyFlowPath

    @Environment(SessionContainer.self) private var sessionContainer

    var body: some View {
        switch path {
        case .selectPaymentCurrency(let targetMint, let targetName, let entered):
            BuyPaymentCurrencyScreen(
                targetMint: targetMint,
                targetName: targetName,
                entered: entered,
                session: sessionContainer.session,
                ratesController: sessionContainer.ratesController
            )

        case .paymentConfirmation(let targetMint, let targetName, let payment, let paymentAmount, let pinnedState):
            BuyConfirmationScreen(
                targetMint: targetMint,
                targetName: targetName,
                payment: payment,
                paymentAmount: paymentAmount,
                pinnedState: pinnedState
            )

        case .processing(let swapId, let targetMint, let currencyName, let amount, let swapType):
            SwapProcessingScreen(
                swapId: swapId,
                swapType: swapType,
                targetMint: targetMint,
                currencyName: currencyName,
                amount: amount
            )
        }
    }
}
