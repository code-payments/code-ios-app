//
//  RatesStore.swift
//  Code
//
//  Created by Dima Bart on 2025-04-11.
//

import Foundation
import FlipcashCore
import SQLite

extension Database {
    
    func rate(for currency: CurrencyCode) throws -> Rate? {
        try getRate(currency: currency.rawValue)
    }
    
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
}

private extension Database {
    
    func getRate(currency: String) throws -> Rate? {
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
    
    func insertRate(rate: Rate, date: Date) throws {
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
