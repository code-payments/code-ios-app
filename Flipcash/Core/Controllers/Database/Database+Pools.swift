//
//  Database+Pools.swift
//  Code
//
//  Created by Dima Bart on 2025-04-11.
//

import Foundation
import FlipcashCore
import SQLite

extension Database {
    
    // MARK: - Get Pool -
    
    func getPool(poolID: PublicKey) throws -> StoredPool? {
        let statement = try reader.prepareRowIterator("""
        SELECT
            p.id,
            p.fundingAccount,
            p.creatorUserID,
            p.creationDate,
            p.closedDate,
            p.isOpen,
            p.isHost,
            p.name,
            p.buyInQuarks,
            p.buyInCurrency,
            p.resolution,
            p.rendezvousSeed,
        
            p.betsCountYes,
            p.betsCountNo,
            p.derivationIndex,
            p.isFundingDestinationInitialized,
            p.userOutcome,
            p.userOutcomeQuarks,
            p.userOutcomeCurrency
        FROM pool p
        WHERE p.id = ?
        LIMIT 1;
        """, bindings: Blob(bytes: poolID.bytes))
        
        let t = PoolTable()
        
        let pools = try statement.map { row in
            var rendezvous: KeyPair?
            if let seed = row[t.rendezvousSeed] {
                rendezvous = KeyPair(seed: seed)
            }
            
            return StoredPool(
                id:             row[t.id],
                fundingAccount: row[t.fundingAccount],
                creatorUserID:  row[t.creatorUserID],
                creationDate:   row[t.creationDate],
                name:           row[t.name],
                buyIn: Fiat(
                    quarks:       row[t.buyInQuarks],
                    currencyCode: row[t.buyInCurrency]
                ),
                
                isOpen:         row[t.isOpen],
                isHost:         row[t.isHost],
                closedDate:     row[t.closedDate],
                rendezvous:     rendezvous,
                resolution:     row[t.resolution],
                
                betCountYes:                     row[t.betsCountYes],
                betCountNo:                      row[t.betsCountNo],
                derivationIndex:                 row[t.derivationIndex],
                isFundingDestinationInitialized: row[t.isFundingDestinationInitialized],
                userOutcome:                     userOutcome(for: row, t: t)
            )
        }
        
        return pools.first
    }
    
    private func userOutcome(for row: RowIterator.Element, t: PoolTable) -> UserOutcome {
        let userOutcomeInt = row[t.userOutcome]
        
        let userOutcome: UserOutcome
        if userOutcomeInt != UserOutcome.none.intValue {
            let amount = Fiat(
                quarks:       row[t.userOutcomeQuarks] ?? 0,
                currencyCode: row[t.userOutcomeCurrency] ?? .usd
            )
            userOutcome = UserOutcome(intValue: userOutcomeInt, amount: amount)
        } else {
            userOutcome = .none
        }
        
        return userOutcome
    }
    
    func getPools() throws -> [StoredPool] {
        let statement = try reader.prepareRowIterator("""
        SELECT
            p.id,
            p.fundingAccount,
            p.creatorUserID,
            p.creationDate,
            p.closedDate,
            p.isOpen,
            p.isHost,
            p.name,
            p.buyInQuarks,
            p.buyInCurrency,
            p.resolution,
            p.rendezvousSeed,
        
            p.betsCountYes,
            p.betsCountNo,
            p.derivationIndex,
            p.isFundingDestinationInitialized,
            p.userOutcome,
            p.userOutcomeQuarks,
            p.userOutcomeCurrency
        FROM pool p
        ORDER BY p.closedDate DESC, p.creationDate DESC
        LIMIT 1024;
        """)
        
        let t = PoolTable()
        
        let pools = try statement.map { row in
            var rendezvous: KeyPair?
            if let seed = row[t.rendezvousSeed] {
                rendezvous = KeyPair(seed: seed)
            }
            
            return StoredPool(
                id:             row[t.id],
                fundingAccount: row[t.fundingAccount],
                creatorUserID:  row[t.creatorUserID],
                creationDate:   row[t.creationDate],
                name:           row[t.name],
                buyIn: Fiat(
                    quarks:       row[t.buyInQuarks],
                    currencyCode: row[t.buyInCurrency]
                ),
                
                isOpen:         row[t.isOpen],
                isHost:         row[t.isHost],
                closedDate:     row[t.closedDate],
                rendezvous:     rendezvous,
                resolution: row[t.resolution],
                
                betCountYes:                     row[t.betsCountYes],
                betCountNo:                      row[t.betsCountNo],
                derivationIndex:                 row[t.derivationIndex],
                isFundingDestinationInitialized: row[t.isFundingDestinationInitialized],
                userOutcome:                     userOutcome(for: row, t: t)
            )
        }
        
        return pools
    }
    
    func getHostedPoolsWithoutRendezvousKeys() throws -> [(PublicKey, Int)] {
        let statement = try reader.prepareRowIterator("""
        SELECT
            p.id,
            p.derivationIndex
        FROM
            pool p
        WHERE
            p.isHost AND p.rendezvousSeed IS NULL
        LIMIT 1024;
        """)
        
        let t = PoolTable()
        
        let pools = try statement.map { row in
            (row[t.id], row[t.derivationIndex])
        }
        
        return pools
    }
    
    // MARK: - Insert Pools -
    
    func insertPool(pool: PoolDescription, rendezvous: KeyPair?, currentUserID: UserID) throws {
        let metadata       = pool.metadata
        let additionalInfo = pool.additionalInfo
        
        let t = PoolTable()
        var setters: [Setter] = [
            t.id             <- metadata.id,
            t.fundingAccount <- metadata.fundingAccount,
            t.creatorUserID  <- metadata.creatorUserID,
            t.creationDate   <- metadata.creationDate,
            t.closedDate     <- metadata.closedDate,
            t.isOpen         <- metadata.isOpen,
            t.isHost         <- currentUserID == metadata.creatorUserID,
            t.name           <- metadata.name,
            t.buyInQuarks    <- metadata.buyIn.quarks,
            t.buyInCurrency  <- metadata.buyIn.currencyCode,
            
            t.betsCountYes                    <- additionalInfo.betCountYes,
            t.betsCountNo                     <- additionalInfo.betCountNo,
            t.derivationIndex                 <- additionalInfo.derivationIndex,
            t.isFundingDestinationInitialized <- additionalInfo.isFundingDestinationInitialized,
            t.userOutcome                     <- additionalInfo.userOutcome.intValue,
        ]
        
        if let outcomeAmount = additionalInfo.userOutcome.amount {
            setters.append(contentsOf: [
                t.userOutcomeQuarks   <- outcomeAmount.quarks,
                t.userOutcomeCurrency <- outcomeAmount.currencyCode,
            ])
        }
        
        if let resolution = metadata.resolution {
            setters.append(
                t.resolution <- resolution
            )
        }
        
        if let keyPair = metadata.rendezvous {
            setters.append(
                t.rendezvousSeed <- keyPair.seed,
            )
            
        } else if let rendezvous, rendezvous.publicKey == metadata.id {
            // When opening a pool from a deeplink, we'll the option to
            // provide the rendezvous key directly, but we'll ensure that
            // it matches the pool metadata ID first
            setters.append(
                t.rendezvousSeed <- rendezvous.seed,
            )
        }
        
        try writer.run(
            t.table.upsert(setters, onConflictOf: t.id)
        )
    }
    
    func setRendezvousForPool(rendezvous: KeyPair) throws {
        let t = PoolTable()
        try writer.run(
            t.table
                .filter(t.id == rendezvous.publicKey)
                .update(t.rendezvousSeed <- rendezvous.seed)
        )
    }
    
    // MARK: - Get Bets -
    
    func betsToDistribute(for poolID: PublicKey, outcome: PoolResoltion) throws -> [StoredBet] {
        // Fetch all pool bets filtered by outcome,
        // in the event of of a tie, all bets will be
        // returned and therefore paid out
        let outcomeBets = try getBets(
            poolID: poolID,
            resolution: outcome
        )
        
        // If outcome bets is empty that means the
        // outcome had no bets and so we'll fetch
        // all the bets for the pool, which will
        // equivalent to a tie
        if outcomeBets.isEmpty {
            return try getBets(poolID: poolID)
        }
        
        return outcomeBets
    }
    
    func getBets(poolID: PublicKey, resolution: PoolResoltion? = nil) throws -> [StoredBet] {
        var filter = ""
        if let resolution, resolution != .refund {
            filter = "AND b.selectedOutcome = \(resolution.intValue)"
        }
        
        let statement = try reader.prepareRowIterator("""
        SELECT
            b.id,
            b.userID,
            b.payoutDestination,
            b.betDate,
            b.selectedOutcome,
            b.isFulfilled
        FROM
            bet b
        WHERE b.isFulfilled = 1 AND b.poolID = ? \(filter);
        """, bindings: Blob(bytes: poolID.bytes))
        
        let t = BetTable()
        
        let pools = try statement.map { row in
            StoredBet(
                id:                row[t.id],
                userID:            row[t.userID],
                payoutDestination: row[t.payoutDestination],
                betDate:           row[t.betDate],
                selectedOutcome:   row[t.selectedOutcome] == 1 ? .yes : .no,
                isFulfilled:       row[t.isFulfilled]
            )
        }
        
        return pools
    }
    
    // MARK: - Insert Bets -
    
    func insertBets(poolID: PublicKey, bets: [BetDescription]) throws {
        try bets.forEach {
            try insertBet(poolID: poolID, bet: $0)
        }
    }
    
    func insertBet(poolID: PublicKey, bet: BetDescription) throws {
        let metadata = bet.metadata
        let t = BetTable()
        let setters: [Setter] = [
            t.id                <- metadata.id,
            t.poolID            <- poolID,
            t.userID            <- metadata.userID,
            t.payoutDestination <- metadata.payoutDestination,
            t.betDate           <- metadata.betDate,
            t.selectedOutcome   <- metadata.selectedOutcome.intValue,
            t.isFulfilled       <- bet.isFulfilled,
        ]
        
        try writer.run(
            t.table.upsert(setters, onConflictOf: t.id)
        )
    }
    
    func setBetFulfilled(betID: PublicKey) throws {
        let t = BetTable()
        try writer.run(
            t.table
                .filter(t.id == betID)
                .update(t.isFulfilled <- true)
        )
    }
}
