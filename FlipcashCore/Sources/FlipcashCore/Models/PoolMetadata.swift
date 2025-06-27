//
//  PoolMetadata.swift
//  FlipcashCore
//
//  Created by Dima Bart on 2025-06-19.
//

import Foundation
import FlipcashCoreAPI

public struct PoolDescription: Sendable, Equatable, Hashable {
    
    public let metadata: PoolMetadata
    public let signature: Signature
    public let bets: [BetDescription]
    public let cursor: ID?
    public let additionalInfo: PoolInfo
    
    public init(metadata: PoolMetadata, signature: Signature, bets: [BetDescription], cursor: ID?, additionalInfo: PoolInfo) {
        self.metadata       = metadata
        self.signature      = signature
        self.bets           = bets
        self.cursor         = cursor
        self.additionalInfo = additionalInfo
    }
}

public struct PoolInfo: Sendable, Equatable, Hashable {
    public let betCountYes: Int
    public let betCountNo: Int
    public let derivationIndex: Int
    public let isFundingDestinationInitialized: Bool
    
    public init(betCountYes: Int, betCountNo: Int, derivationIndex: Int, isFundingDestinationInitialized: Bool) {
        self.betCountYes = betCountYes
        self.betCountNo = betCountNo
        self.derivationIndex = derivationIndex
        self.isFundingDestinationInitialized = isFundingDestinationInitialized
    }
}

public struct PoolMetadata: Identifiable, Sendable, Equatable, Hashable {
    
    public let id: PublicKey
    public let fundingAccount: PublicKey
    public let creatorUserID: UserID
    public let creationDate: Date
    public let isOpen: Bool
    public let name: String
    public let buyIn: Fiat
    public let resolution: PoolResoltion?
    
    public var rendezvous: KeyPair?
    
    public init(id: PublicKey, rendezvous: KeyPair?, fundingAccount: PublicKey, creatorUserID: UserID, creationDate: Date, isOpen: Bool, name: String, buyIn: Fiat, resolution: PoolResoltion?) {
        self.id = id
        self.rendezvous = rendezvous
        self.fundingAccount = fundingAccount
        self.creatorUserID = creatorUserID
        self.creationDate = creationDate
        self.isOpen = isOpen
        self.name = name
        self.buyIn = buyIn
        self.resolution = resolution
    }
}

public enum PoolResoltion: Sendable, Equatable, Hashable {
    case yes
    case no
}

// MARK: - Errors -

extension PoolDescription {
    enum Error: Swift.Error {
        case invalidSignature
    }
}

extension PoolMetadata {
    enum Error: Swift.Error {
        case invalidPublicKey
        case invalidCurrencyCode
    }
}

// MARK: - Proto -

extension PoolDescription {
    init(_ proto: Flipcash_Pool_V1_PoolMetadata) throws {
        guard let signature = Signature(proto.rendezvousSignature.value) else {
            throw Error.invalidSignature
        }
        
        // TODO: Filter out any unpaid bets
//        let betProtos = proto.bets.filter { $0.isIntentSubmitted }
        
        self.init(
            metadata: try PoolMetadata(proto.verifiedMetadata),
            signature: signature,
            bets: try proto.bets.map { try BetDescription($0) },
            cursor: ID(data: proto.pagingToken.value),
            additionalInfo: .init(
                betCountYes: Int(proto.betSummary.booleanSummary.numYes),
                betCountNo: Int(proto.betSummary.booleanSummary.numNo),
                derivationIndex: Int(proto.derivationIndex),
                isFundingDestinationInitialized: proto.isFundingDestinationInitialized
            )
        )
    }
}

extension PoolMetadata {
    init(_ proto: Flipcash_Pool_V1_SignedPoolMetadata) throws {
        guard
            let id = PublicKey(proto.id.value),
            let fundingAccount = PublicKey(proto.fundingDestination.value)
        else {
            throw Error.invalidPublicKey
        }
        
        var resolution: PoolResoltion?
        if proto.hasResolution {
            resolution = proto.resolution.booleanResolution ? .yes : .no
        }
        
        self.init(
            id: id,
            rendezvous: nil,
            fundingAccount: fundingAccount,
            creatorUserID: try UserID(data: proto.creator.value),
            creationDate: proto.createdAt.date,
            isOpen: proto.isOpen,
            name: proto.name,
            buyIn: try Fiat(
                fiatDecimal: Decimal(proto.buyIn.nativeAmount),
                currencyCode: try CurrencyCode(currencyCode: proto.buyIn.currency)
            ),
            resolution: resolution
        )
    }
}
