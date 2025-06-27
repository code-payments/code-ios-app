//
//  PoolBetMetadata.swift
//  FlipcashCore
//
//  Created by Dima Bart on 2025-06-20.
//

import Foundation
import FlipcashCoreAPI

public struct BetDescription: Sendable, Equatable, Hashable {
    
    public let metadata: BetMetadata
    public let signature: Signature
    
    public init(metadata: BetMetadata, signature: Signature) {
        self.metadata  = metadata
        self.signature = signature
    }
}

public struct BetMetadata: Sendable, Equatable, Hashable {
    public let id: PublicKey
    public let userID: UserID
    public let payoutDestination: PublicKey
    public let betDate: Date
    public let selectedOutcome: BetOutcome
    
    public init(id: PublicKey, userID: UserID, payoutDestination: PublicKey, betDate: Date, selectedOutcome: BetOutcome) {
        self.id = id
        self.userID = userID
        self.payoutDestination = payoutDestination
        self.betDate = betDate
        self.selectedOutcome = selectedOutcome
    }
}

public enum BetOutcome: Sendable, Equatable, Hashable, Identifiable {
    case yes
    case no
    
    public var id: BetOutcome {
        self
    }
    
    public var boolValue: Bool {
        switch self {
        case .no:  return false
        case .yes: return true
        }
    }
    
    public var intValue: Int {
        switch self {
        case .no:  return 0
        case .yes: return 1
        }
    }
}

// MARK: - Error -

extension BetDescription {
    enum Error: Swift.Error {
        case invalidSignature
    }
}

extension BetMetadata {
    enum Error: Swift.Error {
        case invalidPublicKey
        case unsupportedBetOutcome
    }
}

// MARK: - Proto -

extension BetDescription {
    init(_ proto: Flipcash_Pool_V1_BetMetadata) throws {
        guard let signature = Signature(proto.rendezvousSignature.value) else {
            throw Error.invalidSignature
        }
        
        self.init(
            metadata: try BetMetadata(proto.verifiedMetadata),
            signature: signature
        )
    }
}

extension BetMetadata {
    init(_ proto: Flipcash_Pool_V1_SignedBetMetadata) throws {
        guard
            let id = PublicKey(proto.betID.value),
            let payoutDestination = PublicKey(proto.payoutDestination.value)
        else {
            throw Error.invalidPublicKey
        }
        
        let outcome: BetOutcome
        switch proto.selectedOutcome.kind {
        case .booleanOutcome(let value):
            outcome = value ? .yes : .no
        default:
            throw Error.unsupportedBetOutcome
        }
        
        self.init(
            id: id,
            userID: try UserID(data: proto.userID.value),
            payoutDestination: payoutDestination,
            betDate: proto.ts.date,
            selectedOutcome: outcome
        )
    }
}
