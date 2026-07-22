//
//  Schema.swift
//  Code
//
//  Created by Dima Bart on 2025-04-11.
//

import Foundation
import FlipcashCore
// @preconcurrency: SQLite.swift's Table and Expression not Sendable upstream.
@preconcurrency import SQLite

nonisolated struct BalanceTable: Sendable {
    static let name = "balance"

    let table        = Table(Self.name)
    let quarks       = Expression <UInt64>    ("quarks")
    let mint         = Expression <PublicKey> ("mint")
    let costBasis    = Expression <Double?>   ("costBasis")
    let updatedAt    = Expression <Date>      ("updatedAt")
}

nonisolated struct MintTable: Sendable {
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
    let sellFeeBps        = Expression <Int?>       ("sellFeeBps")

    let socialLinks       = Expression <String?>    ("socialLinks")
    let billColors        = Expression <String?>    ("billColors")

    let createdAt         = Expression <Date?>      ("createdAt")

    let updatedAt         = Expression <Date>       ("updatedAt")
}


nonisolated struct ActivityTable: Sendable {
    static let name = "activity"

    let table        = Table(Self.name)
    let id           = Expression <PublicKey>    ("id")
    let kind         = Expression <Int>          ("kind")
    let state        = Expression <Int>          ("state")
    let title        = Expression <String>       ("title")
    let quarks       = Expression <UInt64>       ("quarks")       // on-chain mint-native quarks
    let nativeAmount = Expression <Double>       ("nativeAmount")
    let currency     = Expression <CurrencyCode> ("currency")
    let mint         = Expression <PublicKey>    ("mint")
    let date         = Expression <Date>         ("date")
}

nonisolated struct CashLinkMetadataTable: Sendable {
    static let name = "cashLinkMetadata"

    let table        = Table(Self.name)
    let id           = Expression <PublicKey> ("id")
    let vault        = Expression <PublicKey> ("vault")
    let canCancel    = Expression <Bool>      ("canCancel")
}

nonisolated struct LimitsTable: Sendable {
    static let name = "limits"

    let table = Table(Self.name)
    let id    = Expression <Int>  ("id")
    let data  = Expression <Data> ("data")
}

nonisolated struct RateTable: Sendable {
    static let name = "rate"

    let table    = Table(Self.name)
    let currency = Expression <CurrencyCode> ("currency")
    let data     = Expression <Data>         ("data")
}

// Verified exchange-rate proofs, one per fiat currency.
nonisolated struct VerifiedRateTable: Sendable {
    static let name = "verified_rate"

    let table      = Table(Self.name)
    let currency   = Expression <String> ("currency")
    let rateProto  = Expression <Data>   ("rateProto")
}

nonisolated struct ProfileTable: Sendable {
    static let name = "profile"

    let table = Table(Self.name)
    let id    = Expression <Int>  ("id")
    let data  = Expression <Data> ("data")
}

nonisolated struct UserFlagsTable: Sendable {
    static let name = "userFlags"

    let table = Table(Self.name)
    let id    = Expression <Int>  ("id")
    let data  = Expression <Data> ("data")
}

// Verified reserve-state proofs, one per mint.
nonisolated struct VerifiedReserveTable: Sendable {
    static let name = "verified_reserve"

    let table        = Table(Self.name)
    let mint         = Expression <String> ("mint")
    let reserveProto = Expression <Data>   ("reserveProto")
}

// Single-row table holding the contact-sync state machine cursor.
// Primary key is always 1.
nonisolated struct ContactSyncStateTable: Sendable {
    static let name = "contact_sync_state"

    let table         = Table(Self.name)
    let id            = Expression <Int>   ("id")
    let checksum      = Expression <Data?> ("checksum")
}

// E.164 phones the server has confirmed are on Flipcash.
nonisolated struct FlipcashContactTable: Sendable {
    static let name = "flipcash_contact"

    let table     = Table(Self.name)
    let e164      = Expression <String> ("e164")
    let dmChatId  = Expression <Data?>  ("dmChatId")
    let joinTs    = Expression <Date?>  ("joinTs")
    let matchedAt = Expression <Date>   ("matchedAt")
}

// Last contact set uploaded to the server. Joined with CNContactStore at
// render time via `contactId` so name/avatar resolution stays current.
nonisolated struct LocalContactsSnapshotTable: Sendable {
    static let name = "local_contacts_snapshot"

    let table     = Table(Self.name)
    let e164      = Expression <String> ("e164")
    let contactId = Expression <String> ("contactId")
}

// DM conversation feed. Members and messages live in their own tables; the
// feed's last-message preview is the newest row in `conversation_message`.
// Dates are stored as raw `timeIntervalSinceReferenceDate` doubles — decoding
// is a struct init instead of the bundled codec's per-row DateFormatter parse.
nonisolated struct ConversationTable: Sendable {
    static let name = "conversation"

    let table        = Table(Self.name)
    let id           = Expression <Data>    ("id")          // 32-byte ChatId
    let lastActivity = Expression <Double>  ("lastActivity")
    // Highest contiguous event-log sequence applied for this chat — the resume
    // point passed to GetDelta. Nil until the first catch-up establishes one.
    let catchupCursor = Expression <UInt64?> ("catchupCursor")
    // ConversationType raw value; scopes feed replaces and the Tips surfaces.
    let type          = Expression <Int>     ("type")
}

nonisolated struct ConversationMemberTable: Sendable {
    static let name = "conversation_member"

    let table                 = Table(Self.name)
    let conversationId        = Expression <Data>    ("conversationId")
    let userId                = Expression <UUID?>   ("userId")
    let displayName           = Expression <String>  ("displayName")
    let phoneE164             = Expression <String?> ("phoneE164")
    let readPointer           = Expression <UInt64?> ("readPointer")
    let readPointerTimestamp  = Expression <Double?> ("readPointerTimestamp")
    // Profile-picture rendition blob ids, when the member has a picture.
    let profilePictureBlobID          = Expression <Data?> ("profilePictureBlobID")
    let profilePictureThumbnailBlobID = Expression <Data?> ("profilePictureThumbnailBlobID")
}

// One row per message; cash content is decomposed across the amount columns
// the same way `activity` stores ExchangedFiat.
nonisolated struct ConversationMessageTable: Sendable {
    static let name = "conversation_message"

    let table          = Table(Self.name)
    let conversationId = Expression <Data>          ("conversationId")
    let id             = Expression <UInt64>        ("id")
    let senderId       = Expression <UUID?>         ("senderId")
    let kind           = Expression <Int>           ("kind")
    let text           = Expression <String?>       ("text")
    let quarks         = Expression <UInt64?>       ("quarks")
    let nativeAmount   = Expression <String?>       ("nativeAmount")
    let currency       = Expression <CurrencyCode?> ("currency")
    let mint           = Expression <PublicKey?>    ("mint")
    let date           = Expression <Double>        ("date")
    let unreadSeq      = Expression <UInt64>        ("unreadSeq")
    // Event-log version of this message's current state; the store applies
    // last-writer-wins by it. Zero for legacy/optimistic rows.
    let eventSequence  = Expression <UInt64>        ("eventSequence")
    // Stable client identity of an optimistic send, carried onto the server row it reconciles to so a
    // row keeps one identity across sending → sent and survives a DB round-trip.
    let clientMessageID = Expression <UUID?>        ("clientMessageID")
}


// MARK: - Tables -

nonisolated extension Database {
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
                t.column(mintTable.sellFeeBps)

                t.column(mintTable.socialLinks)
                t.column(mintTable.billColors)

                t.column(mintTable.createdAt)

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

        let limitsTable = LimitsTable()

        try writer.transaction {
            try writer.run(limitsTable.table.create(ifNotExists: true, withoutRowid: true) { t in
                t.column(limitsTable.id, primaryKey: true)
                t.column(limitsTable.data)
            })
        }

        let rateTable = RateTable()

        try writer.transaction {
            try writer.run(rateTable.table.create(ifNotExists: true, withoutRowid: true) { t in
                t.column(rateTable.currency, primaryKey: true)
                t.column(rateTable.data)
            })
        }

        let verifiedRateTable = VerifiedRateTable()

        try writer.transaction {
            try writer.run(verifiedRateTable.table.create(ifNotExists: true, withoutRowid: true) { t in
                t.column(verifiedRateTable.currency, primaryKey: true)
                t.column(verifiedRateTable.rateProto)
            })
        }

        let verifiedReserveTable = VerifiedReserveTable()

        try writer.transaction {
            try writer.run(verifiedReserveTable.table.create(ifNotExists: true, withoutRowid: true) { t in
                t.column(verifiedReserveTable.mint, primaryKey: true)
                t.column(verifiedReserveTable.reserveProto)
            })
        }

        let profileTable = ProfileTable()

        try writer.transaction {
            try writer.run(profileTable.table.create(ifNotExists: true, withoutRowid: true) { t in
                t.column(profileTable.id, primaryKey: true)
                t.column(profileTable.data)
            })
        }

        let userFlagsTable = UserFlagsTable()

        try writer.transaction {
            try writer.run(userFlagsTable.table.create(ifNotExists: true, withoutRowid: true) { t in
                t.column(userFlagsTable.id, primaryKey: true)
                t.column(userFlagsTable.data)
            })
        }

        let contactSyncStateTable = ContactSyncStateTable()

        try writer.transaction {
            try writer.run(contactSyncStateTable.table.create(ifNotExists: true, withoutRowid: true) { t in
                t.column(contactSyncStateTable.id, primaryKey: true)
                t.column(contactSyncStateTable.checksum)
            })
        }

        let flipcashContactTable = FlipcashContactTable()

        try writer.transaction {
            try writer.run(flipcashContactTable.table.create(ifNotExists: true, withoutRowid: true) { t in
                t.column(flipcashContactTable.e164, primaryKey: true)
                t.column(flipcashContactTable.dmChatId)
                t.column(flipcashContactTable.joinTs)
                t.column(flipcashContactTable.matchedAt)
            })
        }

        let localContactsSnapshotTable = LocalContactsSnapshotTable()

        try writer.transaction {
            // Composite PK (e164, contactId): the same phone number may
            // appear on multiple address-book contacts (a household
            // landline, a shop number on several cards). The picker shows
            // every (name, number) pair, so the snapshot has to preserve
            // them all.
            try writer.run(localContactsSnapshotTable.table.create(ifNotExists: true, withoutRowid: true) { t in
                t.column(localContactsSnapshotTable.e164)
                t.column(localContactsSnapshotTable.contactId)
                t.primaryKey(localContactsSnapshotTable.e164, localContactsSnapshotTable.contactId)
            })
        }

        let conversationTable = ConversationTable()

        try writer.transaction {
            try writer.run(conversationTable.table.create(ifNotExists: true, withoutRowid: true) { t in
                t.column(conversationTable.id, primaryKey: true)
                t.column(conversationTable.lastActivity)
                t.column(conversationTable.catchupCursor)
                t.column(conversationTable.type, defaultValue: ConversationType.contactDm.rawValue)
            })
        }

        let conversationMemberTable = ConversationMemberTable()

        try writer.transaction {
            // Rowid table: `userId` is nullable (the server may omit it), so it
            // can't join a WITHOUT ROWID primary key. Writes replace a
            // conversation's members wholesale.
            try writer.run(conversationMemberTable.table.create(ifNotExists: true) { t in
                t.column(conversationMemberTable.conversationId)
                t.column(conversationMemberTable.userId)
                t.column(conversationMemberTable.displayName)
                t.column(conversationMemberTable.phoneE164)
                t.column(conversationMemberTable.readPointer)
                t.column(conversationMemberTable.readPointerTimestamp)
                t.column(conversationMemberTable.profilePictureBlobID)
                t.column(conversationMemberTable.profilePictureThumbnailBlobID)
            })
        }

        let conversationMessageTable = ConversationMessageTable()

        try writer.transaction {
            try writer.run(conversationMessageTable.table.create(ifNotExists: true, withoutRowid: true) { t in
                t.column(conversationMessageTable.conversationId)
                t.column(conversationMessageTable.id)
                t.column(conversationMessageTable.senderId)
                t.column(conversationMessageTable.kind)
                t.column(conversationMessageTable.text)
                t.column(conversationMessageTable.quarks)
                t.column(conversationMessageTable.nativeAmount)
                t.column(conversationMessageTable.currency)
                t.column(conversationMessageTable.mint)
                t.column(conversationMessageTable.date)
                t.column(conversationMessageTable.unreadSeq)
                t.column(conversationMessageTable.eventSequence)
                t.column(conversationMessageTable.clientMessageID)
                t.primaryKey(conversationMessageTable.conversationId, conversationMessageTable.id)
            })
        }

    }
}

// MARK: - Value -

nonisolated extension UInt64: @retroactive Value {
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

nonisolated extension Key32: @retroactive Value {
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

nonisolated extension CurrencyCode: @retroactive Value {
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


