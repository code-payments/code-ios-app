//
//  Schema.swift
//  Code
//
//  Created by Dima Bart on 2025-04-11.
//

import Foundation
import FlipcashCore
// @preconcurrency: SQLite.swift's Table and Expression not Sendable upstream.
@preconcurrency public import SQLite

nonisolated public struct BalanceTable: Sendable {
    public static let name = "balance"

    public init() {}

    public let table        = Table(Self.name)
    public let quarks       = Expression <UInt64>    ("quarks")
    public let mint         = Expression <PublicKey> ("mint")
    public let costBasis    = Expression <Double?>   ("costBasis")
    public let updatedAt    = Expression <Date>      ("updatedAt")
}

nonisolated public struct MintTable: Sendable {
    public static let name = "mint"

    public init() {}
    
    public let table        = Table(Self.name)
    public let mint         = Expression <PublicKey> ("mint")
    public let name         = Expression <String>    ("name")
    public let symbol       = Expression <String>    ("symbol")
    public let decimals     = Expression <Int>       ("decimals")
    public let bio          = Expression <String?>   ("bio")
    public let imageURL     = Expression <URL?>      ("imageURL")
    
    public let vmAddress    = Expression <PublicKey?> ("vmAddress")
    public let vmAuthority  = Expression <PublicKey?> ("vmAuthority")
    public let lockDuration = Expression <Int?>       ("lockDuration")
    
    public let currencyConfig    = Expression <PublicKey?> ("currencyConfig")
    public let liquidityPool     = Expression <PublicKey?> ("liquidityPool")
    public let seed              = Expression <PublicKey?> ("seed")
    public let authority         = Expression <PublicKey?> ("authority")
    public let mintVault         = Expression <PublicKey?> ("mintVault")
    public let coreMintVault     = Expression <PublicKey?> ("coreMintVault")
    public let coreMintFees      = Expression <PublicKey?> ("coreMintFees")
    public let supplyFromBonding = Expression <UInt64?>    ("supplyFromBonding")
    public let sellFeeBps        = Expression <Int?>       ("sellFeeBps")

    public let socialLinks       = Expression <String?>    ("socialLinks")
    public let billColors        = Expression <String?>    ("billColors")

    public let createdAt         = Expression <Date?>      ("createdAt")

    public let updatedAt         = Expression <Date>       ("updatedAt")
}


nonisolated public struct ActivityTable: Sendable {
    public static let name = "activity"

    public init() {}

    public let table        = Table(Self.name)
    public let id           = Expression <PublicKey>    ("id")
    public let kind         = Expression <Int>          ("kind")
    public let state        = Expression <Int>          ("state")
    public let title        = Expression <String>       ("title")
    public let quarks       = Expression <UInt64>       ("quarks")       // on-chain mint-native quarks
    public let nativeAmount = Expression <Double>       ("nativeAmount")
    public let currency     = Expression <CurrencyCode> ("currency")
    public let mint         = Expression <PublicKey>    ("mint")
    public let date         = Expression <Date>         ("date")
    // The peer on a send/receive, for feed-row avatar + name enrichment. Both
    // nil for non-peer activity (deposits, buys, withdrawals).
    public let counterpartyUserID = Expression <UUID?>   ("counterpartyUserID")
    public let counterpartyPhone  = Expression <String?> ("counterpartyPhone")
}

nonisolated public struct CashLinkMetadataTable: Sendable {
    public static let name = "cashLinkMetadata"

    public init() {}

    public let table        = Table(Self.name)
    public let id           = Expression <PublicKey> ("id")
    public let vault        = Expression <PublicKey> ("vault")
    public let canCancel    = Expression <Bool>      ("canCancel")
}

// Side table for `.swapped` activities: the two swap legs + fee. Joined 1:1 to
// `activity` by id. The destination amount columns are nullable — a swap that
// hasn't executed yet carries only its destination mint.
nonisolated public struct SwapMetadataTable: Sendable {
    public static let name = "swapMetadata"

    public init() {}

    public let table            = Table(Self.name)
    public let id               = Expression <PublicKey>     ("id")
    public let fromMint         = Expression <PublicKey>     ("fromMint")
    public let fromQuarks       = Expression <UInt64>        ("fromQuarks")
    public let fromNativeAmount = Expression <Double>        ("fromNativeAmount")
    public let fromCurrency     = Expression <CurrencyCode>  ("fromCurrency")
    public let toMint           = Expression <PublicKey>     ("toMint")
    public let toQuarks         = Expression <UInt64?>       ("toQuarks")
    public let toNativeAmount   = Expression <Double?>       ("toNativeAmount")
    public let toCurrency       = Expression <CurrencyCode?> ("toCurrency")
    public let feeNativeAmount  = Expression <Double>        ("feeNativeAmount")
    public let feeCurrency      = Expression <CurrencyCode>  ("feeCurrency")
    public let state            = Expression <Int>           ("state")
}

nonisolated public struct LimitsTable: Sendable {
    public static let name = "limits"

    public init() {}

    public let table = Table(Self.name)
    public let id    = Expression <Int>  ("id")
    public let data  = Expression <Data> ("data")
}

nonisolated public struct RateTable: Sendable {
    public static let name = "rate"

    public init() {}

    public let table    = Table(Self.name)
    public let currency = Expression <CurrencyCode> ("currency")
    public let data     = Expression <Data>         ("data")
}

// Verified exchange-rate proofs, one per fiat currency.
nonisolated public struct VerifiedRateTable: Sendable {
    public static let name = "verified_rate"

    public init() {}

    public let table      = Table(Self.name)
    public let currency   = Expression <String> ("currency")
    public let rateProto  = Expression <Data>   ("rateProto")
}

nonisolated public struct ProfileTable: Sendable {
    public static let name = "profile"

    public init() {}

    public let table = Table(Self.name)
    public let id    = Expression <Int>  ("id")
    public let data  = Expression <Data> ("data")
}

/// Cache of *other* users' profiles, keyed by user id. Populated cache-through
/// as profiles are fetched for display (chat counterparts, tip recipients,
/// blocked users). The signed-in user's own profile stays in the singleton
/// `profile` table. Stored as a JSON blob — reads are only ever by-key.
nonisolated public struct UserProfileTable: Sendable {
    public static let name = "user_profile"

    public init() {}

    public let table  = Table(Self.name)
    public let userID = Expression <UUID> ("userID")   // PK
    public let data   = Expression <Data> ("data")     // JSON-encoded Profile
}

nonisolated public struct UserFlagsTable: Sendable {
    public static let name = "userFlags"

    public init() {}

    public let table = Table(Self.name)
    public let id    = Expression <Int>  ("id")
    public let data  = Expression <Data> ("data")
}

nonisolated public struct BlocklistTable: Sendable {
    public static let name = "blocklist"

    public init() {}

    public let table          = Table(Self.name)
    public let userID         = Expression <UUID>    ("userID")        // PK
    public let blockedAt      = Expression <Double>  ("blockedAt")     // timeIntervalSinceReferenceDate
    public let displayName    = Expression <String>  ("displayName")
    public let avatarBlurhash = Expression <String?> ("avatarBlurhash")
}

// Verified reserve-state proofs, one per mint.
nonisolated public struct VerifiedReserveTable: Sendable {
    public static let name = "verified_reserve"

    public init() {}

    public let table        = Table(Self.name)
    public let mint         = Expression <String> ("mint")
    public let reserveProto = Expression <Data>   ("reserveProto")
}

// Single-row table holding the contact-sync state machine cursor.
// Primary key is always 1.
nonisolated public struct ContactSyncStateTable: Sendable {
    public static let name = "contact_sync_state"

    public init() {}

    public let table         = Table(Self.name)
    public let id            = Expression <Int>   ("id")
    public let checksum      = Expression <Data?> ("checksum")
}

// E.164 phones the server has confirmed are on Flipcash.
nonisolated public struct FlipcashContactTable: Sendable {
    public static let name = "flipcash_contact"

    public init() {}

    public let table     = Table(Self.name)
    public let e164      = Expression <String> ("e164")
    public let dmChatId  = Expression <Data?>  ("dmChatId")
    public let joinTs    = Expression <Date?>  ("joinTs")
    public let matchedAt = Expression <Date>   ("matchedAt")
}

// Last contact set uploaded to the server. Joined with CNContactStore at
// render time via `contactId` so name/avatar resolution stays current.
nonisolated public struct LocalContactsSnapshotTable: Sendable {
    public static let name = "local_contacts_snapshot"

    public init() {}

    public let table     = Table(Self.name)
    public let e164      = Expression <String> ("e164")
    public let contactId = Expression <String> ("contactId")
}

// DM conversation feed. Members and messages live in their own tables; the
// feed's last-message preview is the newest row in `conversation_message`.
// Dates are stored as raw `timeIntervalSinceReferenceDate` doubles — decoding
// is a struct init instead of the bundled codec's per-row DateFormatter parse.
nonisolated public struct ConversationTable: Sendable {
    public static let name = "conversation"

    public init() {}

    public let table        = Table(Self.name)
    public let id           = Expression <Data>    ("id")          // 32-byte ChatId
    public let lastActivity = Expression <Double>  ("lastActivity")
    // Highest contiguous event-log sequence applied for this chat — the resume
    // point passed to GetDelta. Nil until the first catch-up establishes one.
    public let catchupCursor = Expression <UInt64?> ("catchupCursor")
    // ConversationType raw value; scopes feed replaces and the Tips surfaces.
    public let type          = Expression <Int>     ("type")
    // Server-set: the counterpart is on the owner's blocklist. Retained so an
    // unblock restores the conversation; filtered from the displayed feed.
    public let isHidden      = Expression <Bool>    ("isHidden")
    // Server-set title, group chats only. Nil for DMs.
    public let title         = Expression <String?> ("title")
}

nonisolated public struct ConversationMemberTable: Sendable {
    public static let name = "conversation_member"

    public init() {}

    public let table                 = Table(Self.name)
    public let conversationId        = Expression <Data>    ("conversationId")
    public let userId                = Expression <UUID?>   ("userId")
    public let displayName           = Expression <String>  ("displayName")
    public let phoneE164             = Expression <String?> ("phoneE164")
    public let readPointer           = Expression <UInt64?> ("readPointer")
    public let readPointerTimestamp  = Expression <Double?> ("readPointerTimestamp")
    // Profile-picture rendition blob ids, when the member has a picture.
    public let profilePictureBlobID          = Expression <Data?>   ("profilePictureBlobID")
    public let profilePictureThumbnailBlobID = Expression <Data?>   ("profilePictureThumbnailBlobID")
    // The thumbnail rendition's BlurHash preview, when present.
    public let profilePictureThumbnailBlurhash = Expression <String?> ("profilePictureThumbnailBlurhash")
    // The member's claimed handle, when they have one. Carried on the same
    // profile the feed embeds, so it is cached rather than refetched.
    public let username = Expression <String?> ("username")
}

// One row per message; cash content is decomposed across the amount columns
// the same way `activity` stores ExchangedFiat.
nonisolated public struct ConversationMessageTable: Sendable {
    public static let name = "conversation_message"

    public init() {}

    public let table          = Table(Self.name)
    public let conversationId = Expression <Data>          ("conversationId")
    public let id             = Expression <UInt64>        ("id")
    public let senderId       = Expression <UUID?>         ("senderId")
    public let kind           = Expression <Int>           ("kind")
    public let text           = Expression <String?>       ("text")
    public let quarks         = Expression <UInt64?>       ("quarks")
    public let nativeAmount   = Expression <String?>       ("nativeAmount")
    public let currency       = Expression <CurrencyCode?> ("currency")
    public let mint           = Expression <PublicKey?>    ("mint")
    // Cash delivery action (0 = sent, 1 = tipped); nil for non-cash rows.
    public let cashAction     = Expression <Int?>          ("cashAction")
    public let date           = Expression <Double>        ("date")
    public let unreadSeq      = Expression <UInt64>        ("unreadSeq")
    // Event-log version of this message's current state; the store applies
    // last-writer-wins by it. Zero for legacy/optimistic rows.
    public let eventSequence  = Expression <UInt64>        ("eventSequence")
    // Stable client identity of an optimistic send, carried onto the server row it reconciles to so a
    // row keeps one identity across sending → sent and survives a DB round-trip.
    public let clientMessageID = Expression <UUID?>        ("clientMessageID")
    // Reserved for the reply feature: written as nil and ignored on read. The column exists now
    // because the schema version can only be bumped once per rebuild, and adding it later would
    // cost users a second full resync.
    public let repliedToId    = Expression <UInt64?>       ("repliedToId")
    // When the sender last edited this message; nil if never edited.
    public let lastEditedTs   = Expression <Double?>       ("lastEditedTs")
    // Tombstone detail. Both nil for a message that has not been deleted.
    public let deletedBy      = Expression <UUID?>         ("deletedBy")
    public let deletedAt      = Expression <Double?>       ("deletedAt")
}


// MARK: - Tables -

nonisolated extension Database {
    public func createTablesIfNeeded() throws {
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
                t.column(activityTable.counterpartyUserID)
                t.column(activityTable.counterpartyPhone)
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

        let swapMetadataTable = SwapMetadataTable()

        try writer.transaction {
            try writer.run(swapMetadataTable.table.create(ifNotExists: true, withoutRowid: true) { t in
                t.column(swapMetadataTable.id, primaryKey: true)
                t.column(swapMetadataTable.fromMint)
                t.column(swapMetadataTable.fromQuarks)
                t.column(swapMetadataTable.fromNativeAmount)
                t.column(swapMetadataTable.fromCurrency)
                t.column(swapMetadataTable.toMint)
                t.column(swapMetadataTable.toQuarks)
                t.column(swapMetadataTable.toNativeAmount)
                t.column(swapMetadataTable.toCurrency)
                t.column(swapMetadataTable.feeNativeAmount)
                t.column(swapMetadataTable.feeCurrency)
                t.column(swapMetadataTable.state)

                t.foreignKey(swapMetadataTable.id, references: activityTable.table, activityTable.id, delete: .cascade)
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

        let userProfileTable = UserProfileTable()

        try writer.transaction {
            try writer.run(userProfileTable.table.create(ifNotExists: true, withoutRowid: true) { t in
                t.column(userProfileTable.userID, primaryKey: true)
                t.column(userProfileTable.data)
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
                t.column(conversationTable.isHidden, defaultValue: false)
                t.column(conversationTable.title)
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
                t.column(conversationMemberTable.profilePictureThumbnailBlurhash)
                t.column(conversationMemberTable.username)
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
                t.column(conversationMessageTable.cashAction)
                t.column(conversationMessageTable.date)
                t.column(conversationMessageTable.unreadSeq)
                t.column(conversationMessageTable.eventSequence)
                t.column(conversationMessageTable.clientMessageID)
                t.column(conversationMessageTable.repliedToId)
                t.column(conversationMessageTable.lastEditedTs)
                t.column(conversationMessageTable.deletedBy)
                t.column(conversationMessageTable.deletedAt)
                t.primaryKey(conversationMessageTable.conversationId, conversationMessageTable.id)
            })
        }

        let blocklistTable = BlocklistTable()

        try writer.transaction {
            try writer.run(blocklistTable.table.create(ifNotExists: true, withoutRowid: true) { t in
                t.column(blocklistTable.userID, primaryKey: true)
                t.column(blocklistTable.blockedAt)
                t.column(blocklistTable.displayName)
                t.column(blocklistTable.avatarBlurhash)
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

nonisolated extension Key32: Value {
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

nonisolated extension CurrencyCode: Value {
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


