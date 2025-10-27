//
//  Database+Balance.swift
//  Code
//
//  Created by Dima Bart on 2025-04-11.
//

import Foundation
import FlipcashCore
import SQLite

extension Database {
    
    // MARK: - Get -
    
    func getBalances() throws -> [StoredBalance] {
        let statement = try reader.prepareRowIterator("""
        SELECT
            b.quarks,
            b.mint,
            b.updatedAt,
        
            m.symbol,
            m.name,
            m.imageURL,
            m.sellFeeBps,
            m.supplyFromBonding,
            m.coreMintLocked,
            m.vmAuthority
        FROM
            balance b
        
        LEFT JOIN mint m ON m.mint = b.mint
        
        ORDER BY b.quarks;
        """)
        
        let b = BalanceTable()
        let m = MintTable()
        
        let balances = try statement.map { row in
            try StoredBalance(
                quarks:            row[b.quarks],
                symbol:            row[m.symbol],
                name:              row[m.name],
                supplyFromBonding: row[m.supplyFromBonding],
                coreMintLocked:    row[m.coreMintLocked],
                sellFeeBps:        row[m.sellFeeBps],
                mint:              row[b.mint],
                vmAuthority:       row[m.vmAuthority],
                updatedAt:         row[b.updatedAt],
                imageURL:          row[m.imageURL]
            )
        }
        
        return balances
    }
    
    func getMintMetadata(mint: PublicKey) throws -> StoredMintMetadata? {
        let statement = try reader.prepareRowIterator("""
        SELECT
            m.mint,
            m.name,
            m.symbol,
            m.decimals,
            m.bio,
            m.imageURL,
            m.vmAddress,
            m.vmAuthority,
            m.lockDuration,
            m.currencyConfig,
            m.liquidityPool,
            m.seed,
            m.authority,
            m.mintVault,
            m.coreMintVault,
            m.coreMintFees,
            m.supplyFromBonding,
            m.coreMintLocked,
            m.sellFeeBps,
            m.updatedAt
        FROM
            mint m
        WHERE
            m.mint = ?
        LIMIT 1;
        """, bindings: Blob(bytes: mint.bytes))
        
        let m = MintTable()
        
        let mints = try statement.compactMap { row in
            StoredMintMetadata(
                mint:              row[m.mint],
                name:              row[m.name],
                symbol:            row[m.symbol],
                decimals:          row[m.decimals],
                bio:               row[m.bio],
                imageURL:          row[m.imageURL],
                vmAddress:         row[m.vmAddress],
                vmAuthority:       row[m.vmAuthority],
                lockDuration:      row[m.lockDuration],
                currencyConfig:    row[m.currencyConfig],
                liquidityPool:     row[m.liquidityPool],
                seed:              row[m.seed],
                authority:         row[m.authority],
                mintVault:         row[m.mintVault],
                coreMintVault:     row[m.coreMintVault],
                coreMintFees:      row[m.coreMintFees],
                supplyFromBonding: row[m.supplyFromBonding],
                coreMintLocked:    row[m.coreMintLocked],
                sellFeeBps:        row[m.sellFeeBps],
                updatedAt:         row[m.updatedAt]
            )
        }
        
        if mints.isEmpty {
            trace(.warning, components: "Missing mint in database: \(mint.base58)")
        }
        
        return mints.first
    }
    
    func getVMAuthority(mint: PublicKey) throws -> PublicKey? {
        let statement = try reader.prepareRowIterator("""
        SELECT
            m.vmAuthority
        FROM
            mint m
        WHERE
            m.mint = ?
        LIMIT 1;
        """, bindings: Blob(bytes: mint.bytes))
        
        let m = MintTable()
        
        let authority = try statement.compactMap { row in
            row[m.vmAuthority]
        }.first
        
        return authority
    }
    
    // MARK: - Insert -
    
    func insertBalance(quarks: UInt64, mint: PublicKey, date: Date) throws {
        let table = BalanceTable()
        try writer.run(
            table.table.upsert(
                table.mint      <- mint,
                table.quarks    <- quarks,
                table.updatedAt <- date,
                
                onConflictOf: table.mint,
            )
        )
    }
}
