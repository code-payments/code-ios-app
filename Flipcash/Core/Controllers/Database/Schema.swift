//
//  Schema.swift
//  Code
//
//  Created by Dima Bart on 2025-04-11.
//

import Foundation
import FlipcashCore
@preconcurrency import SQLite

struct BalanceTable: Sendable {
    static let name = "balance"

    let table        = Table(Self.name)
    let quarks       = Expression <UInt64>    ("quarks")
    let mint         = Expression <PublicKey> ("mint")
    let costBasis    = Expression <Double?>   ("costBasis")
    let updatedAt    = Expression <Date>      ("updatedAt")
}

struct MintTable: Sendable {
    static let name = "mint"
    
    let table        = Table(Self.name)
    let mint         = Expression <PublicKey> ("mint")
    let name         = Expression <String>    ("name")
    let symbol       = Expression <String>    ("symbol")
    let decimals     = Expression <Int>       ("decimals")
    let bio          = Expression <String?>   ("bio")
    let imageURL     = Expression <URL?>      ("imageURL")
    
    let vmAddress    = Expression <PublicKey?> ("vmAddress")
    let vmAuthority  = Expression <PublicKey?> ("vmAuthority")
    let lockDuration = Expression <Int?>       ("lockDuration")
    
    let currencyConfig    = Expression <PublicKey?> ("currencyConfig")
    let liquidityPool     = Expression <PublicKey?> ("liquidityPool")
    let seed              = Expression <PublicKey?> ("seed")
    let authority         = Expression <PublicKey?> ("authority")
    let mintVault         = Expression <PublicKey?> ("mintVault")
    let coreMintVault     = Expression <PublicKey?> ("coreMintVault")
    let coreMintFees      = Expression <PublicKey?> ("coreMintFees")
    let supplyFromBonding = Expression <UInt64?>    ("supplyFromBonding")
    let coreMintLocked    = Expression <UInt64?>    ("coreMintLocked")
    let sellFeeBps        = Expression <Int?>       ("sellFeeBps")
    
    let updatedAt         = Expression <Date>       ("updatedAt")
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
    let mint         = Expression <PublicKey>    ("mint")
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
        let balanceTable          = BalanceTable()
        let mintTable             = MintTable()
        let activityTable         = ActivityTable()
        let cashLinkMetadataTable = CashLinkMetadataTable()

        try writer.transaction {
            try writer.run(balanceTable.table.create(ifNotExists: true, withoutRowid: true) { t in
                t.column(balanceTable.mint, primaryKey: true)
                t.column(balanceTable.quarks)
                t.column(balanceTable.costBasis)
                t.column(balanceTable.updatedAt)
            })

            // Migration: add costBasis column if it doesn't exist
            _ = try? writer.run(balanceTable.table.addColumn(balanceTable.costBasis))
        }

        try writer.transaction {
            try writer.run(mintTable.table.create(ifNotExists: true, withoutRowid: true) { t in
                t.column(mintTable.mint, primaryKey: true)
                t.column(mintTable.name)
                t.column(mintTable.symbol)
                t.column(mintTable.decimals)
                t.column(mintTable.bio)
                t.column(mintTable.imageURL)
                
                t.column(mintTable.vmAddress)
                t.column(mintTable.vmAuthority)
                t.column(mintTable.lockDuration)
                
                t.column(mintTable.currencyConfig)
                t.column(mintTable.liquidityPool)
                t.column(mintTable.seed)
                t.column(mintTable.authority)
                t.column(mintTable.mintVault)
                t.column(mintTable.coreMintVault)
                t.column(mintTable.coreMintFees)
                t.column(mintTable.supplyFromBonding)
                t.column(mintTable.coreMintLocked)
                t.column(mintTable.sellFeeBps)
                
                t.column(mintTable.updatedAt)
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
                t.column(activityTable.mint)
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

extension Key32: @retroactive Value {
    public static var declaredDatatype: String {
        Blob.declaredDatatype
    }

    public static func fromDatatypeValue(_ dataValue: Blob) -> Key32 {
        try! Key32(dataValue.bytes)
    }

    public var datatypeValue: Blob {
        Blob(bytes: bytes)
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

