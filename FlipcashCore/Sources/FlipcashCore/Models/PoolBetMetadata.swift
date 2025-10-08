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
    public let isFulfilled: Bool
    
    public init(metadata: BetMetadata, signature: Signature, isFulfilled: Bool) {
        self.metadata    = metadata
        self.signature   = signature
        self.isFulfilled = isFulfilled
    }
}

public struct BetMetadata: Sendable, Equatable, Hashable {
    public let id: PublicKey
    public let userID: UserID
    public let payoutDestination: PublicKey
    public let betDate: Date
    public let selectedOutcome: PoolResoltion
    
    public init(id: PublicKey, userID: UserID, payoutDestination: PublicKey, betDate: Date, selectedOutcome: PoolResoltion) {
        self.id = id
        self.userID = userID
        self.payoutDestination = payoutDestination
        self.betDate = betDate
        self.selectedOutcome = selectedOutcome
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
        self.init(
            metadata: try BetMetadata(proto.verifiedMetadata),
            signature: try Signature(proto.rendezvousSignature.value),
            isFulfilled: proto.isIntentSubmitted
        )
    }
}

extension BetMetadata {
    init(_ proto: Flipcash_Pool_V1_SignedBetMetadata) throws {
        let outcome: PoolResoltion
        switch proto.selectedOutcome.kind {
        case .booleanOutcome(let value):
            outcome = value ? .yes : .no
        default:
            throw Error.unsupportedBetOutcome
        }
        
        self.init(
            id: try PublicKey(proto.betID.value),
            userID: try UserID(data: proto.userID.value),
            payoutDestination: try PublicKey(proto.payoutDestination.value),
            betDate: proto.ts.date,
            selectedOutcome: outcome
        )
    }
}
