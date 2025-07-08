//
//  PoolDistributionTests.swift
//  FlipcashTests
//
//  Created by Dima Bart on 2025-03-31.
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

struct PoolDistributionTests {
    
    @Test static func testDistributionWithLargeRemainder() throws {
        let bets = generateBets(count: 1000)
        let pool = Fiat(quarks: 123_456 as UInt64, currencyCode: .usd)
        
        let base      = pool.quarks / UInt64(bets.count)
        let remainder = pool.quarks % UInt64(bets.count)
        
        let distributions = bets.distributePool(balance: pool)
        for (index, distribution) in distributions.enumerated() {
            if index < remainder {
                #expect(distribution.amount.quarks == base + 1)
            } else {
                #expect(distribution.amount.quarks == base)
            }
        }
    }
    
    @Test static func testDistributionWithSmallRemainder() throws {
        let bets = generateBets(count: 3)
        let pool = Fiat(quarks: 8_000_000 as UInt64, currencyCode: .usd)
        
        let base      = pool.quarks / UInt64(bets.count)
        let remainder = pool.quarks % UInt64(bets.count)
        
        let distributions = bets.distributePool(balance: pool)
        for (index, distribution) in distributions.enumerated() {
            if index < remainder {
                #expect(distribution.amount.quarks == base + 1)
            } else {
                #expect(distribution.amount.quarks == base)
            }
        }
    }
    
    private static func generateBets(count: Int) -> [StoredBet] {
        let id = PublicKey.generate()!
        let userID = UserID()
        let destination = PublicKey.generate()!
        let date = Date.now
        
        var bets: [StoredBet] = []
        for _ in 0..<count {
            bets.append(
                .init(
                    id: id,
                    userID: userID,
                    payoutDestination: destination,
                    betDate: date,
                    selectedOutcome: .no,
                    isFulfilled: false
                )
            )
        }
        return bets
    }
}
