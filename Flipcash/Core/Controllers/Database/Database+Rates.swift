//
//  Database+Rates.swift
//  Code
//
//  Created by Dima Bart on 2025-04-11.
//

import Foundation
import FlipcashCore
import SQLite

extension Database {
    
    // MARK: - Get -
    
    func rate(for currency: CurrencyCode) throws -> Rate? {
        try getRate(currency: currency.rawValue)
    }
    
    private func getRate(currency: String) throws -> Rate? {
        let statement = try reader.prepareRowIterator("""
        SELECT
            r.currency,
            r.fx
        FROM
            rate r
        WHERE
            r.currency = "\(currency)"
        LIMIT 1;
        """)
        
        let rTable = RateTable()
        
        let rates = try statement.map { row in
            Rate.init(
                fx: Decimal(row[rTable.fx]),
                currency: try CurrencyCode(currencyCode: row[rTable.currency])
            )
        }
        
        return rates.first
    }
    
    // MARK: - Insert -
    
    func insert(snapshot: RatesSnapshot) throws {
        try transaction {
            for rate in snapshot.rates {
                try $0.insertRate(
                    rate: rate,
                    date: snapshot.date
                )
            }
        }
    }
    
    func insert(mints: [MintMetadata], date: Date) throws {
        try transaction {
            for mint in mints {
                try $0.insert(mint: mint, date: date)
            }
        }
    }
    
    private func insert(mint: MintMetadata, date: Date) throws {
        let table = MintTable()
        try writer.run(
            table.table.upsert(
                table.mint              <- mint.address,
                table.name              <- mint.name,
                table.symbol            <- mint.symbol,
                table.decimals          <- mint.decimals,
                table.bio               <- mint.description,
                table.imageURL          <- mint.imageURL,
                
                table.vmAddress         <- mint.vmMetadata?.vm,
                table.vmAuthority       <- mint.vmMetadata?.authority,
                table.lockDuration      <- mint.vmMetadata?.lockDurationInDays,
                
                table.currencyConfig    <- mint.launchpadMetadata?.currencyConfig,
                table.liquidityPool     <- mint.launchpadMetadata?.liquidityPool,
                table.seed              <- mint.launchpadMetadata?.seed,
                table.authority         <- mint.launchpadMetadata?.authority,
                table.mintVault         <- mint.launchpadMetadata?.mintVault,
                table.coreMintVault     <- mint.launchpadMetadata?.coreMintVault,
                table.coreMintFees      <- mint.launchpadMetadata?.coreMintFees,
                table.supplyFromBonding <- mint.launchpadMetadata?.supplyFromBonding,
                table.coreMintLocked    <- mint.launchpadMetadata?.coreMintLocked,
                table.sellFeeBps        <- mint.launchpadMetadata?.sellFeeBps,
                
                table.updatedAt         <- date,
                
                onConflictOf: table.mint,
            )
        )
    }
    
    private func insertRate(rate: Rate, date: Date) throws {
        let table = RateTable()
        try writer.run(
            table.table.upsert(
                table.currency <- rate.currency.rawValue,
                table.fx       <- rate.fx.doubleValue,
                table.date     <- date,
                
                onConflictOf: table.currency,
            )
        )
    }
}
