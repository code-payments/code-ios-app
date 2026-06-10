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
    let proofSignature: Signature
    
    var parameters: SwapResponseServerParameters?
        
    init(id: SwapId, owner: KeyPair, metadata: VerifiedSwapMetadata, swapAuthority: KeyPair, amount: UInt64, direction: SwapDirection, waitForBlockchain: Bool, proofSignature: Signature) {
        self.id = id
        self.owner = owner
        self.verifiedMetadata = metadata
        self.swapAuthority = swapAuthority
        self.amount = amount
        self.direction = direction
        self.waitForBlockchain = waitForBlockchain
        self.proofSignature = proofSignature
    }
    
    func sign(using parameters: SwapResponseServerParameters) throws -> [Signature] {
        let transaction = try transaction(using: parameters)
        return transaction.signatures(using: owner, swapAuthority)
    }

    func transaction(using parameters: SwapResponseServerParameters) throws -> SolanaTransaction {
        try TransactionBuilder.swap(
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
    func requestToSubmitSignatures() throws -> Ocp_Transaction_V1_StatefulSwapRequest {
        guard let parameters else {
            throw Error.missingSwapParametersProvided
        }

        let signatures = try sign(using: parameters)

        return .with {
            $0.submitSignatures = .with {
                $0.transactionSignatures = signatures.map({ key in
                    key.proto
                })
            }
        }
    }
}
