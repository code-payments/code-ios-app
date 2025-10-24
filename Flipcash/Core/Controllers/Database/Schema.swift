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

struct PoolTable: Sendable {
    static let name = "pool"
    
    let table                           = Table(Self.name)
    let id                              = Expression <PublicKey>      ("id")
    let rendezvousSeed                  = Expression <Seed32?>        ("rendezvousSeed")
    let fundingAccount                  = Expression <PublicKey>      ("fundingAccount")
    let creatorUserID                   = Expression <UUID>           ("creatorUserID")
    let creationDate                    = Expression <Date>           ("creationDate")
    let closedDate                      = Expression <Date?>          ("closedDate")
    let isOpen                          = Expression <Bool>           ("isOpen")
    let isHost                          = Expression <Bool>           ("isHost")
    let name                            = Expression <String>         ("name")
    let buyInQuarks                     = Expression <UInt64>         ("buyInQuarks")
    let buyInCurrency                   = Expression <CurrencyCode>   ("buyInCurrency")
    let resolution                      = Expression <PoolResoltion?> ("resolution")
    
    let betsCountYes                    = Expression <Int>            ("betsCountYes")
    let betsCountNo                     = Expression <Int>            ("betsCountNo")
    let derivationIndex                 = Expression <Int>            ("derivationIndex")
    let isFundingDestinationInitialized = Expression <Bool>           ("isFundingDestinationInitialized")
    let userOutcome                     = Expression <Int>            ("userOutcome")
    let userOutcomeQuarks               = Expression <UInt64?>        ("userOutcomeQuarks")
    let userOutcomeCurrency             = Expression <CurrencyCode?>  ("userOutcomeCurrency")
}

struct BetTable: Sendable {
    static let name = "bet"
    
    let table             = Table(Self.name)
    let id                = Expression <PublicKey> ("id")
    let poolID            = Expression <PublicKey> ("poolID")
    let userID            = Expression <UUID>      ("userID")
    let payoutDestination = Expression <PublicKey> ("payoutDestination")
    let betDate           = Expression <Date>      ("betDate")
    let selectedOutcome   = Expression <Int>       ("selectedOutcome") // 0 = no, 1 = yes, 2+ index of option
    let isFulfilled       = Expression <Bool>      ("isFulfilled")
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
        let rateTable             = RateTable()
        let mintTable             = MintTable()
        let activityTable         = ActivityTable()
        let cashLinkMetadataTable = CashLinkMetadataTable()
        let poolTable             = PoolTable()
        let betTable              = BetTable()
        
        try writer.transaction {
            try writer.run(balanceTable.table.create(ifNotExists: true, withoutRowid: true) { t in
                t.column(balanceTable.mint, primaryKey: true)
                t.column(balanceTable.quarks)
                t.column(balanceTable.updatedAt)
            })
        }
        
        try writer.transaction {
            try writer.run(rateTable.table.create(ifNotExists: true, withoutRowid: true) { t in
                t.column(rateTable.currency, primaryKey: true)
                t.column(rateTable.fx)
                t.column(rateTable.date)
            })
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
        
        try writer.transaction {
            try writer.run(poolTable.table.create(ifNotExists: true, withoutRowid: true) { t in
                t.column(poolTable.id, primaryKey: true)
                t.column(poolTable.fundingAccount)
                t.column(poolTable.creatorUserID)
                t.column(poolTable.creationDate)
                t.column(poolTable.closedDate)
                t.column(poolTable.isOpen)
                t.column(poolTable.isHost)
                t.column(poolTable.name)
                t.column(poolTable.buyInQuarks)
                t.column(poolTable.buyInCurrency)
                t.column(poolTable.resolution)
                t.column(poolTable.rendezvousSeed)
                
                t.column(poolTable.betsCountYes)
                t.column(poolTable.betsCountNo)
                t.column(poolTable.derivationIndex)
                t.column(poolTable.isFundingDestinationInitialized)
                t.column(poolTable.userOutcome)
                t.column(poolTable.userOutcomeQuarks)
                t.column(poolTable.userOutcomeCurrency)
            })
        }
        
        try writer.transaction {
            try writer.run(betTable.table.create(ifNotExists: true, withoutRowid: true) { t in
                t.column(betTable.id, primaryKey: true)
                t.column(betTable.poolID) // FK pool.id
                t.column(betTable.userID)
                t.column(betTable.payoutDestination)
                t.column(betTable.betDate)
                t.column(betTable.selectedOutcome)
                t.column(betTable.isFulfilled, defaultValue: false)
                
                t.foreignKey(betTable.poolID, references: poolTable.table, poolTable.id, delete: .cascade)
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

extension PoolResoltion: @retroactive Value {
    public static var declaredDatatype: String {
        Int64.declaredDatatype
    }

    public static func fromDatatypeValue(_ dataValue: Int64) -> PoolResoltion {
        PoolResoltion(intValue: Int(dataValue))!
    }

    public var datatypeValue: Int64 {
        Int64(intValue)
    }
}
