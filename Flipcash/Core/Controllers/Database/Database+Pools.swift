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
    
    // MARK: - Get -
    
    func getPool(poolID: PublicKey) throws -> PoolMetadata? {
        let statement = try reader.prepareRowIterator("""
        SELECT
            p.id,
            p.fundingAccount,
            p.creatorUserID,
            p.creationDate,
            p.isOpen,
            p.name,
            p.buyInQuarks,
            p.buyInCurrency,
            p.resolution,
            p.privateKeySeed
        FROM pool p
        WHERE p.id = ?
        LIMIT 1;
        """, bindings: Blob(bytes: poolID.bytes))
        
        let pTable = PoolTable()
        
        let pools = try statement.map { row in
            var rendezvous: KeyPair?
            if let seed = row[pTable.privateKeySeed] {
                rendezvous = KeyPair(seed: seed)
            }
            
            var resolution: PoolResoltion?
            if let result = row[pTable.resolution] {
                resolution = result ? .yes : .no
            }
            
            return PoolMetadata(
                id: row[pTable.id],
                rendezvous: rendezvous,
                fundingAccount: row[pTable.fundingAccount],
                creatorUserID: row[pTable.creatorUserID],
                creationDate: row[pTable.creationDate],
                isOpen: row[pTable.isOpen],
                name: row[pTable.name],
                buyIn: Fiat(
                    quarks: row[pTable.buyInQuarks],
                    currencyCode: row[pTable.buyInCurrency]
                ),
                resolution: resolution
            )
        }
        
        return pools.first
    }
    
    func getPools() throws -> [PoolMetadata] {
        let statement = try reader.prepareRowIterator("""
        SELECT
            p.id,
            p.fundingAccount,
            p.creatorUserID,
            p.creationDate,
            p.isOpen,
            p.name,
            p.buyInQuarks,
            p.buyInCurrency,
            p.resolution,
            p.privateKeySeed
            
        FROM pool p
        
        ORDER BY p.creationDate DESC
        LIMIT 1024;
        """)
        
        let pTable = PoolTable()
        
        let pools = try statement.map { row in
            var rendezvous: KeyPair?
            if let seed = row[pTable.privateKeySeed] {
                rendezvous = KeyPair(seed: seed)
            }
            
            var resolution: PoolResoltion?
            if let result = row[pTable.resolution] {
                resolution = result ? .yes : .no
            }
            
            return PoolMetadata(
                id: row[pTable.id],
                rendezvous: rendezvous,
                fundingAccount: row[pTable.fundingAccount],
                creatorUserID: row[pTable.creatorUserID],
                creationDate: row[pTable.creationDate],
                isOpen: row[pTable.isOpen],
                name: row[pTable.name],
                buyIn: Fiat(
                    quarks: row[pTable.buyInQuarks],
                    currencyCode: row[pTable.buyInCurrency]
                ),
                resolution: resolution
            )
        }
        
        return pools
    }
    
    // MARK: - Insert -
    
    func insertPools(pools: [PoolMetadata]) throws {
        try pools.forEach {
            try insertPool(metadata: $0)
        }
    }
    
    func insertPool(metadata: PoolMetadata) throws {
        let table = PoolTable()
        var setters: [Setter] = [
            table.id             <- metadata.id,
            table.fundingAccount <- metadata.fundingAccount,
            table.creatorUserID  <- metadata.creatorUserID,
            table.creationDate   <- metadata.creationDate,
            table.isOpen         <- metadata.isOpen,
            table.name           <- metadata.name,
            table.buyInQuarks    <- metadata.buyIn.quarks,
            table.buyInCurrency  <- metadata.buyIn.currencyCode,
        ]
        
        if let resolution = metadata.resolution {
            setters.append(
                table.resolution <- (resolution == .yes) ? true : false
            )
        }
        
        if let keyPair = metadata.rendezvous {
            setters.append(
                table.privateKeySeed <- keyPair.seed,
            )
        }
        
        try writer.run(
            table.table.upsert(setters, onConflictOf: table.id)
        )
    }
}
