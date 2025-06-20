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
