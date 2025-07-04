//
//  StoredPool.swift
//  Code
//
//  Created by Dima Bart on 2025-07-04.
//

import Foundation
import FlipcashCore

struct StoredPool: Identifiable, Sendable, Equatable, Hashable {
    
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
    
    public let betCountYes: Int
    public let betCountNo: Int
    public let derivationIndex: Int
    public let isFundingDestinationInitialized: Bool
    
    var amountInPool: Fiat {
        Fiat(
            quarks: buyIn.quarks * UInt64(betCountYes + betCountNo),
            currencyCode: buyIn.currencyCode
        )
    }
    
    var winningsForYes: Fiat? {
        guard betCountYes > 0 else { return nil }
        return Fiat(
            quarks: amountInPool.quarks / UInt64(betCountYes),
            currencyCode: buyIn.currencyCode
        )
    }
    
    var winningsForNo: Fiat? {
        guard betCountNo > 0 else { return nil }
        return Fiat(
            quarks: amountInPool.quarks / UInt64(betCountNo),
            currencyCode: buyIn.currencyCode
        )
    }
    
    var winningPayout: Fiat? {
        if let resolution = resolution {
            switch resolution {
            case .yes:
                return winningsForYes
            case .no:
                return winningsForNo
            case .refund:
                return buyIn
            }
        }
        return nil
    }
    
    var amountOnYes: Fiat {
        Fiat(
            quarks: buyIn.quarks * UInt64(betCountYes),
            currencyCode: buyIn.currencyCode
        )
    }
    
    var amountOnNo: Fiat {
        Fiat(
            quarks: buyIn.quarks * UInt64(betCountNo),
            currencyCode: buyIn.currencyCode
        )
    }
}

// MARK: - Metadata -

extension StoredPool {
    func metadataToClose(resolution: PoolResoltion) -> PoolMetadata {
        .init(
            id: id,
            rendezvous: rendezvous,
            fundingAccount: fundingAccount,
            creatorUserID: creatorUserID,
            creationDate: creationDate,
            closedDate: .now,
            isOpen: false,
            name: name,
            buyIn: buyIn,
            resolution: resolution
        )
    }
}
