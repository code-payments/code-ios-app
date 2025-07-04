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
    
    func getPool(poolID: PublicKey) throws -> PoolContainer? {
        let statement = try reader.prepareRowIterator("""
        SELECT
            p.id,
            p.fundingAccount,
            p.creatorUserID,
            p.creationDate,
            p.closedDate,
            p.isOpen,
            p.name,
            p.buyInQuarks,
            p.buyInCurrency,
            p.resolution,
            p.rendezvousSeed,
        
            p.betsCountYes,
            p.betsCountNo,
            p.derivationIndex,
            p.isFundingDestinationInitialized
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
            
            return PoolContainer(
                metadata: PoolMetadata(
                    id:             row[t.id],
                    rendezvous:     rendezvous,
                    fundingAccount: row[t.fundingAccount],
                    creatorUserID:  row[t.creatorUserID],
                    creationDate:   row[t.creationDate],
                    closedDate:     row[t.closedDate],
                    isOpen:         row[t.isOpen],
                    name:           row[t.name],
                    buyIn: Fiat(
                        quarks:       row[t.buyInQuarks],
                        currencyCode: row[t.buyInCurrency]
                    ),
                    resolution: row[t.resolution]
                ),
                info: PoolInfo(
                    betCountYes:                     row[t.betsCountYes],
                    betCountNo:                      row[t.betsCountNo],
                    derivationIndex:                 row[t.derivationIndex],
                    isFundingDestinationInitialized: row[t.isFundingDestinationInitialized]
                )
            )
        }
        
        return pools.first
    }
    
    func getPools() throws -> [PoolContainer] {
        let statement = try reader.prepareRowIterator("""
        SELECT
            p.id,
            p.fundingAccount,
            p.creatorUserID,
            p.creationDate,
            p.closedDate,
            p.isOpen,
            p.name,
            p.buyInQuarks,
            p.buyInCurrency,
            p.resolution,
            p.rendezvousSeed,
        
            p.betsCountYes,
            p.betsCountNo,
            p.derivationIndex,
            p.isFundingDestinationInitialized
        FROM pool p
        ORDER BY p.creationDate DESC
        LIMIT 1024;
        """)
        
        let t = PoolTable()
        
        let pools = try statement.map { row in
            var rendezvous: KeyPair?
            if let seed = row[t.rendezvousSeed] {
                rendezvous = KeyPair(seed: seed)
            }
            
            return PoolContainer(
                metadata: PoolMetadata(
                    id:             row[t.id],
                    rendezvous:     rendezvous,
                    fundingAccount: row[t.fundingAccount],
                    creatorUserID:  row[t.creatorUserID],
                    creationDate:   row[t.creationDate],
                    closedDate:     row[t.closedDate],
                    isOpen:         row[t.isOpen],
                    name:           row[t.name],
                    buyIn: Fiat(
                        quarks:       row[t.buyInQuarks],
                        currencyCode: row[t.buyInCurrency]
                    ),
                    resolution: row[t.resolution]
                ),
                info: PoolInfo(
                    betCountYes:                     row[t.betsCountYes],
                    betCountNo:                      row[t.betsCountNo],
                    derivationIndex:                 row[t.derivationIndex],
                    isFundingDestinationInitialized: row[t.isFundingDestinationInitialized]
                )
            )
        }
        
        return pools
    }
    
    func getHostedPoolsWithoutRendezvousKeys(hostID: UUID) throws -> [(PublicKey, Int)] {
        let statement = try reader.prepareRowIterator("""
        SELECT
            p.id,
            p.derivationIndex
        FROM
            pool p
        WHERE
            creatorUserID = ? AND rendezvousSeed IS NULL
        LIMIT 1024;
        """, bindings: hostID.uuidString)
        
        let t = PoolTable()
        
        let pools = try statement.map { row in
            (row[t.id], row[t.derivationIndex])
        }
        
        return pools
    }
    
    // MARK: - Insert Pools -
    
    func insertPool(pool: PoolDescription) throws {
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
            t.name           <- metadata.name,
            t.buyInQuarks    <- metadata.buyIn.quarks,
            t.buyInCurrency  <- metadata.buyIn.currencyCode,
            
            t.betsCountYes                    <- additionalInfo.betCountYes,
            t.betsCountNo                     <- additionalInfo.betCountNo,
            t.derivationIndex                 <- additionalInfo.derivationIndex,
            t.isFundingDestinationInitialized <- additionalInfo.isFundingDestinationInitialized,
        ]
        
        if let resolution = metadata.resolution {
            setters.append(
                t.resolution <- resolution
            )
        }
        
        if let keyPair = metadata.rendezvous {
            setters.append(
                t.rendezvousSeed <- keyPair.seed,
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

    func getBets(poolID: PublicKey) throws -> [BetMetadata] {
        let statement = try reader.prepareRowIterator("""
        SELECT
            b.id,
            b.userID,
            b.payoutDestination,
            b.betDate,
            b.selectedOutcome
        FROM
            bet b
        WHERE b.poolID = ?;
        """, bindings: Blob(bytes: poolID.bytes))
        
        let t = BetTable()
        
        let pools = try statement.map { row in
            BetMetadata(
                id: row[t.id],
                userID: row[t.userID],
                payoutDestination: row[t.payoutDestination],
                betDate: row[t.betDate],
                selectedOutcome: row[t.selectedOutcome] == 1 ? .yes : .no
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

struct PoolContainer: Identifiable, Sendable, Equatable, Hashable {
    
    let metadata: PoolMetadata
    let info: PoolInfo
    
    var id: PublicKey {
        metadata.id
    }
    
    var amountInPool: Fiat {
        Fiat(
            quarks: metadata.buyIn.quarks * UInt64(info.betCountYes + info.betCountNo),
            currencyCode: metadata.buyIn.currencyCode
        )
    }
    
    var countOnYes: Int {
        info.betCountYes
    }
    
    var countOnNo: Int {
        info.betCountNo
    }
    
    var winningsForYes: Fiat? {
        guard countOnYes > 0 else { return nil }
        return Fiat(
            quarks: amountInPool.quarks / UInt64(countOnYes),
            currencyCode: metadata.buyIn.currencyCode
        )
    }
    
    var winningsForNo: Fiat? {
        guard countOnNo > 0 else { return nil }
        return Fiat(
            quarks: amountInPool.quarks / UInt64(countOnNo),
            currencyCode: metadata.buyIn.currencyCode
        )
    }
    
    var winningPayout: Fiat? {
        if let resolution = metadata.resolution {
            switch resolution {
            case .yes:
                return winningsForYes
            case .no:
                return winningsForNo
            case .refund:
                return metadata.buyIn
            }
        }
        return nil
    }
    
    var amountOnYes: Fiat {
        Fiat(
            quarks: metadata.buyIn.quarks * UInt64(countOnYes),
            currencyCode: metadata.buyIn.currencyCode
        )
    }
    
    var amountOnNo: Fiat {
        Fiat(
            quarks: metadata.buyIn.quarks * UInt64(countOnNo),
            currencyCode: metadata.buyIn.currencyCode
        )
    }
}
