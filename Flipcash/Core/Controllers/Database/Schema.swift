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

struct ActivityTable: Sendable {
    static let name = "activity"
    
    let table        = Table(Self.name)
    let id           = Expression <PublicKey>    ("id")
    let kind         = Expression <Int>          ("kind")
    let state        = Expression <Int>          ("state")
    let title        = Expression <String>       ("title")
    let quarks       = Expression <UInt64>       ("quarks")
    let nativeAmount = Expression <Double>       ("nativeAmount")
    let currency     = Expression <CurrencyCode> ("currency")
    let date         = Expression <Date>         ("date")
}

struct CashLinkMetadataTable: Sendable {
    static let name = "cashLinkMetadata"
    
    let table        = Table(Self.name)
    let id           = Expression <PublicKey> ("id")
    let vault        = Expression <PublicKey> ("vault")
    let canCancel    = Expression <Bool>      ("canCancel")
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
        let activityTable = ActivityTable()
        let cashLinkMetadataTable = CashLinkMetadataTable()
        
        try writer.transaction {
            try writer.run(rateTable.table.create(ifNotExists: true, withoutRowid: true) { t in
                t.column(rateTable.currency, primaryKey: true)
                t.column(rateTable.fx)
                t.column(rateTable.date)
            })
        }
        
        try writer.transaction {
            try writer.run(activityTable.table.create(ifNotExists: true, withoutRowid: true) { t in
                t.column(activityTable.id, primaryKey: true)
                t.column(activityTable.kind)
                t.column(activityTable.state)
                t.column(activityTable.title)
                t.column(activityTable.quarks)
                t.column(activityTable.nativeAmount)
                t.column(activityTable.currency)
                t.column(activityTable.date)
            })
        }
        
        try writer.transaction {
            try writer.run(cashLinkMetadataTable.table.create(ifNotExists: true, withoutRowid: true) { t in
                t.column(cashLinkMetadataTable.id, primaryKey: true)
                t.column(cashLinkMetadataTable.vault)
                t.column(cashLinkMetadataTable.canCancel)
                
                t.foreignKey(cashLinkMetadataTable.id, references: activityTable.table, activityTable.id, delete: .cascade)
            })
        }
        
        try createIndexesIfNeeded()
    }
    
    private func createIndexesIfNeeded() throws {
        
    }
}

// MARK: - Value -

extension UInt64: @retroactive Value {
    public static var declaredDatatype: String {
        Int64.declaredDatatype
    }

    public static func fromDatatypeValue(_ dataValue: Int64) -> UInt64 {
        UInt64(dataValue)
    }

    public var datatypeValue: Int64 {
        Int64(self)
    }
}

extension PublicKey: @retroactive Value {
    public static var declaredDatatype: String {
        String.declaredDatatype
    }

    public static func fromDatatypeValue(_ dataValue: String) -> PublicKey {
        PublicKey(base58: dataValue)!
    }

    public var datatypeValue: String {
        base58
    }
}

extension CurrencyCode: @retroactive Value {
    public static var declaredDatatype: String {
        String.declaredDatatype
    }

    public static func fromDatatypeValue(_ dataValue: String) -> CurrencyCode {
        try! CurrencyCode(currencyCode: dataValue)
    }

    public var datatypeValue: String {
        rawValue
    }
}
