# SwiftData Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the manual SQLite.swift database layer with SwiftData, enabling `@Query` in views, eliminating `Updateable`, and dissolving the Database passthrough problem.

**Architecture:** 4 `@Model` classes replace 5 SQLite tables. A `DatabaseWriter` ModelActor handles background writes. Views use `@Query` for reactive reads. The database is delete-and-rebuild on version bump (no migration path needed). Domain types (`StoredBalance`, `Activity`, `Limits`, `MintMetadata`) stay unchanged — only the storage layer is swapped.

**Tech Stack:** SwiftData (iOS 17+), Swift Testing, Swift 6.1

---

## Design Context

Read `.claude/plans/2026-03-26-swiftdata-migration-research.md` (the research doc) for:
- Full analysis of current SQLite.swift layer
- Design decision rationale (PublicKey as String, @Relationship vs denormalized, etc.)
- SwiftData Pro skill review findings (iOS 17 constraints, predicate safety, relationship rules)
- Risk assessment and open questions

## File Map

### New Files
```
Flipcash/Core/Controllers/Database/Models/
├── MintRecord.swift           — @Model for mint metadata (replaces MintTable)
├── BalanceRecord.swift        — @Model for balances (replaces BalanceTable)
├── ActivityRecord.swift       — @Model for transaction history (replaces ActivityTable + CashLinkMetadataTable)
├── LimitsRecord.swift         — @Model for transaction limits (replaces LimitsTable)
├── MintRecord+Conversion.swift     — MintRecord ↔ MintMetadata / StoredMintMetadata
├── BalanceRecord+Conversion.swift  — BalanceRecord → StoredBalance
├── ActivityRecord+Conversion.swift — ActivityRecord ↔ Activity
└── LimitsRecord+Conversion.swift   — LimitsRecord ↔ Limits

Flipcash/Core/Controllers/Database/
├── DatabaseWriter.swift       — ModelActor for background writes
└── FlipcashModelContainer.swift — ModelContainer setup + version-based store deletion

FlipcashTests/SwiftData/
├── MintRecordTests.swift
├── BalanceRecordTests.swift
├── ActivityRecordTests.swift
├── LimitsRecordTests.swift
├── ConversionTests.swift
└── DatabaseWriterTests.swift
```

### Modified Files
```
Flipcash/Core/Session/Session.swift                    — Replace Updateable + database calls with ModelContext
Flipcash/Core/Session/SessionAuthenticator.swift       — Replace Database init with ModelContainer, update SessionContainer
Flipcash/Core/Controllers/HistoryController.swift      — Replace database write calls with DatabaseWriter
Flipcash/Core/Controllers/RatesController.swift        — Replace database calls with ModelContext/DatabaseWriter
Flipcash/Core/Screens/Main/Currency Info/CurrencyInfoViewModel.swift — Replace Updateable + database with @Query or ModelContext
Flipcash/Core/Screens/Main/Currency Info/CurrencyInfoScreen.swift    — Remove database dependency
Flipcash/Core/Screens/Main/TransactionHistoryScreen.swift            — Replace Updateable with @Query
Flipcash/Core/Screens/Main/Operations/ScanCashOperation.swift        — Replace database calls with DatabaseWriter
Flipcash/Supporting Files/Info.plist                    — Bump SQLiteVersion
```

### Deleted Files (Phase 4)
```
Flipcash/Core/Controllers/Database/Database.swift
Flipcash/Core/Controllers/Database/Schema.swift
Flipcash/Core/Controllers/Database/Updateable.swift
Flipcash/Core/Controllers/Database/Database+Balance.swift
Flipcash/Core/Controllers/Database/Database+Activities.swift
Flipcash/Core/Controllers/Database/Database+Limits.swift
```

---

## Task 1: Create @Model Definitions

**Files:**
- Create: `Flipcash/Core/Controllers/Database/Models/MintRecord.swift`
- Create: `Flipcash/Core/Controllers/Database/Models/BalanceRecord.swift`
- Create: `Flipcash/Core/Controllers/Database/Models/ActivityRecord.swift`
- Create: `Flipcash/Core/Controllers/Database/Models/LimitsRecord.swift`
- Test: `FlipcashTests/SwiftData/MintRecordTests.swift`

- [ ] **Step 1: Create MintRecord.swift**

```swift
//  MintRecord.swift

import Foundation
import SwiftData
import FlipcashCore

@Model class MintRecord {
    @Attribute(.unique) var mintAddress: String

    var name: String
    var symbol: String
    var decimals: Int
    var bio: String?
    var imageURL: URL?

    // VM metadata
    var vmAddress: String?
    var vmAuthority: String?
    var lockDuration: Int?

    // Launchpad metadata
    var currencyConfig: String?
    var liquidityPool: String?
    var seed: String?
    var authority: String?
    var mintVault: String?
    var coreMintVault: String?
    var coreMintFees: String?
    var supplyFromBonding: UInt64?
    var coreMintLocked: UInt64?
    var sellFeeBps: Int?

    // Codable arrays — NOT safe for use in #Predicate (runtime crash)
    var socialLinks: [SocialLink]
    var billColors: [String]

    var createdAt: Date?
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \BalanceRecord.mint)
    var balances: [BalanceRecord]?

    init(mintAddress: String, name: String, symbol: String, decimals: Int, bio: String? = nil, imageURL: URL? = nil, vmAddress: String? = nil, vmAuthority: String? = nil, lockDuration: Int? = nil, currencyConfig: String? = nil, liquidityPool: String? = nil, seed: String? = nil, authority: String? = nil, mintVault: String? = nil, coreMintVault: String? = nil, coreMintFees: String? = nil, supplyFromBonding: UInt64? = nil, coreMintLocked: UInt64? = nil, sellFeeBps: Int? = nil, socialLinks: [SocialLink] = [], billColors: [String] = [], createdAt: Date? = nil, updatedAt: Date) {
        self.mintAddress = mintAddress
        self.name = name
        self.symbol = symbol
        self.decimals = decimals
        self.bio = bio
        self.imageURL = imageURL
        self.vmAddress = vmAddress
        self.vmAuthority = vmAuthority
        self.lockDuration = lockDuration
        self.currencyConfig = currencyConfig
        self.liquidityPool = liquidityPool
        self.seed = seed
        self.authority = authority
        self.mintVault = mintVault
        self.coreMintVault = coreMintVault
        self.coreMintFees = coreMintFees
        self.supplyFromBonding = supplyFromBonding
        self.coreMintLocked = coreMintLocked
        self.sellFeeBps = sellFeeBps
        self.socialLinks = socialLinks
        self.billColors = billColors
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
```

- [ ] **Step 2: Create BalanceRecord.swift**

```swift
//  BalanceRecord.swift

import Foundation
import SwiftData

@Model class BalanceRecord {
    @Attribute(.unique) var mintAddress: String

    var quarks: UInt64
    var costBasis: Double?
    var updatedAt: Date

    var mint: MintRecord?

    init(mintAddress: String, quarks: UInt64, costBasis: Double? = nil, updatedAt: Date, mint: MintRecord? = nil) {
        self.mintAddress = mintAddress
        self.quarks = quarks
        self.costBasis = costBasis
        self.updatedAt = updatedAt
        self.mint = mint
    }
}
```

- [ ] **Step 3: Create ActivityRecord.swift**

```swift
//  ActivityRecord.swift

import Foundation
import SwiftData

@Model class ActivityRecord {
    @Attribute(.unique) var activityID: String

    var kind: Int
    var state: Int
    var title: String
    var quarks: UInt64
    var nativeAmount: Double
    var currency: String
    var mint: String
    var date: Date

    var cashLinkVault: String?
    var cashLinkCanCancel: Bool?

    init(activityID: String, kind: Int, state: Int, title: String, quarks: UInt64, nativeAmount: Double, currency: String, mint: String, date: Date, cashLinkVault: String? = nil, cashLinkCanCancel: Bool? = nil) {
        self.activityID = activityID
        self.kind = kind
        self.state = state
        self.title = title
        self.quarks = quarks
        self.nativeAmount = nativeAmount
        self.currency = currency
        self.mint = mint
        self.date = date
        self.cashLinkVault = cashLinkVault
        self.cashLinkCanCancel = cashLinkCanCancel
    }
}
```

- [ ] **Step 4: Create LimitsRecord.swift**

```swift
//  LimitsRecord.swift

import Foundation
import SwiftData

@Model class LimitsRecord {
    var data: Data
    var updatedAt: Date

    init(data: Data, updatedAt: Date) {
        self.data = data
        self.updatedAt = updatedAt
    }
}
```

- [ ] **Step 5: Write roundtrip tests for MintRecord**

```swift
//  MintRecordTests.swift

import Testing
import SwiftData
@testable import Flipcash

@Suite("MintRecord Tests")
struct MintRecordTests {
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: MintRecord.self, BalanceRecord.self, ActivityRecord.self, LimitsRecord.self,
            configurations: config
        )
    }

    @Test("Insert and fetch mint record by address")
    func insertAndFetch() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let record = MintRecord(
            mintAddress: "So11111111111111111111111111111111",
            name: "Test Coin",
            symbol: "TEST",
            decimals: 6,
            updatedAt: .now
        )
        context.insert(record)
        try context.save()

        let address = "So11111111111111111111111111111111"
        let descriptor = FetchDescriptor<MintRecord>(
            predicate: #Predicate { $0.mintAddress == address }
        )
        let results = try context.fetch(descriptor)

        #expect(results.count == 1)
        #expect(results[0].name == "Test Coin")
        #expect(results[0].symbol == "TEST")
        #expect(results[0].decimals == 6)
    }

    @Test("Upsert overwrites existing record with same mintAddress")
    func upsert() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let record1 = MintRecord(mintAddress: "mint1", name: "V1", symbol: "V1", decimals: 6, updatedAt: .now)
        context.insert(record1)
        try context.save()

        // SwiftData upsert: fetch existing, update in place
        let address = "mint1"
        let descriptor = FetchDescriptor<MintRecord>(predicate: #Predicate { $0.mintAddress == address })
        if let existing = try context.fetch(descriptor).first {
            existing.name = "V2"
            existing.symbol = "V2"
        }
        try context.save()

        let all = try context.fetch(FetchDescriptor<MintRecord>())
        #expect(all.count == 1)
        #expect(all[0].name == "V2")
    }

    @Test("Cascade delete removes associated balances")
    func cascadeDelete() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let mintRecord = MintRecord(mintAddress: "mint1", name: "Coin", symbol: "C", decimals: 6, updatedAt: .now)
        let balanceRecord = BalanceRecord(mintAddress: "mint1", quarks: 1000, updatedAt: .now, mint: mintRecord)
        context.insert(mintRecord)
        context.insert(balanceRecord)
        try context.save()

        context.delete(mintRecord)
        try context.save()

        let balances = try context.fetch(FetchDescriptor<BalanceRecord>())
        #expect(balances.isEmpty)
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `xcodebuild test -scheme Flipcash -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FlipcashTests/MintRecordTests`
Expected: 3 tests PASS

- [ ] **Step 7: Commit**

```
git add Flipcash/Core/Controllers/Database/Models/MintRecord.swift \
       Flipcash/Core/Controllers/Database/Models/BalanceRecord.swift \
       Flipcash/Core/Controllers/Database/Models/ActivityRecord.swift \
       Flipcash/Core/Controllers/Database/Models/LimitsRecord.swift \
       FlipcashTests/SwiftData/MintRecordTests.swift
git commit -m "feat: add SwiftData @Model definitions for database migration"
```

---

## Task 2: Conversion Extensions

**Files:**
- Create: `Flipcash/Core/Controllers/Database/Models/MintRecord+Conversion.swift`
- Create: `Flipcash/Core/Controllers/Database/Models/ActivityRecord+Conversion.swift`
- Create: `Flipcash/Core/Controllers/Database/Models/BalanceRecord+Conversion.swift`
- Create: `Flipcash/Core/Controllers/Database/Models/LimitsRecord+Conversion.swift`
- Test: `FlipcashTests/SwiftData/ConversionTests.swift`

These extensions bridge between SwiftData `@Model` classes and existing domain types. The domain types (`MintMetadata`, `StoredMintMetadata`, `Activity`, `Limits`, `StoredBalance`) remain unchanged.

- [ ] **Step 1: Create MintRecord+Conversion.swift**

```swift
//  MintRecord+Conversion.swift

import Foundation
import FlipcashCore

extension MintRecord {
    /// Creates or updates a MintRecord from a MintMetadata (server response).
    /// Call on an existing record to update, or create new and insert into context.
    convenience init(from metadata: MintMetadata, date: Date) {
        let socialLinksEncoded: [SocialLink] = metadata.socialLinks
        let billColorsEncoded: [String] = metadata.billColors

        self.init(
            mintAddress: metadata.address.base58,
            name: metadata.name,
            symbol: metadata.symbol,
            decimals: metadata.decimals,
            bio: metadata.description.isEmpty ? nil : metadata.description,
            imageURL: metadata.imageURL,
            vmAddress: metadata.vmMetadata?.vm.base58,
            vmAuthority: metadata.vmMetadata?.authority.base58,
            lockDuration: metadata.vmMetadata?.lockDurationInDays,
            currencyConfig: metadata.launchpadMetadata?.currencyConfig.base58,
            liquidityPool: metadata.launchpadMetadata?.liquidityPool.base58,
            seed: metadata.launchpadMetadata?.seed.base58,
            authority: metadata.launchpadMetadata?.authority.base58,
            mintVault: metadata.launchpadMetadata?.mintVault.base58,
            coreMintVault: metadata.launchpadMetadata?.coreMintVault.base58,
            coreMintFees: metadata.launchpadMetadata?.coreMintFees?.base58,
            supplyFromBonding: metadata.launchpadMetadata?.supplyFromBonding,
            sellFeeBps: metadata.launchpadMetadata?.sellFeeBps,
            socialLinks: socialLinksEncoded,
            billColors: billColorsEncoded,
            createdAt: metadata.createdAt,
            updatedAt: date
        )
    }

    /// Updates this record in-place from a MintMetadata.
    func update(from metadata: MintMetadata, date: Date) {
        name = metadata.name
        symbol = metadata.symbol
        decimals = metadata.decimals
        bio = metadata.description.isEmpty ? nil : metadata.description
        imageURL = metadata.imageURL
        vmAddress = metadata.vmMetadata?.vm.base58
        vmAuthority = metadata.vmMetadata?.authority.base58
        lockDuration = metadata.vmMetadata?.lockDurationInDays
        currencyConfig = metadata.launchpadMetadata?.currencyConfig.base58
        liquidityPool = metadata.launchpadMetadata?.liquidityPool.base58
        seed = metadata.launchpadMetadata?.seed.base58
        authority = metadata.launchpadMetadata?.authority.base58
        mintVault = metadata.launchpadMetadata?.mintVault.base58
        coreMintVault = metadata.launchpadMetadata?.coreMintVault.base58
        coreMintFees = metadata.launchpadMetadata?.coreMintFees?.base58
        supplyFromBonding = metadata.launchpadMetadata?.supplyFromBonding
        sellFeeBps = metadata.launchpadMetadata?.sellFeeBps
        socialLinks = metadata.socialLinks
        billColors = metadata.billColors
        createdAt = metadata.createdAt
        updatedAt = date
    }

    /// Converts to the existing StoredMintMetadata value type.
    func toStoredMintMetadata() -> StoredMintMetadata {
        let encodedSocialLinks: String? = {
            guard !socialLinks.isEmpty,
                  let data = try? JSONEncoder().encode(socialLinks) else { return nil }
            return String(data: data, encoding: .utf8)
        }()

        let encodedBillColors: String? = {
            guard !billColors.isEmpty,
                  let data = try? JSONEncoder().encode(billColors) else { return nil }
            return String(data: data, encoding: .utf8)
        }()

        return StoredMintMetadata(
            mint: try! PublicKey(base58: mintAddress),
            name: name,
            symbol: symbol,
            decimals: decimals,
            bio: bio,
            imageURL: imageURL,
            vmAddress: vmAddress.flatMap { try? PublicKey(base58: $0) },
            vmAuthority: vmAuthority.flatMap { try? PublicKey(base58: $0) },
            lockDuration: lockDuration,
            currencyConfig: currencyConfig.flatMap { try? PublicKey(base58: $0) },
            liquidityPool: liquidityPool.flatMap { try? PublicKey(base58: $0) },
            seed: seed.flatMap { try? PublicKey(base58: $0) },
            authority: authority.flatMap { try? PublicKey(base58: $0) },
            mintVault: mintVault.flatMap { try? PublicKey(base58: $0) },
            coreMintVault: coreMintVault.flatMap { try? PublicKey(base58: $0) },
            coreMintFees: coreMintFees.flatMap { try? PublicKey(base58: $0) },
            supplyFromBonding: supplyFromBonding,
            sellFeeBps: sellFeeBps,
            socialLinks: encodedSocialLinks,
            billColors: encodedBillColors,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
```

- [ ] **Step 2: Create ActivityRecord+Conversion.swift**

```swift
//  ActivityRecord+Conversion.swift

import Foundation
import FlipcashCore

extension ActivityRecord {
    convenience init(from activity: Activity) {
        let cashLinkMeta: (vault: String, canCancel: Bool)? = {
            if case .cashLink(let meta) = activity.metadata {
                return (meta.vault.base58, meta.canCancel)
            }
            return nil
        }()

        self.init(
            activityID: activity.id.base58,
            kind: activity.kind.rawValue,
            state: activity.state.rawValue,
            title: activity.title,
            quarks: activity.exchangedFiat.underlying.quarks,
            nativeAmount: activity.exchangedFiat.converted.doubleValue,
            currency: activity.exchangedFiat.converted.currencyCode.rawValue,
            mint: activity.exchangedFiat.mint.base58,
            date: activity.date,
            cashLinkVault: cashLinkMeta?.vault,
            cashLinkCanCancel: cashLinkMeta?.canCancel
        )
    }

    /// Updates this record in-place from an Activity (for upsert).
    func update(from activity: Activity) {
        kind = activity.kind.rawValue
        state = activity.state.rawValue
        title = activity.title
        quarks = activity.exchangedFiat.underlying.quarks
        nativeAmount = activity.exchangedFiat.converted.doubleValue
        currency = activity.exchangedFiat.converted.currencyCode.rawValue
        mint = activity.exchangedFiat.mint.base58
        date = activity.date

        if case .cashLink(let meta) = activity.metadata {
            cashLinkVault = meta.vault.base58
            cashLinkCanCancel = meta.canCancel
        }
    }

    /// Converts to the existing Activity domain type.
    func toActivity() throws -> Activity {
        let mintKey = try PublicKey(base58: mint)
        guard let kind = Activity.Kind(rawValue: kind) else {
            throw ActivityConversionError.invalidKind(kind)
        }
        let currencyCode = try CurrencyCode(currencyCode: currency)

        let metadata: Activity.Metadata? = {
            guard kind == .cashLink,
                  let vault = cashLinkVault.flatMap({ try? PublicKey(base58: $0) }),
                  let canCancel = cashLinkCanCancel else {
                return nil
            }
            return .cashLink(Activity.CashLinkMetadata(vault: vault, canCancel: canCancel))
        }()

        return Activity(
            id: try PublicKey(base58: activityID),
            state: Activity.State(rawValue: state) ?? .unknown,
            kind: kind,
            title: title,
            exchangedFiat: ExchangedFiat(
                underlying: Quarks(quarks: quarks, currencyCode: .usd, decimals: mintKey.mintDecimals),
                converted: try Quarks(fiatDecimal: Decimal(nativeAmount), currencyCode: currencyCode, decimals: mintKey.mintDecimals),
                mint: mintKey
            ),
            date: date,
            metadata: metadata
        )
    }
}
```

- [ ] **Step 3: Create BalanceRecord+Conversion.swift**

```swift
//  BalanceRecord+Conversion.swift

import Foundation
import FlipcashCore

extension BalanceRecord {
    /// Converts to StoredBalance using the eagerly-loaded mint relationship.
    /// Caller must ensure `mint` is prefetched (use `relationshipKeyPathsForPrefetching`).
    func toStoredBalance() throws -> StoredBalance {
        guard let mint else {
            throw BalanceConversionError.missingMintRelationship
        }

        return try StoredBalance(
            quarks: quarks,
            symbol: mint.symbol,
            name: mint.name,
            supplyFromBonding: mint.supplyFromBonding,
            sellFeeBps: mint.sellFeeBps,
            mint: PublicKey(base58: mintAddress),
            vmAuthority: mint.vmAuthority.flatMap { try? PublicKey(base58: $0) },
            updatedAt: updatedAt,
            imageURL: mint.imageURL,
            costBasis: costBasis ?? 0
        )
    }
}

enum BalanceConversionError: Error {
    case missingMintRelationship
}

enum ActivityConversionError: Error {
    case invalidKind(Int)
}
```

- [ ] **Step 4: Create LimitsRecord+Conversion.swift**

```swift
//  LimitsRecord+Conversion.swift

import Foundation
import FlipcashCore

extension LimitsRecord {
    convenience init(from limits: Limits) throws {
        let data = try JSONEncoder().encode(limits)
        self.init(data: data, updatedAt: .now)
    }

    func toLimits() throws -> Limits {
        try JSONDecoder().decode(Limits.self, from: data)
    }
}
```

- [ ] **Step 5: Write conversion roundtrip tests**

```swift
//  ConversionTests.swift

import Testing
import SwiftData
@testable import Flipcash
@testable import FlipcashCore

@Suite("SwiftData Conversion Tests")
struct ConversionTests {
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: MintRecord.self, BalanceRecord.self, ActivityRecord.self, LimitsRecord.self,
            configurations: config
        )
    }

    @Test("MintRecord roundtrip: MintMetadata → MintRecord → StoredMintMetadata preserves fields")
    func mintRoundtrip() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Use a known mint address for testing
        let address = PublicKey.usdf
        let metadata = MintMetadata(
            address: address,
            decimals: 6,
            name: "Test Token",
            symbol: "TT",
            description: "A test token",
            imageURL: nil,
            vmMetadata: nil,
            launchpadMetadata: nil,
            socialLinks: [],
            billColors: []
        )

        let record = MintRecord(from: metadata, date: .now)
        context.insert(record)
        try context.save()

        let stored = record.toStoredMintMetadata()
        #expect(stored.mint == address)
        #expect(stored.name == "Test Token")
        #expect(stored.symbol == "TT")
        #expect(stored.bio == "A test token")
        #expect(stored.decimals == 6)
    }

    @Test("BalanceRecord with mint relationship produces valid StoredBalance")
    func balanceWithRelationship() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let mintRecord = MintRecord(
            mintAddress: PublicKey.usdf.base58,
            name: "USDF",
            symbol: "USDF",
            decimals: 6,
            updatedAt: .now
        )
        let balanceRecord = BalanceRecord(
            mintAddress: PublicKey.usdf.base58,
            quarks: 5_000_000,
            costBasis: 5.0,
            updatedAt: .now,
            mint: mintRecord
        )

        context.insert(mintRecord)
        context.insert(balanceRecord)
        try context.save()

        let stored = try balanceRecord.toStoredBalance()
        #expect(stored.quarks == 5_000_000)
        #expect(stored.symbol == "USDF")
        #expect(stored.mint == .usdf)
        #expect(stored.costBasis == 5.0)
    }

    @Test("LimitsRecord roundtrip preserves Limits data")
    func limitsRoundtrip() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let limits = Limits.mock
        let record = try LimitsRecord(from: limits)
        context.insert(record)
        try context.save()

        let decoded = try record.toLimits()
        #expect(decoded == limits)
    }
}
```

- [ ] **Step 6: Run tests**

Run: `xcodebuild test -scheme Flipcash -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FlipcashTests/ConversionTests`
Expected: PASS

- [ ] **Step 7: Commit**

```
git add Flipcash/Core/Controllers/Database/Models/*+Conversion.swift FlipcashTests/SwiftData/ConversionTests.swift
git commit -m "feat: add SwiftData conversion extensions for domain type bridging"
```

---

## Task 3: ModelContainer Setup + DatabaseWriter

**Files:**
- Create: `Flipcash/Core/Controllers/Database/FlipcashModelContainer.swift`
- Create: `Flipcash/Core/Controllers/Database/DatabaseWriter.swift`
- Test: `FlipcashTests/SwiftData/DatabaseWriterTests.swift`

- [ ] **Step 1: Create FlipcashModelContainer.swift**

This manages the SwiftData container and handles version-based store deletion (matching the existing `SQLiteVersion` pattern in `SessionAuthenticator`).

```swift
//  FlipcashModelContainer.swift

import Foundation
import SwiftData
import FlipcashCore

enum FlipcashModelContainer {
    static let schema = Schema([
        MintRecord.self,
        BalanceRecord.self,
        ActivityRecord.self,
        LimitsRecord.self,
    ])

    /// Creates the shared ModelContainer. Call once at app startup.
    /// Handles version-based store deletion matching the existing SQLiteVersion pattern.
    static func create(owner: PublicKey) throws -> ModelContainer {
        let storeURL = URL.applicationSupportDirectory
            .appendingPathComponent("flipcash-\(owner.base58)-swiftdata.store")

        let config = ModelConfiguration(
            schema: schema,
            url: storeURL
        )

        return try ModelContainer(for: schema, configurations: config)
    }

    /// Deletes the SwiftData store files for a given owner.
    /// Call when SQLiteVersion bumps or on logout.
    static func deleteStore(owner: PublicKey) throws {
        let storeURL = URL.applicationSupportDirectory
            .appendingPathComponent("flipcash-\(owner.base58)-swiftdata.store")

        let urlsToRemove = [
            storeURL,
            storeURL.appendingPathExtension("shm"),
            storeURL.appendingPathExtension("wal"),
        ]

        for url in urlsToRemove {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    /// In-memory container for tests and previews.
    static func makeInMemory() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: config)
    }
}
```

- [ ] **Step 2: Create DatabaseWriter.swift**

Replaces `Database.transaction {}` for background writes. Uses `ModelActor` so writes happen off the main thread.

```swift
//  DatabaseWriter.swift

import Foundation
import SwiftData
import FlipcashCore

@ModelActor
actor DatabaseWriter {

    // MARK: - Mints

    func upsertMints(_ mints: [MintMetadata], date: Date) throws {
        for metadata in mints {
            let address = metadata.address.base58
            let descriptor = FetchDescriptor<MintRecord>(
                predicate: #Predicate { $0.mintAddress == address }
            )

            if let existing = try modelContext.fetch(descriptor).first {
                existing.update(from: metadata, date: date)
            } else {
                let record = MintRecord(from: metadata, date: date)
                modelContext.insert(record)
            }
        }
        try modelContext.save()
    }

    // MARK: - Balances

    func upsertBalances(_ accounts: [(quarks: UInt64, mint: PublicKey, costBasis: Double)], date: Date) throws {
        for account in accounts {
            let address = account.mint.base58
            let descriptor = FetchDescriptor<BalanceRecord>(
                predicate: #Predicate { $0.mintAddress == address }
            )

            if let existing = try modelContext.fetch(descriptor).first {
                existing.quarks = account.quarks
                existing.costBasis = account.costBasis
                existing.updatedAt = date
            } else {
                let mintDescriptor = FetchDescriptor<MintRecord>(
                    predicate: #Predicate { $0.mintAddress == address }
                )
                let mintRecord = try modelContext.fetch(mintDescriptor).first

                let record = BalanceRecord(
                    mintAddress: address,
                    quarks: account.quarks,
                    costBasis: account.costBasis,
                    updatedAt: date,
                    mint: mintRecord
                )
                modelContext.insert(record)
            }
        }
        try modelContext.save()  // Single save for the entire batch
    }

    // MARK: - Activities

    func upsertActivities(_ activities: [Activity]) throws {
        for activity in activities {
            let id = activity.id.base58
            let descriptor = FetchDescriptor<ActivityRecord>(
                predicate: #Predicate { $0.activityID == id }
            )

            if let existing = try modelContext.fetch(descriptor).first {
                existing.update(from: activity)
            } else {
                let record = ActivityRecord(from: activity)
                modelContext.insert(record)
            }
        }
        try modelContext.save()
    }

    // MARK: - Limits

    func upsertLimits(_ limits: Limits) throws {
        let descriptor = FetchDescriptor<LimitsRecord>()
        if let existing = try modelContext.fetch(descriptor).first {
            existing.data = try JSONEncoder().encode(limits)
            existing.updatedAt = .now
        } else {
            let record = try LimitsRecord(from: limits)
            modelContext.insert(record)
        }
        try modelContext.save()
    }

    // MARK: - Live Supply

    func updateLiveSupply(updates: [ReserveStateUpdate], date: Date) throws {
        for update in updates {
            let address = update.mint.base58
            let descriptor = FetchDescriptor<MintRecord>(
                predicate: #Predicate { $0.mintAddress == address }
            )
            if let record = try modelContext.fetch(descriptor).first {
                record.supplyFromBonding = update.supplyFromBonding
                record.updatedAt = date
            }
        }
        try modelContext.save()
    }
}
```

- [ ] **Step 3: Write DatabaseWriter tests**

```swift
//  DatabaseWriterTests.swift

import Testing
import SwiftData
@testable import Flipcash
@testable import FlipcashCore

@Suite("DatabaseWriter Tests")
struct DatabaseWriterTests {

    @Test("Upsert mints inserts new and updates existing")
    func upsertMints() async throws {
        let container = try FlipcashModelContainer.makeInMemory()
        let writer = DatabaseWriter(modelContainer: container)

        let mint = MintMetadata(
            address: .usdf,
            decimals: 6,
            name: "USDF",
            symbol: "USDF",
            description: "",
            imageURL: nil,
            vmMetadata: nil,
            launchpadMetadata: nil,
            socialLinks: [],
            billColors: []
        )

        // Insert
        try await writer.upsertMints([mint], date: .now)

        // Verify via main context
        let context = ModelContext(container)
        let all = try context.fetch(FetchDescriptor<MintRecord>())
        #expect(all.count == 1)
        #expect(all[0].name == "USDF")

        // Update
        let updated = MintMetadata(
            address: .usdf,
            decimals: 6,
            name: "USDF Updated",
            symbol: "USDF",
            description: "",
            imageURL: nil,
            vmMetadata: nil,
            launchpadMetadata: nil,
            socialLinks: [],
            billColors: []
        )
        try await writer.upsertMints([updated], date: .now)

        let refreshed = try context.fetch(FetchDescriptor<MintRecord>())
        #expect(refreshed.count == 1)
        #expect(refreshed[0].name == "USDF Updated")
    }

    @Test("Upsert balance creates relationship to existing mint")
    func upsertBalanceWithMint() async throws {
        let container = try FlipcashModelContainer.makeInMemory()
        let writer = DatabaseWriter(modelContainer: container)

        // Insert mint first
        let mint = MintMetadata(
            address: .usdf, decimals: 6, name: "USDF", symbol: "USDF",
            description: "", imageURL: nil, vmMetadata: nil,
            launchpadMetadata: nil, socialLinks: [], billColors: []
        )
        try await writer.upsertMints([mint], date: .now)

        // Insert balance
        try await writer.upsertBalance(quarks: 1_000_000, mint: .usdf, costBasis: 1.0, date: .now)

        // Verify relationship
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<BalanceRecord>()
        descriptor.relationshipKeyPathsForPrefetching = [\.mint]
        let balances = try context.fetch(descriptor)

        #expect(balances.count == 1)
        #expect(balances[0].mint?.name == "USDF")
        let stored = try balances[0].toStoredBalance()
        #expect(stored.quarks == 1_000_000)
    }

    @Test("Upsert limits replaces singleton")
    func upsertLimits() async throws {
        let container = try FlipcashModelContainer.makeInMemory()
        let writer = DatabaseWriter(modelContainer: container)

        let limits = Limits.mock
        try await writer.upsertLimits(limits)

        let context = ModelContext(container)
        let all = try context.fetch(FetchDescriptor<LimitsRecord>())
        #expect(all.count == 1)

        let decoded = try all[0].toLimits()
        #expect(decoded == limits)

        // Upsert again — should still be 1 record
        try await writer.upsertLimits(limits)
        let refreshed = try context.fetch(FetchDescriptor<LimitsRecord>())
        #expect(refreshed.count == 1)
    }
}
```

- [ ] **Step 4: Run tests**

Run: `xcodebuild test -scheme Flipcash -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FlipcashTests/DatabaseWriterTests`
Expected: PASS

- [ ] **Step 5: Commit**

```
git add Flipcash/Core/Controllers/Database/FlipcashModelContainer.swift \
       Flipcash/Core/Controllers/Database/DatabaseWriter.swift \
       FlipcashTests/SwiftData/DatabaseWriterTests.swift
git commit -m "feat: add ModelContainer setup and DatabaseWriter actor"
```

---

## Task 4: Replace Write Path in Session

**Files:**
- Modify: `Flipcash/Core/Session/Session.swift` — Replace `database.insert(mints:)`, `database.insertBalance(...)`, `database.insertLimits(...)`, `database.transaction {}` calls with `DatabaseWriter`
- Modify: `Flipcash/Core/Session/SessionAuthenticator.swift` — Replace Database init with ModelContainer, add DatabaseWriter to SessionContainer

This is the largest caller. Key changes:
- `SessionContainer` gains `modelContainer: ModelContainer` and `databaseWriter: DatabaseWriter`
- `Session` gains `databaseWriter` property, drops `database` dependency for writes
- `fetchBalance()` uses `databaseWriter.upsertMints(...)` and `databaseWriter.upsertBalances(...)`
- `fetchLimits()` uses `databaseWriter.upsertLimits(...)`
- `Updateable { database.getBalances() }` → `@Query` in views (deferred to Task 6)

**Important:** This task replaces WRITE calls only. READ calls (`Updateable`, `getBalances()`, etc.) are replaced in Task 6. During the interim, both old and new write paths exist. The old Database stays until Task 8 (cleanup).

- [ ] **Step 1: Add databaseWriter to SessionContainer**

In `Flipcash/Core/Session/SessionAuthenticator.swift`, add to `SessionContainer`:

```swift
struct SessionContainer {
    let session: Session
    let database: Database  // Keep during migration — removed in Task 8
    let databaseWriter: DatabaseWriter  // NEW
    let modelContainer: ModelContainer  // NEW
    let walletConnection: WalletConnection
    let ratesController: RatesController
    let historyController: HistoryController
    let pushController: PushController
    let onrampViewModel: OnrampViewModel

    fileprivate func injectingEnvironment<SomeView>(into view: SomeView) -> some View where SomeView: View {
        view
            .environment(session)
            .environment(ratesController)
            .environment(historyController)
            .environment(pushController)
            .environment(walletConnection)
            .modelContainer(modelContainer)  // NEW
    }
}
```

Update `SessionAuthenticator.createSessionContainer(...)` to create the ModelContainer and DatabaseWriter. Update `SessionContainer.mock`.

- [ ] **Step 2: Add databaseWriter to Session**

Add `let databaseWriter: DatabaseWriter` property. Update Session init to accept it.

- [ ] **Step 3: Replace fetchBalance() write calls**

In `Session.fetchBalance()`, replace:

```swift
// BEFORE
try database.insert(mints: mintMetadata.map { $0.value }, date: now)
database.transaction { database in
    accounts.forEach { account in
        try? database.insertBalance(quarks: account.quarks, mint: account.mint, costBasis: account.usdCostBasis, date: now)
    }
}

// AFTER
try await databaseWriter.upsertMints(mintMetadata.map { $0.value }, date: now)
try await databaseWriter.upsertBalances(
    accounts.map { (quarks: $0.quarks, mint: $0.mint, costBasis: $0.usdCostBasis) },
    date: now
)
```

- [ ] **Step 4: Replace fetchLimits() write call**

```swift
// BEFORE
database.transaction { database in
    try? database.insertLimits(fetchedLimits)
}

// AFTER
try? await databaseWriter.upsertLimits(fetchedLimits)
```

- [ ] **Step 5: Replace fetchMintMetadata() write call**

```swift
// BEFORE
try database.insert(mints: [mintMetadata], date: .now)

// AFTER
try await databaseWriter.upsertMints([mintMetadata], date: .now)
```

- [ ] **Step 6: Replace other Session mint insert calls**

Search Session.swift for remaining `database.insert(mints:` calls (line ~1195) and replace with `databaseWriter.upsertMints(...)`.

- [ ] **Step 7: Build to verify**

Run: `xcodebuild build -scheme Flipcash -destination 'generic/platform=iOS'`
Expected: BUILD SUCCEEDED (old reads still use Database — that's fine for now)

- [ ] **Step 8: Commit**

```
git commit -m "refactor: replace Session database writes with DatabaseWriter"
```

---

## Task 5: Replace Write Path in HistoryController and RatesController

**Files:**
- Modify: `Flipcash/Core/Controllers/HistoryController.swift`
- Modify: `Flipcash/Core/Controllers/RatesController.swift`
- Modify: `Flipcash/Core/Screens/Main/Operations/ScanCashOperation.swift`

- [ ] **Step 1: Replace HistoryController write calls**

Add `let databaseWriter: DatabaseWriter` to HistoryController. Replace:

```swift
// BEFORE (syncPendingActivities)
try database.transaction { try $0.insertActivities(activities: activities) }

// AFTER
try await databaseWriter.upsertActivities(activities)
```

```swift
// BEFORE (syncHistory)
try database.transaction { try $0.insertActivities(activities: container) }

// AFTER
try await databaseWriter.upsertActivities(container)
```

- [ ] **Step 2: Replace RatesController write call**

Add `let databaseWriter: DatabaseWriter` to RatesController. Replace the Combine sink for `updateLiveSupply`:

```swift
// BEFORE
try self.database.updateLiveSupply(updates: updates, date: .now)

// AFTER
Task {
    do {
        try await self.databaseWriter.updateLiveSupply(updates: updates, date: .now)
    } catch {
        trace(.warning, components: "Failed to update live supply: \(error)")
    }
}
```

- [ ] **Step 3: Replace ScanCashOperation write calls**

Add `let databaseWriter: DatabaseWriter`. Replace:

```swift
// BEFORE
try? database.insert(mints: [mintMetadata], date: .now)

// AFTER
try? await databaseWriter.upsertMints([mintMetadata], date: .now)
```

- [ ] **Step 4: Build to verify**

Run: `xcodebuild build -scheme Flipcash -destination 'generic/platform=iOS'`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```
git commit -m "refactor: replace HistoryController, RatesController, ScanCashOperation writes with DatabaseWriter"
```

---

## Task 6: Replace Read Path — Session Balances and Limits

**Files:**
- Modify: `Flipcash/Core/Session/Session.swift` — Replace `Updateable<[StoredBalance]>` and `Updateable<Limits?>` with ModelContext-based reads

This is the critical change. Session currently uses `Updateable` to auto-refresh balances and limits on database changes. With SwiftData, the `ModelContext` observation handles this automatically.

**Strategy:** Session reads balances/limits via `ModelContext.fetch()`. Views that need reactive updates use `@Query` directly (Task 7). Session keeps fetched values in `@Observable` properties that update when the model context changes.

- [ ] **Step 1: Replace Updateable balances with ModelContext fetch**

In Session, replace:

```swift
// BEFORE
private var updateableBalances: Updateable<[StoredBalance]>
var balances: [StoredBalance] { updateableBalances.value }

// AFTER
private(set) var balances: [StoredBalance] = []
private let modelContext: ModelContext

func refreshBalances() {
    var descriptor = FetchDescriptor<BalanceRecord>(
        sortBy: [SortDescriptor(\.quarks, order: .reverse)]
    )
    descriptor.relationshipKeyPathsForPrefetching = [\.mint]

    do {
        let records = try modelContext.fetch(descriptor)
        balances = records.compactMap { try? $0.toStoredBalance() }
    } catch {
        balances = []
    }
}
```

Call `refreshBalances()` after every write operation. Because `DatabaseWriter` uses its own `ModelContext` (on a background actor), the main-thread `modelContext` may not yet see the writes. Force a re-read from the persistent store before fetching:

```swift
try await databaseWriter.upsertBalances(...)
try modelContext.save()  // Merges any pending changes and picks up background writes
refreshBalances()
```

- [ ] **Step 2: Replace Updateable limits**

```swift
// BEFORE
private var updateableLimits: Updateable<Limits?>
var limits: Limits? { updateableLimits.value }

// AFTER
private(set) var limits: Limits?

func refreshLimits() {
    do {
        let records = try modelContext.fetch(FetchDescriptor<LimitsRecord>())
        limits = try records.first?.toLimits()
    } catch {
        limits = nil
    }
}
```

- [ ] **Step 3: Add refresh calls after writes**

In `fetchBalance()`, after the DatabaseWriter calls:
```swift
try await databaseWriter.upsertMints(...)
try await databaseWriter.upsertBalances(...)
refreshBalances()
```

In `fetchLimits()`:
```swift
try? await databaseWriter.upsertLimits(fetchedLimits)
refreshLimits()
```

- [ ] **Step 4: Build to verify**

Run: `xcodebuild build -scheme Flipcash -destination 'generic/platform=iOS'`

- [ ] **Step 5: Commit**

```
git commit -m "refactor: replace Updateable balances/limits with ModelContext fetch in Session"
```

---

## Task 7: Replace Read Path — Views with @Query

**Files:**
- Modify: `Flipcash/Core/Screens/Main/TransactionHistoryScreen.swift`
- Modify: `Flipcash/Core/Screens/Main/Currency Info/CurrencyInfoViewModel.swift`
- Modify: `Flipcash/Core/Controllers/HistoryController.swift` — Replace `getLatestActivityID()` and `getPendingActivityIDs()`
- Modify: `Flipcash/Core/Controllers/RatesController.swift` — Replace `getMintMetadata()` reads

- [ ] **Step 1: Replace TransactionHistoryScreen with @Query**

```swift
// BEFORE
@State private var updateableActivities: Updateable<[Activity]>
private var activities: [Activity] { updateableActivities.value }

init(mintMetadata: StoredMintMetadata, container: Container, sessionContainer: SessionContainer) { ... }

// AFTER
@Query private var activityRecords: [ActivityRecord]
@Environment(Session.self) private var session
@State private var activities: [Activity] = []

init(mintMetadata: StoredMintMetadata) {
    self.mintMetadata = mintMetadata
    let mintAddress = mintMetadata.mint.base58
    _activityRecords = Query(
        filter: #Predicate<ActivityRecord> { $0.mint == mintAddress },
        sort: \.date,
        order: .reverse
    )
}
```

Cache the conversion result via `onChange` to avoid re-converting on every body evaluation:

```swift
.onChange(of: activityRecords, initial: true) { _, records in
    activities = records.compactMap { try? $0.toActivity() }
}
```

This eliminates `container`, `sessionContainer`, `database` from the init entirely.

- [ ] **Step 2: Replace CurrencyInfoViewModel database fast-path**

The VM currently reads `database.getMintMetadata(mint:)` at init. Replace with `ModelContext.fetch()`:

```swift
// BEFORE
if let cachedMetadata = try? database.getMintMetadata(mint: mint) {
    setupUpdateable(with: cachedMetadata)
    loadingState = .loaded(cachedMetadata)
}

// AFTER
init(mint: PublicKey, session: Session, modelContext: ModelContext, ratesController: RatesController) {
    self.mint = mint
    self.session = session
    self.modelContext = modelContext
    self.ratesController = ratesController

    let address = mint.base58
    let descriptor = FetchDescriptor<MintRecord>(
        predicate: #Predicate { $0.mintAddress == address }
    )
    if let record = try? modelContext.fetch(descriptor).first {
        let metadata = record.toStoredMintMetadata()
        loadingState = .loaded(metadata)
    }
}
```

Remove the `Updateable` property and `setupUpdateable()` method. Note: `ModelContext.fetch()` is a one-shot read (not reactive like `@Query`). This means live supply updates won't auto-refresh the loaded metadata. This is acceptable because: (1) the VM already does a network refresh via `loadMintMetadata()` in `.task`, and (2) supply-driven values (market cap, balance) are computed from `session.balance()` and `ratesController`, which are `@Observable` and update independently.

- [ ] **Step 3: Replace HistoryController read calls**

```swift
// BEFORE
let pendingIDs = try database.getPendingActivityIDs()
let latestID = try database.getLatestActivityID()

// AFTER (using ModelContext)
func getPendingActivityIDs() throws -> [PublicKey] {
    let pending = 1
    let descriptor = FetchDescriptor<ActivityRecord>(
        predicate: #Predicate { $0.state == pending },
        sortBy: [SortDescriptor(\.date, order: .reverse)]
    )
    return try modelContext.fetch(descriptor).compactMap {
        try? PublicKey(base58: $0.activityID)
    }
}

func getLatestActivityID() throws -> PublicKey? {
    let completed = 2
    var descriptor = FetchDescriptor<ActivityRecord>(
        predicate: #Predicate { $0.state == completed },
        sortBy: [SortDescriptor(\.date, order: .reverse)]
    )
    descriptor.fetchLimit = 1
    return try modelContext.fetch(descriptor).first.flatMap {
        try? PublicKey(base58: $0.activityID)
    }
}
```

- [ ] **Step 4: Replace RatesController and Session read calls**

Replace `database.getMintMetadata(mint:)` calls with `ModelContext.fetch()`:

```swift
func getMintMetadata(mint: PublicKey) -> StoredMintMetadata? {
    let address = mint.base58
    let descriptor = FetchDescriptor<MintRecord>(
        predicate: #Predicate { $0.mintAddress == address }
    )
    return try? modelContext.fetch(descriptor).first?.toStoredMintMetadata()
}
```

Replace `database.getVMAuthority(mint:)`:

```swift
func getVMAuthority(mint: PublicKey) -> PublicKey? {
    let address = mint.base58
    let descriptor = FetchDescriptor<MintRecord>(
        predicate: #Predicate { $0.mintAddress == address }
    )
    guard let vmAuth = try? modelContext.fetch(descriptor).first?.vmAuthority else { return nil }
    return try? PublicKey(base58: vmAuth)
}
```

- [ ] **Step 5: Build and test**

Run: `xcodebuild build -scheme Flipcash -destination 'generic/platform=iOS'`
Run: `xcodebuild test -scheme Flipcash -destination 'platform=iOS Simulator,name=iPhone 17' -testPlan AllTargets`

- [ ] **Step 6: Commit**

```
git commit -m "refactor: replace database reads with @Query and ModelContext.fetch()"
```

---

## Task 8: Delete Old Code and Cleanup

**Files:**
- Delete: `Flipcash/Core/Controllers/Database/Database.swift`
- Delete: `Flipcash/Core/Controllers/Database/Schema.swift`
- Delete: `Flipcash/Core/Controllers/Database/Updateable.swift`
- Delete: `Flipcash/Core/Controllers/Database/Database+Balance.swift`
- Delete: `Flipcash/Core/Controllers/Database/Database+Activities.swift`
- Delete: `Flipcash/Core/Controllers/Database/Database+Limits.swift`
- Modify: `Flipcash/Core/Session/SessionAuthenticator.swift` — Remove `database` from `SessionContainer`
- Modify: `Flipcash/Supporting Files/Info.plist` — Bump `SQLiteVersion`

- [ ] **Step 1: Remove database from SessionContainer**

Remove `let database: Database` from `SessionContainer`. Remove `database` from `SessionAuthenticator.createSessionContainer()` and `SessionContainer.mock`.

- [ ] **Step 2: Remove Database dependency from all callers**

Search for any remaining `database.` references. Remove `database` property from Session, HistoryController, RatesController, ScanCashOperation, CurrencyInfoViewModel.

- [ ] **Step 3: Remove container passthrough from CurrencyInfoScreen**

Now that CurrencyInfoViewModel uses `ModelContext` instead of `Database`, remove `container`/`sessionContainer` from `CurrencyInfoScreen` init. The screen reads what it needs from `@Environment`:
- `@Environment(Session.self)` for session
- `@Environment(RatesController.self)` for rates
- `@Environment(\.modelContext)` for database queries

Update callers (BalanceScreen, GiveScreen, CurrencyDiscoveryScreen) to use simplified inits.

- [ ] **Step 4: Delete old database files**

```bash
git rm Flipcash/Core/Controllers/Database/Database.swift
git rm Flipcash/Core/Controllers/Database/Schema.swift
git rm Flipcash/Core/Controllers/Database/Updateable.swift
git rm Flipcash/Core/Controllers/Database/Database+Balance.swift
git rm Flipcash/Core/Controllers/Database/Database+Activities.swift
git rm Flipcash/Core/Controllers/Database/Database+Limits.swift
```

- [ ] **Step 5: Bump SQLiteVersion in Info.plist**

Increment the version number so existing installs delete the old SQLite database on next launch.

- [ ] **Step 6: Check if SQLite.swift package can be removed**

Search for `import SQLite` across all targets. If only the deleted files imported it, remove the package dependency from `Code.xcodeproj`.

**Warning:** The `Code/` (legacy) target may still use it. Verify before removing.

- [ ] **Step 7: Build and run full test suite**

Run: `xcodebuild build -scheme Flipcash -destination 'generic/platform=iOS'`
Run: `xcodebuild test -scheme Flipcash -destination 'platform=iOS Simulator,name=iPhone 17' -testPlan AllTargets`

- [ ] **Step 8: Commit**

```
git commit -m "refactor: delete SQLite.swift database layer, complete SwiftData migration"
```

---

## Verification Checklist

After all tasks:

- [ ] Build succeeds with no new warnings
- [ ] All tests pass (AllTargets test plan)
- [ ] No remaining references to `Database.swift`, `Schema.swift`, or `Updateable`
- [ ] No remaining `import SQLite` in Flipcash target
- [ ] SQLiteVersion bumped in Info.plist
- [ ] Manual test: fresh install → login → server sync populates data → balances display
- [ ] Manual test: currency info screen shows cached metadata instantly (no flash)
- [ ] Manual test: transaction history loads and updates reactively
- [ ] Manual test: give/buy/sell flows complete successfully
- [ ] Run `/swiftdata-pro` on final code for review
