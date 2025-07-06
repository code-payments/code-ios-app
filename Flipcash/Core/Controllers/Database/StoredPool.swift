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
    public var isHost: Bool
    public var closedDate: Date?
    public var rendezvous: KeyPair?
    public var resolution: PoolResoltion?
    
    public let betCountYes: Int
    public let betCountNo: Int
    public let derivationIndex: Int
    public let isFundingDestinationInitialized: Bool
    public let userOutcome: UserOutcome
    
    var amountInPool: Fiat {
        Fiat(
            quarks: buyIn.quarks * UInt64(betCountYes + betCountNo),
            currencyCode: buyIn.currencyCode
        )
    }
    
    var payout: Fiat? {
        if let resolution = resolution {
            return payoutFor(resolution: resolution)
        }
        return nil
    }
    
//    var amountOnYes: Fiat {
//        Fiat(
//            quarks: buyIn.quarks * UInt64(betCountYes),
//            currencyCode: buyIn.currencyCode
//        )
//    }
//    
//    var amountOnNo: Fiat {
//        Fiat(
//            quarks: buyIn.quarks * UInt64(betCountNo),
//            currencyCode: buyIn.currencyCode
//        )
//    }
    
    func payoutFor(resolution: PoolResoltion) -> Fiat {
        let winnerCount = winnerCount(for: resolution)
        guard winnerCount > 0 else {
            return Fiat(
                quarks: 0 as UInt64,
                currencyCode: buyIn.currencyCode
            )
        }
        
        return Fiat(
            quarks: amountInPool.quarks / UInt64(winnerCount),
            currencyCode: buyIn.currencyCode
        )
    }
    
    func winnerCount(for resolution: PoolResoltion) -> Int {
        let totalBets = betCountYes + betCountNo
        
        switch resolution {
        case .yes:
            guard betCountYes > 0 else {
                return totalBets
            }
            
            return betCountYes
            
        case .no:
            guard betCountNo > 0 else {
                return totalBets
            }
            
            return betCountNo
            
        case .refund:
            return totalBets
        }
    }
}

// MARK: - Metadata -

extension StoredPool {
    func metadataToClose(resolution: PoolResoltion?) -> PoolMetadata {
        .init(
            id: id,
            rendezvous: rendezvous,
            fundingAccount: fundingAccount,
            creatorUserID: creatorUserID,
            creationDate: creationDate,
            closedDate: closedDate ?? .now,
            isOpen: false,
            name: name,
            buyIn: buyIn,
            resolution: resolution
        )
    }
}
