//
//  ActionPrivacyUpgrade.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipchatPaymentsAPI

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
    
    func compactMessages() throws -> [CompactMessage] {
        []
    }
}

extension ActionPrivacyUpgrade {
    enum Error: Swift.Error {
        case missingServerParameter
        case missingPrivacyUpgradeParameter
        case invalidMerkleProof
        case invalidSource
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
