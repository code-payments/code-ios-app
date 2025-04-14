//
//  Schema.swift
//  Code
//
//  Created by Dima Bart on 2025-04-11.
//

import Foundation
import FlipcashCore
@preconcurrency import SQLite

struct RateTable: Sendable {
    static let name = "rate"
    
    let table        = Table(Self.name)
    let currency     = Expression <String> ("currency")
    let fx           = Expression <Double> ("fx")
    let date         = Expression <Date>   ("updatedAt")
}

extension Expression {
    func alias(_ alias: String) -> Expression<Datatype> {
        Expression(alias)
    }
    
    func casting<T>(to type: T.Type) -> Expression<T> {
        Expression<T>(template)
    }
}

// MARK: - Tables -

extension Database {
    func createTablesIfNeeded() throws {
        let rateTable = RateTable()
        
        try writer.transaction {
            try writer.run(rateTable.table.create(ifNotExists: true, withoutRowid: true) { t in
                t.column(rateTable.currency, primaryKey: true)
                t.column(rateTable.fx)
                t.column(rateTable.date)
            })
        }
        
        try createIndexesIfNeeded()
    }
    
    private func createIndexesIfNeeded() throws {
        
    }
}
