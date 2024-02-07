//
//  SwapIntent.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import CodeAPI

class SwapIntent {
    
    let id: PublicKey
    let organizer: Organizer
    
    let owner: KeyPair
    
    let swapCluster: AccountCluster
    
    var parameters: SwapConfigParameters?
    
    // MARK: - Init -
    
    init(organizer: Organizer) {
        self.id = PublicKey.generate()!
        self.organizer = organizer
        
        self.owner = organizer.ownerKeyPair
        
        self.swapCluster = organizer.tray.cluster(for: .swap)
    }
    
    func sign(using parameters: SwapConfigParameters) -> Signature {
        let transaction = transaction(using: parameters)
        return transaction.signature(using: organizer.swapKeyPair)
    }
    
    func transaction(using parameters: SwapConfigParameters) -> SolanaTransaction {
        TransactionBuilder.swap(
            from: swapCluster,
            to: organizer.primaryVault,
            parameters: parameters
        )
    }
}

extension SwapIntent {
    enum Error: Swift.Error {
        case missingSwapParametersProvided
    }
}

extension SwapIntent {
    func requestToSubmitSignatures() throws -> Code_Transaction_V2_SwapRequest {
        guard let parameters else {
            throw Error.missingSwapParametersProvided
        }
        
        return .with {
            $0.submitSignature = .with {
                $0.signature = sign(using: parameters).codeClientSignature
            }
        }
    }
}
