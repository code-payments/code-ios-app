//
//  PoolMetadata.swift
//  FlipcashCore
//
//  Created by Dima Bart on 2025-06-19.
//

import Foundation
import FlipcashCoreAPI

public struct PoolMetadata: Identifiable, Sendable, Equatable, Hashable {
    
    public let id: PublicKey
    public let fundingAccount: PublicKey
    public let creatorUserID: UserID
    public let creationDate: Date
    public let isOpen: Bool
    public let name: String
    public let buyIn: Fiat
    public let resolution: PoolResoltion?
    
    public let rendezvous: KeyPair?
    
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

extension PoolMetadata {
    enum Error: Swift.Error {
        case invalidPublicKey
        case invalidCurrencyCode
    }
}

// MARK: - Proto -

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
