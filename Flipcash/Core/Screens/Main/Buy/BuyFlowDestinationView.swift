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

    var body: some View {
        switch path {
        case .phantomEducation(let mint, let amount):
            PhantomEducationScreen(mint: mint, amount: amount)
        case .phantomConfirm(let mint, let amount):
            PhantomConfirmScreen(mint: mint, amount: amount)
        case .usdcDepositEducation(let mint, let amount):
            USDCDepositEducationScreen(mint: mint, amount: amount)
        case .usdcDepositAddress(let mint, let amount):
            USDCDepositAddressScreen(mint: mint, amount: amount)
        case .processing(let swapId, let currencyName, let amount, let swapType):
            SwapProcessingScreen(
                swapId: swapId,
                swapType: swapType,
                currencyName: currencyName,
                amount: amount
            )
        }
    }
}
