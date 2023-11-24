//
//  ActionPrivacyUpgrade.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import CodeAPI

struct ActionPrivacyUpgrade: ActionType {
    
    var id: Int
    var serverParameter: ServerParameter?
    var signer: KeyPair?

    var source: AccountCluster
    var originalActionID: Int
    var originalCommitmentStateAccount: PublicKey
    var originalAmount: Kin
    var originalNonce: PublicKey
    var originalRecentBlockhash: Hash
    var treasury: PublicKey
    
    static let configCountRequirement: Int = 1
    
    init(source: AccountCluster, originalActionID: Int, originalCommitmentStateAccount: PublicKey, originalAmount: Kin, originalNonce: PublicKey, originalRecentBlockhash: Hash, treasury: PublicKey) {
        self.id = 0
        self.signer = source.authority.keyPair
        self.source = source
        
        self.originalActionID = originalActionID
        self.originalCommitmentStateAccount = originalCommitmentStateAccount
        self.originalAmount = originalAmount
        self.originalNonce = originalNonce
        self.originalRecentBlockhash = originalRecentBlockhash
        self.treasury = treasury
    }
    
    func transactions() throws -> [SolanaTransaction] {
        guard let serverParameter = serverParameter else {
            throw Error.missingServerParameter
        }
        
        guard case .permanentPrivacyUpgrade(let privacyUpgrade) = serverParameter.parameter else {
            throw Error.missingPrivacyUpgradeParameter
        }
        
        /// Validate the merkle proof and ensure that the original commitment
        /// accounts exist in the merkle tree provided by the server via the
        /// `merkleRoot` and `merkleProof` params
        
        let leaf = originalCommitmentStateAccount
        
        let isProofValid = leaf.verifyContained(
            in: privacyUpgrade.merkleRoot,
            using: privacyUpgrade.merkleProof
        )
        
        guard isProofValid else {
            throw Error.invalidMerkleProof
        }
        
//        print("--- Merkle Proof ---")
//        print("Valid: \(isProofValid ? "✅" : "❌")")
//        print("Leaf: \(leaf.base58)")
//        print("Root: \(privacyUpgrade.merkleRoot.base58)")
//        privacyUpgrade.merkleProof.enumerated().forEach { index, node in
//            print("n(\(index)): \(node.base58)")
//        }
//        print("---  End Proof   ---")
        
        // Server may provide the nonce and recentBlockhash and
        // it may match the original but we shouldn't trust it.
        // We'll user the original nonce and recentBlockhash that
        // the original transaction used.
        
        let splitterAccounts = SplitterCommitmentAccounts(
            treasury: treasury,
            destination: privacyUpgrade.newCommitmentDestination,
            recentRoot: privacyUpgrade.merkleRoot,
            transcript: privacyUpgrade.newCommitmentTranscript,
            amount: privacyUpgrade.newCommitmentAmount
        )
        
        let transaction = TransactionBuilder.transfer(
            timelockDerivedAccounts: source.timelockAccounts,
            destination: splitterAccounts.vault.publicKey,
            amount: originalAmount,
            nonce: originalNonce,
            recentBlockhash: originalRecentBlockhash,
            kreIndex: KRE.index
        )
        
        return [transaction]
    }
}

extension ActionPrivacyUpgrade {
    enum Error: Swift.Error {
        case missingServerParameter
        case missingPrivacyUpgradeParameter
        case invalidMerkleProof
    }
}

// MARK: - Proto -

extension ActionPrivacyUpgrade {
    func action() -> Code_Transaction_V2_Action {
        .with {
            $0.id = UInt32(id)
            $0.permanentPrivacyUpgrade = .with {
                $0.actionID = UInt32(originalActionID)
            }
        }
    }
}
