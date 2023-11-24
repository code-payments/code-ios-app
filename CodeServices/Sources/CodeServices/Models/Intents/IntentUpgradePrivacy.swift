//
//  IntentUpgradePrivacy.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import CodeAPI

class IntentUpgradePrivacy: IntentType {
    
    let id: PublicKey
    
    var actionGroup: ActionGroup
    
    init(mnemonic: MnemonicPhrase, upgradeableIntent: UpgradeableIntent) throws {
        self.id = upgradeableIntent.id
        
        self.actionGroup = ActionGroup()
        
        let actions = try upgradeableIntent.actions.map { upgradeableAction in
            
            let actionAmount = upgradeableAction.originalAmount
            let originalDestination = upgradeableAction.originalDestination
            let treasury = upgradeableAction.treasury
            let recentRoot = upgradeableAction.recentRoot
            let originalNonce = upgradeableAction.originalNonce
            let originalRecentBlockhash = upgradeableAction.originalRecentBlockhash
            
            let sourceCluster = AccountCluster.using(
                type: upgradeableAction.sourceAccountType,
                index: upgradeableAction.sourceDerivationIndex,
                mnemonic: mnemonic
            )
            
            // Validate the server isn't mallicious and is providing
            // the original details of the transaction
            try validate(
                transactionData: upgradeableAction.transactionBlob,
                clientSignature: upgradeableAction.clientSignature,
                intentID: upgradeableIntent.id,
                actionID: upgradeableAction.id,
                amount: actionAmount,
                source: sourceCluster,
                destination: originalDestination,
                originalNonce: originalNonce,
                treasury: treasury,
                recentRoot: recentRoot
            )
            
            
            // We have to derive the original commitment accounts because
            // we'll need to verify whether the commitment state account
            // is part of the merkle tree provided by server paramaeters
            
            let originalSplitterAccounts = SplitterCommitmentAccounts(
                source: sourceCluster,
                destination: originalDestination,
                amount: actionAmount,
                treasury: treasury,
                recentRoot: recentRoot,
                intentID: id,
                actionID: upgradeableAction.id
            )
            
            return ActionPrivacyUpgrade(
                source: sourceCluster,
                originalActionID: upgradeableAction.id,
                originalCommitmentStateAccount: originalSplitterAccounts.state.publicKey,
                originalAmount: actionAmount,
                originalNonce: originalNonce,
                originalRecentBlockhash: originalRecentBlockhash,
                treasury: treasury
            )
        }
        
        self.actionGroup = ActionGroup(actions: actions)
    }
    
    private func validate(transactionData: Data, clientSignature: Signature, intentID: PublicKey, actionID: Int, amount: Kin, source: AccountCluster, destination: PublicKey, originalNonce: PublicKey, treasury: PublicKey, recentRoot: Hash) throws {
        
        guard let transaction = SolanaTransaction(data: transactionData) else {
            throw Error.failedToParseTransaction
        }
        
        var originalTransfer = ActionTransfer(
            kind: .tempPrivacyTransfer, // Isn't used here
            intentID: intentID,
            amount: amount,
            source: source,
            destination: destination
        )
        
        originalTransfer.id = actionID
        originalTransfer.serverParameter = ServerParameter(
            actionID: actionID,
            parameter: .tempPrivacy(.init(
                treasury: treasury,
                recentRoot: recentRoot
            )),
            configs: [
                .init(
                    nonce: originalNonce,
                    blockhash: transaction.recentBlockhash
                )
            ]
        )
        
        let originalTransaction = try originalTransfer.transactions()[0]
        
        guard originalTransaction.encode() == transactionData else {
            throw Error.transactionMismatch
        }
        
        // (Optional) Reach into transaction and make sure the source is the same
        
        let signature = originalTransaction.signature(using: source.authority.keyPair)
        
        guard signature == clientSignature else {
            throw Error.signatureMismatch
        }
    }
}

// MARK: - Errors -

extension IntentUpgradePrivacy {
    enum Error: Swift.Error {
        case failedToParseTransaction
        case transactionMismatch
        case signatureMismatch
    }
}

// MARK: - Proto -

extension IntentUpgradePrivacy {
    func metadata() -> Code_Transaction_V2_Metadata {
        .with {
            $0.upgradePrivacy = .with { _ in }
        }
    }
}

// MARK: - Cluster Derivation -

private extension AccountCluster {
    static func using(type: AccountType, index: Int, mnemonic: MnemonicPhrase) -> AccountCluster {
        AccountCluster(
            index: index,
            authority: .derive(using: type.derivationPath(using: index), mnemonic: mnemonic)
        )
    }
}
