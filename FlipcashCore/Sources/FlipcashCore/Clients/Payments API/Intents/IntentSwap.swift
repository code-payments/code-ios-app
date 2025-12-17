//
//  IntentSwap.swift
//  FlipcashCore
//
//  Created by Brandon McAnsh on 12/15/25.
//

import FlipcashAPI

class IntentSwap {
    let id: SwapId
    
    let owner: KeyPair
    let verifiedMetadata: VerifiedSwapMetadata
    let swapAuthority: KeyPair
    let amount: UInt64
    let direction: SwapDirection
    let waitForBlockchain: Bool
    
    var parameters: SwapResponseServerParameters?
        
    init(id: SwapId, owner: KeyPair, metadata: VerifiedSwapMetadata, swapAuthority: KeyPair, amount: UInt64, direction: SwapDirection, waitForBlockchain: Bool) {
        self.id = id
        self.owner = owner
        self.verifiedMetadata = metadata
        self.swapAuthority = swapAuthority
        self.amount = amount
        self.direction = direction
        self.waitForBlockchain = waitForBlockchain
    }
    
    func sign(using parameters: SwapResponseServerParameters) -> [Signature] {
        let transaction = transaction(using: parameters)
        return transaction.signatures(using: owner, swapAuthority)
    }
    
    func transaction(using parameters: SwapResponseServerParameters) -> SolanaTransaction {
        TransactionBuilder.swap(
            responseParams: parameters,
            metadata: verifiedMetadata,
            authority: owner.publicKey,
            swapAuthority: swapAuthority.publicKey,
            direction: direction,
            amount: amount,
        )
    }
}

extension IntentSwap {
    enum Error: Swift.Error {
        case missingSwapParametersProvided
    }
}

extension IntentSwap {
    func requestToSubmitSignatures() throws -> Code_Transaction_V2_SwapRequest {
        guard let parameters else {
            throw Error.missingSwapParametersProvided
        }
        
        return .with {
            $0.submitSignatures = .with {
                $0.signatures = sign(using: parameters).map({ key in
                    key.proto
                })
            }
        }
    }
}
