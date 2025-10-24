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
    public let userOutcome: UserOutcome
    
    public init(betCountYes: Int, betCountNo: Int, derivationIndex: Int, isFundingDestinationInitialized: Bool, userOutcome: UserOutcome) {
        self.betCountYes = betCountYes
        self.betCountNo = betCountNo
        self.derivationIndex = derivationIndex
        self.isFundingDestinationInitialized = isFundingDestinationInitialized
        self.userOutcome = userOutcome
    }
}

public struct PoolMetadata: Identifiable, Sendable, Equatable, Hashable {
    
    public let id: PublicKey
    public let fundingAccount: PublicKey
    public let creatorUserID: UserID
    public let creationDate: Date
    public let name: String
    public let buyIn: Fiat
    
    public var isOpen: Bool
    public var closedDate: Date?
    public var rendezvous: KeyPair?
    public var resolution: PoolResoltion?
    
    public init(id: PublicKey, rendezvous: KeyPair?, fundingAccount: PublicKey, creatorUserID: UserID, creationDate: Date, closedDate: Date?, isOpen: Bool, name: String, buyIn: Fiat, resolution: PoolResoltion?) {
        self.id = id
        self.rendezvous = rendezvous
        self.fundingAccount = fundingAccount
        self.creatorUserID = creatorUserID
        self.creationDate = creationDate
        self.closedDate = closedDate
        self.isOpen = isOpen
        self.name = name
        self.buyIn = buyIn
        self.resolution = resolution
    }
}

public enum UserOutcome: Sendable, Equatable, Hashable {
    
    case none
    case won(Fiat)
    case lost(Fiat)
    case refunded(Fiat)
    
    public init(intValue: Int, amount: Fiat?) {
        switch intValue {
        case 0:
            self = .none
        case 1:
            self = .won(amount!)
        case 2:
            self = .lost(amount!)
        case 3:
            self = .refunded(amount!)
        default:
            fatalError("Invalid UserOutcome value")
        }
    }
    
    public var intValue: Int {
        switch self {
        case .none:     return 0
        case .won:      return 1
        case .lost:     return 2
        case .refunded: return 3
        }
    }
    
    public var amount: Fiat? {
        switch self {
        case .none:            return nil
        case .won(let a):      return a
        case .lost(let a):     return a
        case .refunded(let a): return a
        }
    }
}

public enum PoolResoltion: Identifiable, Sendable, Equatable, Hashable {
    
    case yes
    case no
    case refund
    
    public var id: Int {
        intValue
    }
    
    public var boolValue: Bool? {
        switch self {
        case .no:     return false
        case .yes:    return true
        case .refund: return nil
        }
    }
    
    public var intValue: Int {
        switch self {
        case .no:     return 0
        case .yes:    return 1
        case .refund: return 2
        }
    }
    
    public init?(intValue: Int) {
        switch intValue {
        case 0: self = .no
        case 1: self = .yes
        case 2: self = .refund
        default: return nil
        }
    }
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

extension PoolResoltion {
    var proto: Flipcash_Pool_V1_Resolution {
        .with {
            switch self {
            case .yes:
                $0.kind = .booleanResolution(true)
            case .no:
                $0.kind = .booleanResolution(false)
            case .refund:
                $0.kind = .refundResolution(.init())
            }
        }
    }
}

extension UserOutcome {
    init(_ proto: Flipcash_Pool_V1_UserPoolSummary) throws {
        guard let outcome = proto.outcome else {
            self = .none
            return
        }
        
        switch outcome {
        case .none:
            self = .none
        case .win(let result):
            self = .won(
                try Fiat(
                    fiatDecimal: Decimal(result.amountWon.nativeAmount),
                    currencyCode: try CurrencyCode(currencyCode: result.amountWon.currency),
                    decimals: 6
                )
            )
            
        case .lose(let result):
            self = .lost(
                try Fiat(
                    fiatDecimal: Decimal(result.amountLost.nativeAmount),
                    currencyCode: try CurrencyCode(currencyCode: result.amountLost.currency),
                    decimals: 6
                )
            )
            
        case .refund(let result):
            self = .refunded(
                try Fiat(
                    fiatDecimal: Decimal(result.amountRefunded.nativeAmount),
                    currencyCode: try CurrencyCode(currencyCode: result.amountRefunded.currency),
                    decimals: 6
                )
            )
        }
    }
}

extension PoolDescription {
    init(_ proto: Flipcash_Pool_V1_PoolMetadata) throws {
        self.init(
            metadata: try PoolMetadata(proto.verifiedMetadata),
            signature: try Signature(proto.rendezvousSignature.value),
            bets: try proto.bets.map { try BetDescription($0) },
            cursor: ID(data: proto.pagingToken.value),
            additionalInfo: .init(
                betCountYes: Int(proto.betSummary.booleanSummary.numYes),
                betCountNo: Int(proto.betSummary.booleanSummary.numNo),
                derivationIndex: Int(proto.derivationIndex),
                isFundingDestinationInitialized: proto.isFundingDestinationInitialized,
                userOutcome: try UserOutcome(proto.userSummary)
            )
        )
    }
}

extension PoolMetadata {
    
    var signedMetadata: Flipcash_Pool_V1_SignedPoolMetadata {
        .with {
            $0.id      = .with { $0.value = id.data }
            $0.creator = creatorUserID.proto
            $0.name    = name
            $0.buyIn   = .with {
                $0.nativeAmount = buyIn.doubleValue
                $0.currency     = buyIn.currencyCode.rawValue
            }
            $0.fundingDestination = fundingAccount.proto
            $0.isOpen             = isOpen
            $0.createdAt          = .from(date: creationDate, stripNanos: true)
            
            if let resolution = resolution {
                $0.resolution = resolution.proto
            }
            
            if let closedDate {
                $0.closedAt = .from(date: closedDate, stripNanos: true)
            }
        }
    }
    
    init(_ proto: Flipcash_Pool_V1_SignedPoolMetadata) throws {
        var resolution: PoolResoltion?
        if proto.hasResolution, let kind = proto.resolution.kind {
            switch kind {
            case .booleanResolution(let bool):
                resolution = bool ? .yes : .no
            case .refundResolution:
                resolution = .refund
            }
        }
        
        self.init(
            id: try PublicKey(proto.id.value),
            rendezvous: nil,
            fundingAccount: try PublicKey(proto.fundingDestination.value),
            creatorUserID: try UserID(data: proto.creator.value),
            creationDate: proto.createdAt.date,
            closedDate: proto.hasClosedAt ? proto.closedAt.date : nil,
            isOpen: proto.isOpen,
            name: proto.name,
            buyIn: try Fiat(
                fiatDecimal: Decimal(proto.buyIn.nativeAmount),
                currencyCode: try CurrencyCode(currencyCode: proto.buyIn.currency),
                decimals: 6
            ),
            resolution: resolution
        )
    }
}
