//
//  IntentFundSwap.swift
//  FlipcashCore
//

import Foundation
import FlipcashAPI
import SwiftProtobuf

/// Intent to fund a VM swap PDA for swap execution
final class IntentFundSwap: IntentType {

    let id: PublicKey
    let swapId: SwapId
    let sourceCluster: AccountCluster
    let amount: ExchangedFiat
    let verifiedState: VerifiedState
    let destination: PublicKey
    let destinationOwner: PublicKey

    var actionGroup: ActionGroup

    init(
        intentID: PublicKey,
        swapId: SwapId,
        sourceCluster: AccountCluster,
        amount: ExchangedFiat,
        verifiedState: VerifiedState,
        fromMint: MintMetadata,
        toMint: MintMetadata
    ) {
        self.id = intentID
        self.swapId = swapId
        self.sourceCluster = sourceCluster
        self.amount = amount
        self.verifiedState = verifiedState

        // Use VM swap accounts for destination (NOT regular timelock)
        guard let timelockAccounts = fromMint.timelockSwapAccounts(owner: sourceCluster.authorityPublicKey) else {
            fatalError("Failed to derive VM swap PDA for \(fromMint.symbol)")
        }

        self.destination = timelockAccounts.ata.publicKey
        self.destinationOwner = timelockAccounts.pda.publicKey

        let transfer = ActionTransfer(
            amount: amount.onChainAmount,
            sourceCluster: sourceCluster,
            destination: destination,
            mint: fromMint.address
        )

        self.actionGroup = ActionGroup(actions: [transfer])
    }
}

// MARK: - Proto -

extension IntentFundSwap {
    func metadata() -> Ocp_Transaction_V1_Metadata {
        .with {
            $0.sendPublicPayment = .with {
                $0.source = sourceCluster.vaultPublicKey.solanaAccountID
                $0.destination = destination.solanaAccountID
                $0.destinationOwner = destinationOwner.solanaAccountID
                $0.mint = amount.mint.solanaAccountID

                $0.clientExchangeData = .init(amount: amount, verifiedState: verifiedState)

                $0.isWithdrawal = true
                $0.isIndirectSend = false
            }
        }
    }
}
