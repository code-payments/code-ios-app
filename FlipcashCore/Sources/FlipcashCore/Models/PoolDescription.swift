//
//  PoolDescription.swift
//  FlipcashCore
//
//  Created by Dima Bart on 2025-06-20.
//

import Foundation
import FlipcashCoreAPI

public struct PoolDescription: Sendable, Equatable, Hashable {
    
    public let metadata: PoolMetadata
    public let signature: Signature
//    let bets: [BetMetadata]
    
    public init(metadata: PoolMetadata, signature: Signature) {
        self.metadata = metadata
        self.signature = signature
    }
}

//struct BetMetadata: Sendable, Equatable, Hashable {
//    
//}

// MARK: - Error -

extension PoolDescription {
    enum Error: Swift.Error {
        case invalidSignature
    }
}


// MARK: - Proto -

extension PoolDescription {
    init(_ proto: Flipcash_Pool_V1_PoolMetadata) throws {
        guard let signature = Signature(proto.rendezvousSignature.value) else {
            throw Error.invalidSignature
        }
        
        self.init(
            metadata: try PoolMetadata(proto.verifiedMetadata),
            signature: signature
        )
    }
}
