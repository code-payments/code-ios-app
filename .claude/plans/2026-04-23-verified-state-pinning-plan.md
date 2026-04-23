# Pin `VerifiedState` for Amount-Entry Flows — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate "native amount does not match sell amount" server rejections by pinning one `VerifiedState` per amount-entry flow, persisting verified protos in SQLite, and making the pin the single source of truth for both UI math and intent submission.

**Architecture:** New SQLite tables (`verified_rate`, `verified_reserve`) store the signed protos so they survive cold start. `VerifiedProtoService` becomes the single writer; it warm-loads on init, persists on stream delivery. Each amount-entry ViewModel takes a pinned `VerifiedState` at construction time and treats it as immutable — stream updates arriving mid-flow land in cache for the next flow, not this one. `Session.buy/sell/withdraw` accept the pinned state as a required parameter and re-check staleness at submit; if the pin ages out (13 min client cutoff, 2 min below the 15 min server window), the UI surfaces an explicit refresh action rather than silently re-pinning.

**Tech Stack:** Swift 6 / iOS 17+, SwiftUI, Swift Testing, SQLite (dbart01/SQLite.swift fork), grpc-swift, SwiftProtobuf.

**Concurrency notes for the implementer:**
- `VerifiedProtoService` stays an `actor` (its in-memory dictionaries are shared mutable state). Callers cross the actor boundary with `await`.
- `RatesController.currentPinnedState(for:mint:)` is `async` because it reads through the actor; navigation handlers wrap the call in `Task { @MainActor in … }`.
- The ViewModels are `@Observable final class`; they are treated as `@MainActor` implicitly via their use sites. If strict concurrency in this target complains about non-Sendable VM types crossing the actor boundary in tests, mark the VM classes `@MainActor` or use `@preconcurrency` at the actor method signature.
- Warm-load inside `VerifiedProtoService.init` kicks off an unstructured `Task { await self.warmLoadFromStore() }`. Tests that rely on warm-load completion include a small `Task.sleep(nanoseconds: 100_000_000)` — brittle, but acceptable at the ms scale. If the warm-load ever changes to a deterministic completion signal, tighten the tests then.

**Design reference:** `.claude/plans/2026-04-23-verified-state-pinning.md`

**Commit policy:** Each task ends with a commit step. Per user preference, the executor should pause after each task for the user to sanity-check or request changes before running `git commit`. The commit commands in this plan are exact and ready to paste, not authorization to auto-commit.

---

## File Structure

### Create

- `FlipcashCore/Sources/FlipcashCore/Clients/Payments API/Services/VerifiedProtoStore.swift` — narrow protocol + struct for the DB read/write surface `VerifiedProtoService` depends on; lets us inject a fake in tests without dragging `Database` into `FlipcashCore`.
- `Flipcash/Core/Controllers/Database/Models/StoredVerifiedRate.swift` — thin row model bridging the `verified_rate` table to the proto + timestamp tuple.
- `Flipcash/Core/Controllers/Database/Models/StoredVerifiedReserve.swift` — same for `verified_reserve`.
- `Flipcash/Core/Controllers/Database/Database+VerifiedProtos.swift` — read/write extension on `Database` (write, read-by-key, read-all).
- `Flipcash/Core/Controllers/Database/VerifiedProtoStore+Database.swift` — conforms `Database` to `VerifiedProtoStore` so it can be passed into `VerifiedProtoService`.
- `FlipcashTests/TestSupport/InMemoryVerifiedProtoStore.swift` — test double used by `VerifiedProtoServiceTests` and any ViewModel test that needs a live cache.
- `FlipcashTests/VerifiedStateTests.swift`
- `FlipcashTests/Database/Database+VerifiedProtosTests.swift`
- `FlipcashTests/VerifiedProtoServiceTests.swift`
- `FlipcashTests/Regressions/Regression_native_amount_mismatch.swift`

### Modify

- `FlipcashCore/Sources/FlipcashCore/Models/VerifiedState.swift` — add `serverTimestamp`, `clientMaxAge`, `age`, `isStale`.
- `FlipcashCore/Sources/FlipcashCore/Clients/Payments API/Services/VerifiedProtoService.swift` — inject `VerifiedProtoStore`, warm-load on init, persist on save.
- `Flipcash/Core/Controllers/Database/Schema.swift` — two new tables.
- `Flipcash/Info.plist` — bump `SQLiteVersion`.
- `Flipcash/Core/Controllers/RatesController.swift` — add `maxAge:` to `awaitVerifiedState`, add `awaitPinnedState(for:mint:)` coordinator.
- `Flipcash/Core/Session/Session.swift` — buy/sell/withdraw accept `verifiedState`, drop internal `getVerifiedState()` calls, drop `Error.missingVerifiedState`, add `Error.verifiedStateStale` + staleness re-check.
- `Flipcash/Core/Screens/Main/Give/GiveViewModel.swift` — pin on init, reads from pin.
- `Flipcash/Core/Screens/Main/Give/GiveScreen.swift` (or containing coordinator) — await pin before constructing ViewModel.
- `Flipcash/Core/Screens/Main/Withdraw/WithdrawViewModel.swift` — same pattern.
- `Flipcash/Core/Screens/Main/Withdraw/WithdrawScreen.swift` (or coordinator) — await pin before constructing ViewModel.
- `Flipcash/Core/Screens/Currency/CurrencySellViewModel.swift` — same pattern.
- `Flipcash/Core/Screens/Currency/CurrencySellScreen.swift` (or coordinator) — await pin before constructing ViewModel.
- All Session call sites that currently call `buy`/`sell`/`withdraw` without passing verified state.

### Test

- Per file mapping above; unit test per new type, one regression file for the bug surface.

---

## Task 0: Branch setup

**Files:** none

- [ ] **Step 1: Confirm clean working tree and create branch**

Run:
```bash
git status
```
Expected: `working tree clean` on `chore/draft-gh-releases` or whatever branch the executor is on.

Run:
```bash
git fetch origin
git checkout -b fix/verified-state-pinning origin/main
```
Expected: new branch created from `origin/main`, tracking configured correctly. Before any commit on this branch, verify `git config --get branch.fix/verified-state-pinning.merge` shows `refs/heads/main` (per user's verify-branch-upstream feedback).

- [ ] **Step 2: Verify baseline build**

Run:
```bash
xcodebuild build -scheme Flipcash -destination 'generic/platform=iOS' -quiet
```
Expected: `BUILD SUCCEEDED`. Catches any pre-existing breakage so later failures are attributable to this plan.

---

## Task 1: Add `serverTimestamp`, `clientMaxAge`, `age`, `isStale` to `VerifiedState`

**Files:**
- Modify: `FlipcashCore/Sources/FlipcashCore/Models/VerifiedState.swift`
- Create: `FlipcashTests/VerifiedStateTests.swift`

Before writing, locate the server-signed timestamp on the two verified protos:
- `Ocp_Currency_V1_VerifiedCoreMintFiatExchangeRate` — a `google.protobuf.Timestamp` (likely a field named `timestamp`, `createdAt`, or similar; identified by being a proof field covered by the signature).
- `Ocp_Currency_V1_VerifiedLaunchpadCurrencyReserveState` — same pattern.

`SendCashOperation.swift` already extracts a `reserveTimestamp` — open it and find the exact conversion (likely `proto.reserveState.timestamp.date` or `Date(timeIntervalSince1970: TimeInterval(proto.timestamp.seconds))`). Reuse whatever helper it uses; if it uses an inline conversion, extract it into a helper in this task.

- [ ] **Step 1: Write the failing tests**

Create `FlipcashTests/VerifiedStateTests.swift`:

```swift
import Testing
import Foundation
@testable import FlipcashCore

@Suite("VerifiedState")
struct VerifiedStateTests {

    struct TimestampCase: Sendable, CustomTestStringConvertible {
        let name: String
        let rate: Date
        let reserve: Date?
        let expected: Date
        var testDescription: String { name }
    }

    @Test(
        "serverTimestamp uses the oldest available proof timestamp",
        arguments: [
            TimestampCase(
                name: "reserve is older than rate → uses reserve",
                rate: Date(timeIntervalSince1970: 1_000),
                reserve: Date(timeIntervalSince1970: 500),
                expected: Date(timeIntervalSince1970: 500)
            ),
            TimestampCase(
                name: "rate is older than reserve → uses rate",
                rate: Date(timeIntervalSince1970: 500),
                reserve: Date(timeIntervalSince1970: 1_000),
                expected: Date(timeIntervalSince1970: 500)
            ),
            TimestampCase(
                name: "reserve absent → falls back to rate",
                rate: Date(timeIntervalSince1970: 1_000),
                reserve: nil,
                expected: Date(timeIntervalSince1970: 1_000)
            ),
        ]
    )
    func serverTimestamp_picksOldestAvailable(scenario: TimestampCase) {
        let state = VerifiedState.makeForTest(
            rateTimestamp: scenario.rate,
            reserveTimestamp: scenario.reserve
        )
        #expect(state.serverTimestamp == scenario.expected)
    }

    struct StaleCase: Sendable, CustomTestStringConvertible {
        let name: String
        let offsetFromNow: TimeInterval
        let expected: Bool
        var testDescription: String { name }
    }

    @Test(
        "isStale boundary at clientMaxAge",
        arguments: [
            StaleCase(name: "brand new proof", offsetFromNow: 0, expected: false),
            StaleCase(name: "1 minute under the cutoff", offsetFromNow: -(VerifiedState.clientMaxAge - 60), expected: false),
            StaleCase(name: "1 second past the cutoff", offsetFromNow: -(VerifiedState.clientMaxAge + 1), expected: true),
            StaleCase(name: "5 minutes past the cutoff", offsetFromNow: -(VerifiedState.clientMaxAge + 5 * 60), expected: true),
        ]
    )
    func isStale_respectsBoundary(scenario: StaleCase) {
        let state = VerifiedState.makeForTest(
            rateTimestamp: Date().addingTimeInterval(scenario.offsetFromNow),
            reserveTimestamp: nil
        )
        #expect(state.isStale == scenario.expected)
    }

    @Test("clientMaxAge equals 13 minutes")
    func clientMaxAge_value() {
        #expect(VerifiedState.clientMaxAge == 13 * 60)
    }
}
```

Parameterization makes the intent crisp: one parameterized test for the "oldest wins" rule, one for the staleness boundary. `CustomTestStringConvertible` on the case structs gives readable failure names in the test navigator.

The `makeForTest` factory will live in `FlipcashTests/TestSupport/VerifiedState+TestSupport.swift` (Task 1 substep — create alongside the test).

Create `FlipcashTests/TestSupport/VerifiedState+TestSupport.swift`:

```swift
import Foundation
@testable import FlipcashCore
import FlipcashCoreAPI // adjust to the module that carries the Ocp_Currency_V1_* protos

extension VerifiedState {
    static func makeForTest(
        rateTimestamp: Date,
        reserveTimestamp: Date?
    ) -> VerifiedState {
        var rate = Ocp_Currency_V1_VerifiedCoreMintFiatExchangeRate()
        // Set whichever field carries the server timestamp — confirmed during the
        // exploration step at the top of Task 1. If the proto uses google.protobuf.Timestamp:
        //   rate.timestamp = .init(date: rateTimestamp)
        // If it uses int64 seconds:
        //   rate.timestampSeconds = Int64(rateTimestamp.timeIntervalSince1970)
        // Replace the placeholder with the actual field name.

        let reserve: Ocp_Currency_V1_VerifiedLaunchpadCurrencyReserveState? = reserveTimestamp.map {
            var r = Ocp_Currency_V1_VerifiedLaunchpadCurrencyReserveState()
            // Same treatment for the reserve's timestamp field.
            return r
        }

        return VerifiedState(rateProto: rate, reserveProto: reserve)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
xcodebuild test -scheme Flipcash -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FlipcashTests/VerifiedStateTests 2>&1 | tail -30
```
Expected: tests fail — `clientMaxAge`, `serverTimestamp`, `isStale` don't exist yet.

- [ ] **Step 3: Implement**

Edit `FlipcashCore/Sources/FlipcashCore/Models/VerifiedState.swift`. Add a `serverTimestamp` computed property, the `clientMaxAge` constant, and `age`/`isStale`:

```swift
public struct VerifiedState: Equatable, Sendable {
    public let rateProto: Ocp_Currency_V1_VerifiedCoreMintFiatExchangeRate
    public let reserveProto: Ocp_Currency_V1_VerifiedLaunchpadCurrencyReserveState?

    public init(
        rateProto: Ocp_Currency_V1_VerifiedCoreMintFiatExchangeRate,
        reserveProto: Ocp_Currency_V1_VerifiedLaunchpadCurrencyReserveState? = nil
    ) {
        self.rateProto = rateProto
        self.reserveProto = reserveProto
    }

    public var supplyFromBonding: UInt64? {
        reserveProto?.reserveState.supplyFromBonding
    }

    /// Server-signed timestamp for this proof bundle. When both protos are present,
    /// the older of the two drives staleness (that's the one closest to its
    /// server-side expiry). Uses the exact same field the server checks.
    public var serverTimestamp: Date {
        let rateDate = Self.date(from: rateProto) // replace with the concrete accessor below
        guard let reserveProto = reserveProto else { return rateDate }
        let reserveDate = Self.date(from: reserveProto)
        return min(rateDate, reserveDate)
    }

    /// Client-side freshness ceiling. Server accepts proofs up to 15 minutes old
    /// (measured against its signing clock); we stop at 13 to leave a 2-minute
    /// buffer for RTT and clock skew.
    public static let clientMaxAge: TimeInterval = 13 * 60

    public var age: TimeInterval {
        Date().timeIntervalSince(serverTimestamp)
    }

    public var isStale: Bool {
        age >= Self.clientMaxAge
    }

    // Replace the bodies below with whatever the protos actually expose.
    // If SendCashOperation already has a helper, call it here instead of duplicating.
    private static func date(from proto: Ocp_Currency_V1_VerifiedCoreMintFiatExchangeRate) -> Date {
        // e.g. proto.timestamp.date    (google.protobuf.Timestamp)
        // or   Date(timeIntervalSince1970: TimeInterval(proto.timestampSeconds))
        fatalError("replace with the actual accessor — see comment in Task 1")
    }

    private static func date(from proto: Ocp_Currency_V1_VerifiedLaunchpadCurrencyReserveState) -> Date {
        fatalError("replace with the actual accessor — see comment in Task 1")
    }
}
```

The `fatalError` placeholders are intentional: the implementer fills them in by looking at `SendCashOperation`'s existing `reserveTimestamp` extraction. Do not leave them after Task 1.

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
xcodebuild test -scheme Flipcash -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FlipcashTests/VerifiedStateTests 2>&1 | tail -20
```
Expected: all test cases pass (3 `@Test` functions, 8 parameterized runs in total).

- [ ] **Step 5: Commit**

```bash
git add FlipcashCore/Sources/FlipcashCore/Models/VerifiedState.swift \
        FlipcashTests/VerifiedStateTests.swift \
        FlipcashTests/TestSupport/VerifiedState+TestSupport.swift
git commit -m "$(cat <<'EOF'
feat: add serverTimestamp and staleness check to VerifiedState

Introduces clientMaxAge (13 min, 2 min below the server's 15 min window)
and the isStale predicate used by amount-entry flows to decide when to
force a refresh.
EOF
)"
```

---

## Task 2: Add `verified_rate` and `verified_reserve` tables to the schema

**Files:**
- Modify: `Flipcash/Core/Controllers/Database/Schema.swift`
- Create: `Flipcash/Core/Controllers/Database/Models/StoredVerifiedRate.swift`
- Create: `Flipcash/Core/Controllers/Database/Models/StoredVerifiedReserve.swift`

- [ ] **Step 1: Define the row models**

Create `Flipcash/Core/Controllers/Database/Models/StoredVerifiedRate.swift`:

```swift
import Foundation

struct StoredVerifiedRate: Equatable {
    let currency: String      // matches CurrencyCode raw value
    let rateProto: Data        // serialized Ocp_Currency_V1_VerifiedCoreMintFiatExchangeRate
    let receivedAt: Date       // when we received it from the stream (recorded for debugging)
}
```

Create `Flipcash/Core/Controllers/Database/Models/StoredVerifiedReserve.swift`:

```swift
import Foundation

struct StoredVerifiedReserve: Equatable {
    let mint: String           // base58 PublicKey
    let reserveProto: Data     // serialized Ocp_Currency_V1_VerifiedLaunchpadCurrencyReserveState
    let receivedAt: Date
}
```

Note: `receivedAt` here is our client-side receive time (useful for debugging and for warm-load ordering). The staleness check on `VerifiedState` uses the proof's server-signed timestamp, not this field.

- [ ] **Step 2: Add tables to `Schema.swift`**

Open `Flipcash/Core/Controllers/Database/Schema.swift` and add the two tables alongside the existing definitions. Follow the exact SQLite.swift expression style used for the surrounding tables (look at how `mint` and `balance` are declared around lines 13–46 to match indentation and naming conventions):

```swift
// Verified exchange-rate proofs, one per fiat currency.
enum VerifiedRateTable {
    static let table = Table("verified_rate")
    static let currency = Expression<String>("currency")
    static let rateProto = Expression<Data>("rateProto")
    static let receivedAt = Expression<Date>("receivedAt")

    static func create(_ connection: Connection) throws {
        try connection.run(table.create(ifNotExists: true) { t in
            t.column(currency, primaryKey: true)
            t.column(rateProto)
            t.column(receivedAt)
        })
    }
}

// Verified reserve-state proofs, one per mint.
enum VerifiedReserveTable {
    static let table = Table("verified_reserve")
    static let mint = Expression<String>("mint")
    static let reserveProto = Expression<Data>("reserveProto")
    static let receivedAt = Expression<Date>("receivedAt")

    static func create(_ connection: Connection) throws {
        try connection.run(table.create(ifNotExists: true) { t in
            t.column(mint, primaryKey: true)
            t.column(reserveProto)
            t.column(receivedAt)
        })
    }
}
```

Register both in the schema's `createAll` (or equivalent) — the existing function that gets called at database init.

- [ ] **Step 3: Build to verify compilation**

Run:
```bash
xcodebuild build -scheme Flipcash -destination 'generic/platform=iOS' -quiet
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add Flipcash/Core/Controllers/Database/Schema.swift \
        Flipcash/Core/Controllers/Database/Models/StoredVerifiedRate.swift \
        Flipcash/Core/Controllers/Database/Models/StoredVerifiedReserve.swift
git commit -m "feat(db): add verified_rate and verified_reserve tables"
```

---

## Task 3: Database read/write helpers for verified protos

**Files:**
- Create: `Flipcash/Core/Controllers/Database/Database+VerifiedProtos.swift`
- Create: `FlipcashTests/Database/Database+VerifiedProtosTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `FlipcashTests/Database/Database+VerifiedProtosTests.swift`:

```swift
import Testing
import Foundation
@testable import Flipcash

@Suite("Database+VerifiedProtos")
struct DatabaseVerifiedProtosTests {

    @Test("writeVerifiedRate then read returns the same row")
    func rate_roundTrip() throws {
        let db = try Database.makeInMemory()
        let proto = Data([0x01, 0x02, 0x03])
        let received = Date(timeIntervalSince1970: 1_000)

        try db.writeVerifiedRate(
            StoredVerifiedRate(currency: "USD", rateProto: proto, receivedAt: received)
        )

        let loaded = try db.readVerifiedRate(currency: "USD")
        #expect(loaded == StoredVerifiedRate(currency: "USD", rateProto: proto, receivedAt: received))
    }

    @Test("writeVerifiedRate upserts on the currency key")
    func rate_upsert() throws {
        let db = try Database.makeInMemory()
        try db.writeVerifiedRate(StoredVerifiedRate(currency: "USD", rateProto: Data([0x01]), receivedAt: Date(timeIntervalSince1970: 1_000)))
        try db.writeVerifiedRate(StoredVerifiedRate(currency: "USD", rateProto: Data([0x02]), receivedAt: Date(timeIntervalSince1970: 2_000)))

        let loaded = try db.readVerifiedRate(currency: "USD")
        #expect(loaded?.rateProto == Data([0x02]))
        #expect(loaded?.receivedAt == Date(timeIntervalSince1970: 2_000))
    }

    @Test("readVerifiedRate returns nil for missing currency")
    func rate_missing() throws {
        let db = try Database.makeInMemory()
        #expect(try db.readVerifiedRate(currency: "EUR") == nil)
    }

    @Test("readAllVerifiedRates returns every row")
    func rate_readAll() throws {
        let db = try Database.makeInMemory()
        try db.writeVerifiedRate(StoredVerifiedRate(currency: "USD", rateProto: Data([0x01]), receivedAt: Date(timeIntervalSince1970: 1_000)))
        try db.writeVerifiedRate(StoredVerifiedRate(currency: "EUR", rateProto: Data([0x02]), receivedAt: Date(timeIntervalSince1970: 2_000)))

        let all = try db.readAllVerifiedRates()
        #expect(Set(all.map(\.currency)) == ["USD", "EUR"])
    }

    @Test("writeVerifiedReserve then read returns the same row")
    func reserve_roundTrip() throws {
        let db = try Database.makeInMemory()
        let proto = Data([0xaa, 0xbb])
        let received = Date(timeIntervalSince1970: 500)
        let mint = "SomeBase58MintAddress"

        try db.writeVerifiedReserve(
            StoredVerifiedReserve(mint: mint, reserveProto: proto, receivedAt: received)
        )

        let loaded = try db.readVerifiedReserve(mint: mint)
        #expect(loaded == StoredVerifiedReserve(mint: mint, reserveProto: proto, receivedAt: received))
    }

    @Test("writeVerifiedReserve upserts on mint")
    func reserve_upsert() throws {
        let db = try Database.makeInMemory()
        let mint = "MintX"
        try db.writeVerifiedReserve(StoredVerifiedReserve(mint: mint, reserveProto: Data([0x01]), receivedAt: Date(timeIntervalSince1970: 1_000)))
        try db.writeVerifiedReserve(StoredVerifiedReserve(mint: mint, reserveProto: Data([0x02]), receivedAt: Date(timeIntervalSince1970: 2_000)))

        let loaded = try db.readVerifiedReserve(mint: mint)
        #expect(loaded?.reserveProto == Data([0x02]))
    }

    @Test("readAllVerifiedReserves returns every row")
    func reserve_readAll() throws {
        let db = try Database.makeInMemory()
        try db.writeVerifiedReserve(StoredVerifiedReserve(mint: "A", reserveProto: Data([0x01]), receivedAt: Date()))
        try db.writeVerifiedReserve(StoredVerifiedReserve(mint: "B", reserveProto: Data([0x02]), receivedAt: Date()))

        let all = try db.readAllVerifiedReserves()
        #expect(Set(all.map(\.mint)) == ["A", "B"])
    }
}
```

`Database.makeInMemory()` must exist already for the other `Database*Tests` in the repo. If it doesn't, add it in `FlipcashTests/TestSupport/Database+TestSupport.swift` following the existing SQLite.swift `:memory:` idiom (do NOT put it in production code).

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
xcodebuild test -scheme Flipcash -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FlipcashTests/DatabaseVerifiedProtosTests 2>&1 | tail -30
```
Expected: all tests fail — `writeVerifiedRate`, `readVerifiedRate`, etc. don't exist yet.

- [ ] **Step 3: Implement the helpers**

Create `Flipcash/Core/Controllers/Database/Database+VerifiedProtos.swift`:

```swift
import Foundation
import SQLite

extension Database {

    // MARK: - Rates

    func writeVerifiedRate(_ row: StoredVerifiedRate) throws {
        try writeQueue.sync {
            let insert = VerifiedRateTable.table.upsert(
                VerifiedRateTable.currency <- row.currency,
                VerifiedRateTable.rateProto <- row.rateProto,
                VerifiedRateTable.receivedAt <- row.receivedAt,
                onConflictOf: VerifiedRateTable.currency
            )
            try connection.run(insert)
        }
    }

    func readVerifiedRate(currency: String) throws -> StoredVerifiedRate? {
        try readQueue.sync {
            let query = VerifiedRateTable.table.filter(VerifiedRateTable.currency == currency)
            guard let row = try connection.pluck(query) else { return nil }
            return StoredVerifiedRate(
                currency: row[VerifiedRateTable.currency],
                rateProto: row[VerifiedRateTable.rateProto],
                receivedAt: row[VerifiedRateTable.receivedAt]
            )
        }
    }

    func readAllVerifiedRates() throws -> [StoredVerifiedRate] {
        try readQueue.sync {
            try connection.prepare(VerifiedRateTable.table).map { row in
                StoredVerifiedRate(
                    currency: row[VerifiedRateTable.currency],
                    rateProto: row[VerifiedRateTable.rateProto],
                    receivedAt: row[VerifiedRateTable.receivedAt]
                )
            }
        }
    }

    // MARK: - Reserves

    func writeVerifiedReserve(_ row: StoredVerifiedReserve) throws {
        try writeQueue.sync {
            let insert = VerifiedReserveTable.table.upsert(
                VerifiedReserveTable.mint <- row.mint,
                VerifiedReserveTable.reserveProto <- row.reserveProto,
                VerifiedReserveTable.receivedAt <- row.receivedAt,
                onConflictOf: VerifiedReserveTable.mint
            )
            try connection.run(insert)
        }
    }

    func readVerifiedReserve(mint: String) throws -> StoredVerifiedReserve? {
        try readQueue.sync {
            let query = VerifiedReserveTable.table.filter(VerifiedReserveTable.mint == mint)
            guard let row = try connection.pluck(query) else { return nil }
            return StoredVerifiedReserve(
                mint: row[VerifiedReserveTable.mint],
                reserveProto: row[VerifiedReserveTable.reserveProto],
                receivedAt: row[VerifiedReserveTable.receivedAt]
            )
        }
    }

    func readAllVerifiedReserves() throws -> [StoredVerifiedReserve] {
        try readQueue.sync {
            try connection.prepare(VerifiedReserveTable.table).map { row in
                StoredVerifiedReserve(
                    mint: row[VerifiedReserveTable.mint],
                    reserveProto: row[VerifiedReserveTable.reserveProto],
                    receivedAt: row[VerifiedReserveTable.receivedAt]
                )
            }
        }
    }
}
```

If `Database`'s internal `writeQueue` / `readQueue` / `connection` naming differs (exact names vary in this project), match what `Database+Balance.swift` and other existing extensions use.

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
xcodebuild test -scheme Flipcash -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FlipcashTests/DatabaseVerifiedProtosTests 2>&1 | tail -20
```
Expected: all 7 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Flipcash/Core/Controllers/Database/Database+VerifiedProtos.swift \
        FlipcashTests/Database/Database+VerifiedProtosTests.swift
git commit -m "feat(db): helpers to read/write verified proto rows"
```

---

## Task 4: Bump `SQLiteVersion` in `Info.plist`

**Files:**
- Modify: `Flipcash/Info.plist`

- [ ] **Step 1: Read current version**

Run:
```bash
/usr/libexec/PlistBuddy -c "Print :SQLiteVersion" Flipcash/Info.plist
```
Expected: current integer value (let's call it `N`).

- [ ] **Step 2: Bump by one**

Run:
```bash
/usr/libexec/PlistBuddy -c "Set :SQLiteVersion $((N+1))" Flipcash/Info.plist
```
(Replace `N+1` with the literal next integer.)

Verify:
```bash
/usr/libexec/PlistBuddy -c "Print :SQLiteVersion" Flipcash/Info.plist
```
Expected: the incremented value.

- [ ] **Step 3: Build**

Run:
```bash
xcodebuild build -scheme Flipcash -destination 'generic/platform=iOS' -quiet
```
Expected: `BUILD SUCCEEDED`. The rebuild-on-bump logic in `SessionAuthenticator.initializeDatabase` will fire on next login.

- [ ] **Step 4: Commit**

```bash
git add Flipcash/Info.plist
git commit -m "chore(db): bump SQLiteVersion for verified-proto tables"
```

---

## Task 5: `VerifiedProtoStore` abstraction + `Database` conformance

Goal: give `VerifiedProtoService` (in `FlipcashCore`) a narrow dependency on the DB so it can be unit-tested with a fake without importing `Flipcash`.

**Files:**
- Create: `FlipcashCore/Sources/FlipcashCore/Clients/Payments API/Services/VerifiedProtoStore.swift`
- Create: `Flipcash/Core/Controllers/Database/VerifiedProtoStore+Database.swift`
- Create: `FlipcashTests/TestSupport/InMemoryVerifiedProtoStore.swift`

- [ ] **Step 1: Define the protocol + value types in FlipcashCore**

Create `FlipcashCore/Sources/FlipcashCore/Clients/Payments API/Services/VerifiedProtoStore.swift`:

```swift
import Foundation

/// Persistence surface required by `VerifiedProtoService`. Keeping this narrow lets
/// the service live in FlipcashCore without depending on the main-app `Database`.
public protocol VerifiedProtoStore: Sendable {
    func allRates() throws -> [StoredRateRow]
    func allReserves() throws -> [StoredReserveRow]
    func writeRate(_ row: StoredRateRow) throws
    func writeReserve(_ row: StoredReserveRow) throws
}

public struct StoredRateRow: Equatable, Sendable {
    public let currency: String
    public let rateProto: Data
    public let receivedAt: Date

    public init(currency: String, rateProto: Data, receivedAt: Date) {
        self.currency = currency
        self.rateProto = rateProto
        self.receivedAt = receivedAt
    }
}

public struct StoredReserveRow: Equatable, Sendable {
    public let mint: String
    public let reserveProto: Data
    public let receivedAt: Date

    public init(mint: String, reserveProto: Data, receivedAt: Date) {
        self.mint = mint
        self.reserveProto = reserveProto
        self.receivedAt = receivedAt
    }
}
```

- [ ] **Step 2: Conform `Database` to `VerifiedProtoStore`**

Create `Flipcash/Core/Controllers/Database/VerifiedProtoStore+Database.swift`:

```swift
import Foundation
import FlipcashCore

extension Database: VerifiedProtoStore {

    public func allRates() throws -> [StoredRateRow] {
        try readAllVerifiedRates().map {
            StoredRateRow(currency: $0.currency, rateProto: $0.rateProto, receivedAt: $0.receivedAt)
        }
    }

    public func allReserves() throws -> [StoredReserveRow] {
        try readAllVerifiedReserves().map {
            StoredReserveRow(mint: $0.mint, reserveProto: $0.reserveProto, receivedAt: $0.receivedAt)
        }
    }

    public func writeRate(_ row: StoredRateRow) throws {
        try writeVerifiedRate(
            StoredVerifiedRate(currency: row.currency, rateProto: row.rateProto, receivedAt: row.receivedAt)
        )
    }

    public func writeReserve(_ row: StoredReserveRow) throws {
        try writeVerifiedReserve(
            StoredVerifiedReserve(mint: row.mint, reserveProto: row.reserveProto, receivedAt: row.receivedAt)
        )
    }
}
```

- [ ] **Step 3: In-memory fake for tests**

Create `FlipcashTests/TestSupport/InMemoryVerifiedProtoStore.swift`:

```swift
import Foundation
import FlipcashCore

final class InMemoryVerifiedProtoStore: VerifiedProtoStore, @unchecked Sendable {
    private let lock = NSLock()
    private var rates: [String: StoredRateRow] = [:]
    private var reserves: [String: StoredReserveRow] = [:]
    private(set) var writeRateCalls: [StoredRateRow] = []
    private(set) var writeReserveCalls: [StoredReserveRow] = []

    var writeRateError: Error?
    var writeReserveError: Error?

    func allRates() throws -> [StoredRateRow] {
        lock.lock(); defer { lock.unlock() }
        return Array(rates.values)
    }

    func allReserves() throws -> [StoredReserveRow] {
        lock.lock(); defer { lock.unlock() }
        return Array(reserves.values)
    }

    func writeRate(_ row: StoredRateRow) throws {
        if let writeRateError { throw writeRateError }
        lock.lock(); defer { lock.unlock() }
        rates[row.currency] = row
        writeRateCalls.append(row)
    }

    func writeReserve(_ row: StoredReserveRow) throws {
        if let writeReserveError { throw writeReserveError }
        lock.lock(); defer { lock.unlock() }
        reserves[row.mint] = row
        writeReserveCalls.append(row)
    }
}
```

- [ ] **Step 4: Build and run existing DB tests to confirm nothing regressed**

Run:
```bash
xcodebuild test -scheme Flipcash -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FlipcashTests/DatabaseVerifiedProtosTests 2>&1 | tail -20
```
Expected: all tests still pass.

- [ ] **Step 5: Commit**

```bash
git add FlipcashCore/Sources/FlipcashCore/Clients/Payments\ API/Services/VerifiedProtoStore.swift \
        Flipcash/Core/Controllers/Database/VerifiedProtoStore+Database.swift \
        FlipcashTests/TestSupport/InMemoryVerifiedProtoStore.swift
git commit -m "feat(core): VerifiedProtoStore abstraction for verified-proto persistence"
```

---

## Task 6: `VerifiedProtoService` persists on write + warm-loads on init

**Files:**
- Modify: `FlipcashCore/Sources/FlipcashCore/Clients/Payments API/Services/VerifiedProtoService.swift`
- Create: `FlipcashTests/VerifiedProtoServiceTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `FlipcashTests/VerifiedProtoServiceTests.swift`:

```swift
import Testing
import Foundation
import Combine
@testable import FlipcashCore

@Suite("VerifiedProtoService")
struct VerifiedProtoServiceTests {

    @Test("saveRates persists each rate to the store")
    func saveRates_persists() async throws {
        let store = InMemoryVerifiedProtoStore()
        let service = VerifiedProtoService(store: store, clock: { Date(timeIntervalSince1970: 1_000) })

        var rateProto = Ocp_Currency_V1_VerifiedCoreMintFiatExchangeRate()
        // populate whichever fields uniquely identify a rate for the `currency` key

        await service.saveRates(["USD": rateProto])

        // small settle delay for the background write
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(store.writeRateCalls.count == 1)
        #expect(store.writeRateCalls.first?.currency == "USD")
        #expect(store.writeRateCalls.first?.receivedAt == Date(timeIntervalSince1970: 1_000))
    }

    @Test("saveReserveStates persists each reserve to the store")
    func saveReserves_persists() async throws {
        let store = InMemoryVerifiedProtoStore()
        let service = VerifiedProtoService(store: store, clock: { Date(timeIntervalSince1970: 500) })

        var reserveProto = Ocp_Currency_V1_VerifiedLaunchpadCurrencyReserveState()
        // populate fields; use a stable mint key

        await service.saveReserveStates([PublicKey.anyTestKey: reserveProto])

        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(store.writeReserveCalls.count == 1)
        #expect(store.writeReserveCalls.first?.receivedAt == Date(timeIntervalSince1970: 500))
    }

    @Test("init warm-loads rates and reserves from store into publishers")
    func init_warmLoad() async throws {
        let store = InMemoryVerifiedProtoStore()
        try store.writeRate(StoredRateRow(currency: "USD", rateProto: Data([0x01]), receivedAt: Date()))
        try store.writeReserve(StoredReserveRow(mint: "MintA", reserveProto: Data([0x02]), receivedAt: Date()))

        let service = VerifiedProtoService(store: store, clock: { Date() })

        var receivedRates: [CurrencyCode: Ocp_Currency_V1_VerifiedCoreMintFiatExchangeRate] = [:]
        let cancellable = service.ratesPublisher.sink { receivedRates = $0 }

        // give the warm-load publisher emission a turn on the main queue
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(receivedRates.keys.contains(.usd))
        cancellable.cancel()
    }

    @Test("write failure logs but does not prevent in-memory update")
    func writeFailure_fallsThrough() async throws {
        let store = InMemoryVerifiedProtoStore()
        store.writeRateError = TestError.any
        let service = VerifiedProtoService(store: store, clock: { Date() })

        var rateProto = Ocp_Currency_V1_VerifiedCoreMintFiatExchangeRate()
        await service.saveRates(["USD": rateProto])

        // In-memory cache should still reflect the new value even though write failed.
        let state = await service.getVerifiedState(for: .usd, mint: .usdfMintKey)
        #expect(state?.rateProto != nil)
    }
}

private enum TestError: Error { case any }
```

Some symbols in the tests above (`PublicKey.anyTestKey`, `.usdfMintKey`, populated proto fields) must be filled in with whatever the project exposes. If there isn't already a test fixture for a `PublicKey`, add a small helper in `FlipcashTests/TestSupport/`.

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
xcodebuild test -scheme Flipcash -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FlipcashTests/VerifiedProtoServiceTests 2>&1 | tail -30
```
Expected: tests fail — the service doesn't have a `store` parameter or `clock`, warm-load isn't implemented.

- [ ] **Step 3: Update `VerifiedProtoService`**

Open `FlipcashCore/Sources/FlipcashCore/Clients/Payments API/Services/VerifiedProtoService.swift`. Change the actor's init to take the store and a clock, add the DB side-effect to the two save methods, and warm-load in init.

```swift
public actor VerifiedProtoService {

    // Existing in-memory caches — unchanged structure.
    private var exchangeRates: [CurrencyCode: Ocp_Currency_V1_VerifiedCoreMintFiatExchangeRate] = [:]
    private var reserveStates: [PublicKey: Ocp_Currency_V1_VerifiedLaunchpadCurrencyReserveState] = [:]

    private let ratesSubject = CurrentValueSubject<[CurrencyCode: Ocp_Currency_V1_VerifiedCoreMintFiatExchangeRate], Never>([:])
    private let reservesSubject = CurrentValueSubject<[PublicKey: Ocp_Currency_V1_VerifiedLaunchpadCurrencyReserveState], Never>([:])

    public nonisolated var ratesPublisher: AnyPublisher<[CurrencyCode: Ocp_Currency_V1_VerifiedCoreMintFiatExchangeRate], Never> {
        ratesSubject.eraseToAnyPublisher()
    }

    public nonisolated var reserveStatesPublisher: AnyPublisher<[PublicKey: Ocp_Currency_V1_VerifiedLaunchpadCurrencyReserveState], Never> {
        reservesSubject.eraseToAnyPublisher()
    }

    private let store: VerifiedProtoStore
    private let clock: @Sendable () -> Date
    private let logger = Logger(label: "VerifiedProtoService") // use existing project logger API

    public init(store: VerifiedProtoStore, clock: @Sendable @escaping () -> Date = Date.init) {
        self.store = store
        self.clock = clock
        Task { await self.warmLoadFromStore() }
    }

    // MARK: - Warm load

    private func warmLoadFromStore() async {
        do {
            let storedRates = try store.allRates()
            for row in storedRates {
                guard let currency = CurrencyCode(rawValue: row.currency) else { continue }
                if let proto = try? Ocp_Currency_V1_VerifiedCoreMintFiatExchangeRate(serializedBytes: row.rateProto) {
                    exchangeRates[currency] = proto
                }
            }
            let storedReserves = try store.allReserves()
            for row in storedReserves {
                guard let key = PublicKey(base58: row.mint) else { continue }
                if let proto = try? Ocp_Currency_V1_VerifiedLaunchpadCurrencyReserveState(serializedBytes: row.reserveProto) {
                    reserveStates[key] = proto
                }
            }
            ratesSubject.send(exchangeRates)
            reservesSubject.send(reserveStates)
        } catch {
            logger.warning("Failed to warm-load verified protos", metadata: ["error": "\(error)"])
        }
    }

    // MARK: - Save

    public func saveRates(_ rates: [CurrencyCode: Ocp_Currency_V1_VerifiedCoreMintFiatExchangeRate]) {
        let now = clock()
        for (currency, proto) in rates {
            exchangeRates[currency] = proto
            persistRate(currency: currency, proto: proto, receivedAt: now)
        }
        ratesSubject.send(exchangeRates)
    }

    public func saveReserveStates(_ states: [PublicKey: Ocp_Currency_V1_VerifiedLaunchpadCurrencyReserveState]) {
        let now = clock()
        for (mint, proto) in states {
            reserveStates[mint] = proto
            persistReserve(mint: mint, proto: proto, receivedAt: now)
        }
        reservesSubject.send(reserveStates)
    }

    private func persistRate(
        currency: CurrencyCode,
        proto: Ocp_Currency_V1_VerifiedCoreMintFiatExchangeRate,
        receivedAt: Date
    ) {
        do {
            let data = try proto.serializedData()
            try store.writeRate(
                StoredRateRow(currency: currency.rawValue, rateProto: data, receivedAt: receivedAt)
            )
        } catch {
            logger.warning("Failed to persist verified rate", metadata: [
                "currency": "\(currency.rawValue)",
                "error": "\(error)"
            ])
        }
    }

    private func persistReserve(
        mint: PublicKey,
        proto: Ocp_Currency_V1_VerifiedLaunchpadCurrencyReserveState,
        receivedAt: Date
    ) {
        do {
            let data = try proto.serializedData()
            try store.writeReserve(
                StoredReserveRow(mint: mint.base58, reserveProto: data, receivedAt: receivedAt)
            )
        } catch {
            logger.warning("Failed to persist verified reserve", metadata: [
                "mint": "\(mint.base58)",
                "error": "\(error)"
            ])
        }
    }

    // MARK: - Existing API (unchanged signatures)

    public func getVerifiedState(for currency: CurrencyCode, mint: PublicKey) -> VerifiedState? {
        guard let rateProto = exchangeRates[currency] else { return nil }
        return VerifiedState(rateProto: rateProto, reserveProto: reserveStates[mint])
    }

    public func clear() {
        exchangeRates.removeAll()
        reserveStates.removeAll()
        ratesSubject.send([:])
        reservesSubject.send([:])
    }
}
```

- [ ] **Step 4: Update call sites that construct `VerifiedProtoService`**

Find every `VerifiedProtoService(` in the project and pass in a `store`. The only production call site is `RatesController` — open `Flipcash/Core/Controllers/RatesController.swift` and change:

```swift
self.verifiedProtoService = VerifiedProtoService(store: database)
```

(The `database` reference already lives on `RatesController` per the existing architecture.)

- [ ] **Step 5: Run tests to verify they pass**

Run:
```bash
xcodebuild test -scheme Flipcash -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FlipcashTests/VerifiedProtoServiceTests 2>&1 | tail -20
```
Expected: all 4 tests pass.

Run the broader DB tests too as a sanity check that nothing regressed:
```bash
xcodebuild test -scheme Flipcash -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FlipcashTests/DatabaseVerifiedProtosTests 2>&1 | tail -10
```
Expected: pass.

- [ ] **Step 6: Commit**

```bash
git add FlipcashCore/Sources/FlipcashCore/Clients/Payments\ API/Services/VerifiedProtoService.swift \
        Flipcash/Core/Controllers/RatesController.swift \
        FlipcashTests/VerifiedProtoServiceTests.swift
git commit -m "feat(core): persist verified protos and warm-load on launch"
```

---

## Task 7: Add `currentPinnedState(for:mint:)` convenience on `RatesController`

Navigation handlers need a quick, synchronous-ish "is there a usable proof right now?" answer. No polling, no waiting, no spinner UI — if the answer is "no," the navigation silently doesn't happen (in practice always "yes" because the stream + DB warm-load keep the cache populated).

**Files:**
- Modify: `Flipcash/Core/Controllers/RatesController.swift`
- Create: `FlipcashTests/RatesControllerTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import Flipcash
@testable import FlipcashCore

@Suite("RatesController.currentPinnedState")
struct RatesControllerCurrentPinnedStateTests {

    @Test("Returns nil when nothing is cached")
    func nilWhenEmpty() async {
        let controller = RatesController.makeForTest(rates: [:], reserves: [:])
        #expect(await controller.currentPinnedState(for: .usd, mint: .testBondedMint) == nil)
    }

    @Test("Returns nil when the cached rate is older than clientMaxAge")
    func nilWhenStale() async {
        let controller = RatesController.makeForTest(
            rates: ["USD": .staleRate()],
            reserves: [:]
        )
        #expect(await controller.currentPinnedState(for: .usd, mint: .testBondedMint) == nil)
    }

    @Test("Returns the cached state when inside the freshness window")
    func returnsFresh() async {
        let controller = RatesController.makeForTest(
            rates: ["USD": .freshRate()],
            reserves: [PublicKey.testBondedMint: .freshReserve(supplyFromBonding: 1)]
        )
        let state = await controller.currentPinnedState(for: .usd, mint: .testBondedMint)
        #expect(state?.isStale == false)
    }
}
```

`RatesController.makeForTest(...)`, `.freshRate()`, `.staleRate()`, `.freshReserve(...)` live in `FlipcashTests/TestSupport/`; the factory wires a `VerifiedProtoService` around an `InMemoryVerifiedProtoStore`.

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -scheme Flipcash -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FlipcashTests/RatesControllerCurrentPinnedStateTests 2>&1 | tail -30
```
Expected: fail — `currentPinnedState` does not exist.

- [ ] **Step 3: Implement**

In `Flipcash/Core/Controllers/RatesController.swift`:

```swift
/// Returns a non-stale `VerifiedState` if one is currently cached — otherwise nil.
/// Does not poll, does not wait. Callers use this right before opening an
/// amount-entry flow; if nil, they should not open the flow (the caller decides
/// how — typically a silent no-op because the stream + DB warm-load keep the
/// cache populated).
public func currentPinnedState(
    for currency: CurrencyCode,
    mint: PublicKey
) async -> VerifiedState? {
    guard let state = await verifiedProtoService.getVerifiedState(for: currency, mint: mint),
          !state.isStale
    else {
        return nil
    }
    return state
}
```

This is intentionally tiny. No new error types, no timeouts, no polling loops — staleness handling is a UI problem and the UI is not allowed to show anything for it (zero UX changes). If the cache is empty or stale, `nil` is the answer and the caller deals.

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild test -scheme Flipcash -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FlipcashTests/RatesControllerCurrentPinnedStateTests 2>&1 | tail -20
```
Expected: all 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Flipcash/Core/Controllers/RatesController.swift \
        FlipcashTests/RatesControllerTests.swift \
        FlipcashTests/TestSupport/RatesController+TestSupport.swift
git commit -m "feat: currentPinnedState convenience on RatesController"
```

---

## Task 8: Add `Session.Error.verifiedStateStale`

**Files:**
- Modify: `Flipcash/Core/Session/Session.swift`

- [ ] **Step 1: Locate `Session.Error` and add the case**

Find the `Session.Error` enum (exploration noted branches for `missingVerifiedState`, `missingSupply`, etc.). Add:

```swift
case verifiedStateStale(ageSeconds: TimeInterval)
```

If `Session.Error` isn't equatable, skip equatability — callers switch on it exhaustively. Remember: CLAUDE.md says prefer exhaustive `switch` over `if case`.

- [ ] **Step 2: Build**

Run:
```bash
xcodebuild build -scheme Flipcash -destination 'generic/platform=iOS' -quiet
```
Expected: `BUILD SUCCEEDED`. Adding a case can fail compile if any existing `switch` is exhaustive without a default — fix those switches by adding a case arm for `verifiedStateStale` that logs + rethrows (or treat it as a temporary generic error for now; Task 9/10/11 will wire the proper handling).

- [ ] **Step 3: Commit**

```bash
git add Flipcash/Core/Session/Session.swift
git commit -m "feat(session): add verifiedStateStale error case"
```

---

## Task 9: `Session.buy` takes `verifiedState` and drops internal fetch

**Files:**
- Modify: `Flipcash/Core/Session/Session.swift`
- Modify: all call sites of `Session.buy`
- Create/Modify: `FlipcashTests/SessionTests.swift`

- [ ] **Step 1: Write the failing test**

Extend `FlipcashTests/SessionTests.swift`:

```swift
@Suite("Session.buy verified state")
struct SessionBuyVerifiedStateTests {

    @Test("Throws verifiedStateStale when the provided state is past clientMaxAge")
    func buy_throwsStale() async {
        let session = Session.makeForTest()
        let stale = VerifiedState.makeForTest(
            rateTimestamp: Date().addingTimeInterval(-VerifiedState.clientMaxAge - 1),
            reserveTimestamp: nil
        )
        do {
            _ = try await session.buy(
                amount: .testUsdcFive,
                verifiedState: stale,
                of: .testUsdcMetadata,
                owner: .testOwner
            )
            Issue.record("expected stale throw")
        } catch Session.Error.verifiedStateStale {
            // expected
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test("Passes the exact same verifiedState to the client when fresh")
    func buy_passesStateThrough() async throws {
        let client = FakeFlipClient()
        let session = Session.makeForTest(client: client)
        let fresh = VerifiedState.makeForTest(rateTimestamp: Date(), reserveTimestamp: Date())
        _ = try await session.buy(
            amount: .testUsdcFive,
            verifiedState: fresh,
            of: .testUsdcMetadata,
            owner: .testOwner
        )
        #expect(client.lastBuyCall?.verifiedState == fresh)
    }
}
```

`FakeFlipClient` and `.testOwner`, `.testUsdcMetadata`, `.testUsdcFive` either already exist in the test target or need minimal additions in `FlipcashTests/TestSupport/`.

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
xcodebuild test -scheme Flipcash -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FlipcashTests/SessionBuyVerifiedStateTests 2>&1 | tail -20
```
Expected: `buy` signature mismatch — test won't compile.

- [ ] **Step 3: Update `Session.buy`**

Open `Flipcash/Core/Session/Session.swift` around line 592. Replace the internal `getVerifiedState` fetch with a required parameter + staleness check:

```swift
func buy(
    amount: ExchangedFiat,
    verifiedState: VerifiedState,
    of token: Token,
    owner: KeyPair
) async throws -> TransactionID {
    if verifiedState.isStale {
        logger.info("Rejected stale verifiedState at buy", metadata: [
            "currency": "\(amount.nativeAmount.currency.rawValue)",
            "mint": "\(amount.mint.base58)",
            "ageSeconds": "\(verifiedState.age)",
            "clientMaxAge": "\(VerifiedState.clientMaxAge)"
        ])
        throw Error.verifiedStateStale(ageSeconds: verifiedState.age)
    }
    return try await client.buy(
        amount: amount,
        verifiedState: verifiedState,
        of: token.metadata,
        owner: owner
    )
}
```

Remove the `Error.missingVerifiedState` throw and its enum case if no other path still uses it. (If one does, leave the case; it becomes dead for this path but is not a breaking removal yet.)

- [ ] **Step 4: Update call sites**

Grep:
```bash
grep -rn "session.buy(" Flipcash FlipcashCore | grep -v Tests
```

For each caller, pass the `verifiedState` that was used to build the `amount`. Two cases:

- **Caller has a pinned state in scope** (post-Task 11): pass it directly.
- **Caller still fetches mid-flow** (pre-Task 11 transitional code): temporarily call `RatesController.getVerifiedState(for:mint:)` inline at the call site. This is ugly and will be cleaned up by Tasks 11–13 — add a `// TODO: pin upstream (Task 11)` comment at each such site so it's easy to find later.

- [ ] **Step 5: Run tests to verify they pass**

Run:
```bash
xcodebuild test -scheme Flipcash -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FlipcashTests/SessionBuyVerifiedStateTests 2>&1 | tail -20
```
Expected: both tests pass.

- [ ] **Step 6: Commit**

```bash
git add Flipcash/Core/Session/Session.swift \
        FlipcashTests/SessionTests.swift \
        <any call-site files touched>
git commit -m "refactor(session): buy requires verifiedState as parameter"
```

---

## Task 10: `Session.sell` takes `verifiedState`

**Files:**
- Modify: `Flipcash/Core/Session/Session.swift`
- Modify: all call sites of `Session.sell`
- Modify: `FlipcashTests/SessionTests.swift`

Same pattern as Task 9. The existing `Session.sell` (lines 733–762) has two branches worth examining:

1. The `guard let supply = verifiedState.supplyFromBonding else { throw Error.missingSupply }` — keep this; `Session.sell` is bonded-currency-only, so missing supply remains a true error.
2. The "on-chain amount exceeds balance" workaround at `Session.swift:747-757`. **Verify during implementation whether it becomes obsolete.** The workaround exists because the UI's supply and the intent's supply could differ; once we pin upstream, they can't. If the manual test in Task 16 shows the workaround never fires, remove it in a follow-up task added at the end of this plan (keep a short note in `Task 10.post`).

- [ ] **Step 1: Failing tests**

```swift
@Suite("Session.sell verified state")
struct SessionSellVerifiedStateTests {

    @Test("Throws verifiedStateStale for stale state")
    func sell_throwsStale() async {
        let session = Session.makeForTest()
        let stale = VerifiedState.makeForTest(
            rateTimestamp: Date().addingTimeInterval(-VerifiedState.clientMaxAge - 1),
            reserveTimestamp: Date().addingTimeInterval(-VerifiedState.clientMaxAge - 1)
        )
        do {
            _ = try await session.sell(
                amount: .testBondedFive,
                verifiedState: stale,
                mint: .testBondedMint,
                owner: .testOwner
            )
            Issue.record("expected stale throw")
        } catch Session.Error.verifiedStateStale {
            // expected
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test("Passes the exact same verifiedState to the client when fresh")
    func sell_passesStateThrough() async throws {
        let client = FakeFlipClient()
        let session = Session.makeForTest(client: client)
        let fresh = VerifiedState.makeForTest(rateTimestamp: Date(), reserveTimestamp: Date())
        _ = try await session.sell(
            amount: .testBondedFive,
            verifiedState: fresh,
            mint: .testBondedMint,
            owner: .testOwner
        )
        #expect(client.lastSellCall?.verifiedState == fresh)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -scheme Flipcash -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FlipcashTests/SessionSellVerifiedStateTests 2>&1 | tail -20
```

- [ ] **Step 3: Update `Session.sell`**

Replace the internal `getVerifiedState` lookup at `Session.swift:733-762` with a required parameter. Keep the `guard let supply = verifiedState.supplyFromBonding` guard. Add the staleness check first:

```swift
func sell(
    amount: ExchangedFiat,
    verifiedState: VerifiedState,
    mint: PublicKey,
    owner: KeyPair
) async throws -> TransactionID {
    if verifiedState.isStale {
        logger.info("Rejected stale verifiedState at sell", metadata: [
            "currency": "\(amount.nativeAmount.currency.rawValue)",
            "mint": "\(mint.base58)",
            "ageSeconds": "\(verifiedState.age)",
            "clientMaxAge": "\(VerifiedState.clientMaxAge)"
        ])
        throw Error.verifiedStateStale(ageSeconds: verifiedState.age)
    }
    guard let supply = verifiedState.supplyFromBonding else {
        throw Error.missingSupply
    }
    // existing amount-for-intent adjustment kept as-is — flagged for review in Task 16.
    let amountForIntent: ExchangedFiat = /* existing branch preserved verbatim */
    return try await client.sell(
        amount: amountForIntent,
        verifiedState: verifiedState,
        mint: mint,
        owner: owner
    )
}
```

- [ ] **Step 4: Update call sites** (same pattern as Task 9 step 4).

- [ ] **Step 5: Run tests to verify they pass**

```bash
xcodebuild test -scheme Flipcash -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FlipcashTests/SessionSellVerifiedStateTests 2>&1 | tail -20
```
Expected: both tests pass.

- [ ] **Step 6: Commit**

```bash
git add Flipcash/Core/Session/Session.swift FlipcashTests/SessionTests.swift <call-site files>
git commit -m "refactor(session): sell requires verifiedState as parameter"
```

---

## Task 11: `Session.withdraw` takes `verifiedState`

**Files:**
- Modify: `Flipcash/Core/Session/Session.swift`
- Modify: call sites
- Modify: `FlipcashTests/SessionTests.swift`

Same pattern as Tasks 9–10, for the `withdraw` method at `Session.swift:776-793`.

- [ ] **Step 1: Failing tests**

```swift
@Suite("Session.withdraw verified state")
struct SessionWithdrawVerifiedStateTests {

    @Test("Throws verifiedStateStale for stale state")
    func withdraw_throwsStale() async {
        let session = Session.makeForTest()
        let stale = VerifiedState.makeForTest(
            rateTimestamp: Date().addingTimeInterval(-VerifiedState.clientMaxAge - 1),
            reserveTimestamp: nil
        )
        do {
            _ = try await session.withdraw(
                exchangedFiat: .testUsdfFive,
                verifiedState: stale,
                mint: .usdfMintKey,
                destination: .testDestination,
                owner: .testOwner
            )
            Issue.record("expected stale throw")
        } catch Session.Error.verifiedStateStale {
            // expected
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test("Passes the exact same verifiedState to the client when fresh")
    func withdraw_passesStateThrough() async throws {
        let client = FakeFlipClient()
        let session = Session.makeForTest(client: client)
        let fresh = VerifiedState.makeForTest(rateTimestamp: Date(), reserveTimestamp: nil)
        _ = try await session.withdraw(
            exchangedFiat: .testUsdfFive,
            verifiedState: fresh,
            mint: .usdfMintKey,
            destination: .testDestination,
            owner: .testOwner
        )
        #expect(client.lastWithdrawCall?.verifiedState == fresh)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -scheme Flipcash -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FlipcashTests/SessionWithdrawVerifiedStateTests 2>&1 | tail -20
```

- [ ] **Step 3: Update `Session.withdraw`**

```swift
func withdraw(
    exchangedFiat: ExchangedFiat,
    verifiedState: VerifiedState,
    mint: PublicKey,
    destination: PublicKey,
    owner: KeyPair
) async throws -> TransactionID {
    if verifiedState.isStale {
        logger.info("Rejected stale verifiedState at withdraw", metadata: [
            "currency": "\(exchangedFiat.nativeAmount.currency.rawValue)",
            "mint": "\(mint.base58)",
            "ageSeconds": "\(verifiedState.age)",
            "clientMaxAge": "\(VerifiedState.clientMaxAge)"
        ])
        throw Error.verifiedStateStale(ageSeconds: verifiedState.age)
    }
    return try await client.withdraw(
        exchangedFiat: exchangedFiat,
        verifiedState: verifiedState,
        mint: mint,
        destination: destination,
        owner: owner
    )
}
```

- [ ] **Step 4: Update call sites.** Same pattern.

- [ ] **Step 5: Run tests to verify they pass**

```bash
xcodebuild test -scheme Flipcash -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FlipcashTests/SessionWithdrawVerifiedStateTests 2>&1 | tail -20
```

- [ ] **Step 6: Commit**

```bash
git add Flipcash/Core/Session/Session.swift FlipcashTests/SessionTests.swift <call-site files>
git commit -m "refactor(session): withdraw requires verifiedState as parameter"
```

---

## Task 12: Pin `VerifiedState` in `GiveViewModel`

Zero UX changes. The Give screen looks and behaves exactly like it does today — no new loading state, no refresh prompt, no error retry view, no phase enum. The only new behavior is that the submit action is gated on the pin being present and fresh.

**Files:**
- Modify: `Flipcash/Core/Screens/Main/Give/GiveViewModel.swift`
- Modify: whichever view currently navigates into the Give flow (home screen or an intermediate coordinator)
- Create: `FlipcashTests/GiveViewModelTests.swift`
- Create: `FlipcashTests/TestSupport/GiveViewModel+TestSupport.swift`

- [ ] **Step 1: Failing tests**

Create `FlipcashTests/GiveViewModelTests.swift`:

```swift
import Testing
import Foundation
@testable import Flipcash
@testable import FlipcashCore

@Suite("GiveViewModel pinning")
struct GiveViewModelPinningTests {

    @Test("ExchangedFiat computes against pinned supply, not DB supply")
    func usesPinnedSupply() {
        let pinnedSupply: UInt64 = 1_000_000
        let dbSupply: UInt64 = 9_999_999
        let pinnedState = VerifiedState.makeForTest(
            rateTimestamp: Date(),
            reserveTimestamp: Date(),
            supplyFromBonding: pinnedSupply
        )
        let vm = GiveViewModel.makeForTest(
            pinnedState: pinnedState,
            selectedBalance: .testBondedBalance(supplyFromBonding: dbSupply)
        )
        vm.updateAmount("5.00")

        let expected = ExchangedFiat.compute(
            fromEntered: FiatAmount(value: Decimal(5), currency: .usd),
            rate: pinnedState.rate,
            mint: .testBondedMint,
            supplyQuarks: pinnedSupply
        )
        #expect(vm.computedExchangedFiat == expected)
    }

    @Test("Stream updates to the cache do not replace pinnedState")
    func streamUpdatesAreIgnored() async {
        let pinnedState = VerifiedState.makeForTest(
            rateTimestamp: Date(),
            reserveTimestamp: Date(),
            supplyFromBonding: 1_000_000
        )
        let ratesController = RatesController.makeForTest()
        let vm = GiveViewModel.makeForTest(
            pinnedState: pinnedState,
            ratesController: ratesController
        )

        await ratesController.verifiedProtoService.saveReserveStates([
            PublicKey.testBondedMint: .freshReserve(supplyFromBonding: 2_000_000)
        ])
        try? await Task.sleep(nanoseconds: 100_000_000)

        #expect(vm.pinnedState == pinnedState)
    }

    @Test("canSubmit is false when the pinned state has aged past clientMaxAge")
    func canSubmit_falseWhenStale() {
        let stalePinned = VerifiedState.makeForTest(
            rateTimestamp: Date().addingTimeInterval(-VerifiedState.clientMaxAge - 1),
            reserveTimestamp: Date().addingTimeInterval(-VerifiedState.clientMaxAge - 1),
            supplyFromBonding: 1
        )
        let vm = GiveViewModel.makeForTest(pinnedState: stalePinned)
        vm.updateAmount("5.00")
        #expect(vm.canSubmit == false)
    }

    @Test("canSubmit is true when the amount is valid and the pin is fresh")
    func canSubmit_trueWhenFreshAndValid() {
        let pinned = VerifiedState.makeForTest(
            rateTimestamp: Date(),
            reserveTimestamp: Date(),
            supplyFromBonding: 1
        )
        let vm = GiveViewModel.makeForTest(pinnedState: pinned)
        vm.updateAmount("5.00")
        #expect(vm.canSubmit == true)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -scheme Flipcash -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FlipcashTests/GiveViewModelPinningTests 2>&1 | tail -30
```

- [ ] **Step 3: Update `GiveViewModel`**

`GiveViewModel.swift` currently reads `selectedBalance.stored.supplyFromBonding` (lines 50–66 per exploration). Change to:

```swift
@Observable
final class GiveViewModel {
    // Immutable after construction — never updated by the stream.
    let pinnedState: VerifiedState

    // Existing fields (selectedBalance, enteredAmount, session, etc.) stay.

    init(
        pinnedState: VerifiedState,
        selectedBalance: Balance,
        session: Session,
        owner: KeyPair
        // other existing deps
    ) {
        self.pinnedState = pinnedState
        // existing init continues
    }

    private func computeExchangedFiat(for entered: FiatAmount) -> ExchangedFiat? {
        if selectedBalance.mint != .usdf {
            guard let supplyQuarks = pinnedState.supplyFromBonding else { return nil }
            return ExchangedFiat.compute(
                fromEntered: entered,
                rate: pinnedState.rate,
                mint: selectedBalance.mint,
                supplyQuarks: supplyQuarks
            )
        }
        return ExchangedFiat.compute(
            fromEntered: entered,
            rate: pinnedState.rate,
            mint: selectedBalance.mint,
            supplyQuarks: nil
        )
    }

    /// Submit is allowed only when the entered amount is valid AND the pinned
    /// state is still within the server's freshness window. `isStale` is
    /// recomputed each access, so SwiftUI re-evaluates the button's enabled
    /// state while the user is typing (and, crucially, if the user lingers
    /// past 13 minutes without typing).
    var canSubmit: Bool {
        guard let computed = computedExchangedFiat else { return false }
        return computed.onChainAmount.quarks > 0
            && !pinnedState.isStale
            // plus whatever other conditions the screen already enforces
    }

    func submit() async throws {
        guard let amount = computedExchangedFiat, canSubmit else { return }
        do {
            try await session.buy(
                amount: amount,
                verifiedState: pinnedState,
                of: token,
                owner: owner
            )
        } catch Session.Error.verifiedStateStale {
            // Defense-in-depth: canSubmit should have caught this. If we somehow
            // got here with a stale pin (race between canSubmit evaluation and
            // submit), silently drop — surfacing an error would be a new UX
            // element. Log for observability.
            logger.warning("Submit reached Session with stale pinnedState", metadata: [
                "ageSeconds": "\(pinnedState.age)"
            ])
        }
    }
}
```

Remove the `// TODO: pin upstream (Task 11)` marker left at the Give call site in Task 9.

- [ ] **Step 4: Update the navigation point that opens Give**

Wherever the Give flow is opened (typically a `Button` on the home screen or an amount-summary screen), the handler synchronously reads a pin from `RatesController.currentPinnedState(for:mint:)` (Task 7) and only constructs `GiveViewModel` when a non-stale pin is available. If `currentPinnedState` returns `nil`, the handler silently does nothing — no alert, no error, no visual feedback. In practice this never triggers because the stream + DB warm-load keep the cache populated; this is defensive.

Example pattern (the exact wiring depends on the existing navigation in the app — find the current `GiveViewModel(...)` construction and adapt):

```swift
// In HomeViewModel, CurrencyDetailViewModel, or wherever Give is launched from:
func openGive(for balance: Balance) {
    Task { @MainActor in
        guard let pinnedState = await ratesController.currentPinnedState(
            for: ratesController.entryCurrency,
            mint: balance.mint
        ) else {
            logger.warning("Tried to open Give without a pinnedState", metadata: [
                "mint": "\(balance.mint.base58)"
            ])
            return
        }
        let vm = GiveViewModel(
            pinnedState: pinnedState,
            selectedBalance: balance,
            session: session,
            owner: owner
        )
        navigator.push(.give(vm))
    }
}
```

`GiveScreen` itself does **not** change its rendering logic. It continues to consume the existing VM exactly as today — just built with a pinned state. If the existing submit button was wired to some `isSubmitEnabled` boolean, replace that with `vm.canSubmit` (the rename captures the additional staleness condition without altering the button's look).

- [ ] **Step 5: Run tests to verify they pass**

```bash
xcodebuild test -scheme Flipcash -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FlipcashTests/GiveViewModelPinningTests 2>&1 | tail -20
```
Expected: all 4 tests pass.

Also confirm existing Session tests still pass:
```bash
xcodebuild test -scheme Flipcash -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FlipcashTests/SessionBuyVerifiedStateTests 2>&1 | tail -10
```

- [ ] **Step 6: Commit**

```bash
git add Flipcash/Core/Screens/Main/Give/GiveViewModel.swift \
        <home/navigation file where Give is launched> \
        FlipcashTests/GiveViewModelTests.swift \
        FlipcashTests/TestSupport/GiveViewModel+TestSupport.swift
git commit -m "feat(give): pin VerifiedState for the duration of the flow"
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
xcodebuild test -scheme Flipcash -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FlipcashTests/GiveViewModelPinningTests 2>&1 | tail -20
```
Expected: both tests pass.

Also run the Session tests to confirm no regression:
```bash
xcodebuild test -scheme Flipcash -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FlipcashTests/SessionBuyVerifiedStateTests 2>&1 | tail -10
```

- [ ] **Step 6: Commit**

```bash
git add Flipcash/Core/Screens/Main/Give/GiveViewModel.swift \
        Flipcash/Core/Screens/Main/Give/GiveScreen.swift \
        FlipcashTests/GiveViewModelTests.swift \
        FlipcashTests/TestSupport/GiveViewModel+TestSupport.swift
git commit -m "feat(give): pin VerifiedState for the duration of the flow"
```

---

## Task 13: Pin `VerifiedState` in `WithdrawViewModel`

Zero UX changes. Withdraw screen looks identical to today. The only new behavior: submit is gated on the pin being fresh.

**Files:**
- Modify: `Flipcash/Core/Screens/Main/Withdraw/WithdrawViewModel.swift`
- Modify: whichever view navigates into the Withdraw flow
- Create: `FlipcashTests/WithdrawViewModelTests.swift`
- Create: `FlipcashTests/TestSupport/WithdrawViewModel+TestSupport.swift`

Withdraw is USDF-only — no `reserveProto`, no supply math. The pinning pattern still applies: the `rate` is the thing that mustn't drift.

- [ ] **Step 1: Failing tests**

Create `FlipcashTests/WithdrawViewModelTests.swift`:

```swift
import Testing
import Foundation
@testable import Flipcash
@testable import FlipcashCore

@Suite("WithdrawViewModel pinning")
struct WithdrawViewModelPinningTests {

    @Test("Computed exchanged amount uses pinnedState.rate, not ratesController.cachedRates")
    func usesPinnedRate() {
        let pinnedRate = Rate(currency: .usd, fx: Decimal(1.0))
        let pinnedState = VerifiedState.makeForTest(
            rateTimestamp: Date(),
            reserveTimestamp: nil,
            rate: pinnedRate
        )
        let vm = WithdrawViewModel.makeForTest(
            pinnedState: pinnedState,
            selectedBalance: .testUsdfBalance
        )
        vm.updateAmount("5.00")
        #expect(vm.computedExchangedFiat?.rate == pinnedRate)
    }

    @Test("Stream updates to the cache do not replace pinnedState")
    func streamUpdatesAreIgnored() async {
        let pinnedState = VerifiedState.makeForTest(
            rateTimestamp: Date(),
            reserveTimestamp: nil,
            rate: Rate(currency: .usd, fx: Decimal(1.0))
        )
        let ratesController = RatesController.makeForTest()
        let vm = WithdrawViewModel.makeForTest(
            pinnedState: pinnedState,
            ratesController: ratesController
        )

        await ratesController.verifiedProtoService.saveRates([
            "USD": .freshRate(fx: Decimal(1.5))
        ])
        try? await Task.sleep(nanoseconds: 100_000_000)

        #expect(vm.pinnedState == pinnedState)
    }

    @Test("canSubmit is false when pinnedState is stale")
    func canSubmit_falseWhenStale() {
        let stalePinned = VerifiedState.makeForTest(
            rateTimestamp: Date().addingTimeInterval(-VerifiedState.clientMaxAge - 1),
            reserveTimestamp: nil
        )
        let vm = WithdrawViewModel.makeForTest(pinnedState: stalePinned)
        vm.updateAmount("5.00")
        #expect(vm.canSubmit == false)
    }

    @Test("Submit forwards pinnedState to Session.withdraw")
    func submitPassesState() async throws {
        let client = FakeFlipClient()
        let session = Session.makeForTest(client: client)
        let pinnedState = VerifiedState.makeForTest(
            rateTimestamp: Date(),
            reserveTimestamp: nil
        )
        let vm = WithdrawViewModel.makeForTest(
            pinnedState: pinnedState,
            session: session
        )
        vm.updateAmount("5.00")
        try await vm.submit()
        #expect(client.lastWithdrawCall?.verifiedState == pinnedState)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -scheme Flipcash -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FlipcashTests/WithdrawViewModelPinningTests 2>&1 | tail -30
```

- [ ] **Step 3: Update `WithdrawViewModel`**

`WithdrawViewModel.swift` currently reads `selectedBalance.stored.supplyFromBonding` (lines 50–62). Change:

```swift
@Observable
final class WithdrawViewModel {
    let pinnedState: VerifiedState  // immutable for this flow

    // existing fields (selectedBalance, destination, enteredAmount, session, etc.)

    init(
        pinnedState: VerifiedState,
        selectedBalance: Balance,
        destination: PublicKey,
        session: Session,
        owner: KeyPair
    ) {
        self.pinnedState = pinnedState
        // existing init continues
    }

    private func computeExchangedFiat(for entered: FiatAmount) -> ExchangedFiat? {
        ExchangedFiat.compute(
            fromEntered: entered,
            rate: pinnedState.rate,
            mint: selectedBalance.mint,
            supplyQuarks: pinnedState.supplyFromBonding  // nil for USDF
        )
    }

    var canSubmit: Bool {
        guard let computed = computedExchangedFiat else { return false }
        return computed.onChainAmount.quarks > 0
            && !pinnedState.isStale
            // plus whatever other conditions the screen already enforces
    }

    func submit() async throws {
        guard let amount = computedExchangedFiat, canSubmit else { return }
        do {
            try await session.withdraw(
                exchangedFiat: amount,
                verifiedState: pinnedState,
                mint: selectedBalance.mint,
                destination: destination,
                owner: owner
            )
        } catch Session.Error.verifiedStateStale {
            logger.warning("Submit reached Session.withdraw with stale pinnedState", metadata: [
                "ageSeconds": "\(pinnedState.age)"
            ])
        }
    }
}
```

Remove the `// TODO: pin upstream (Task 11)` markers at Withdraw call sites.

- [ ] **Step 4: Update the navigation point that opens Withdraw**

Same pattern as Task 12: the handler reads `ratesController.currentPinnedState`, constructs the VM only when a non-stale pin is available, silently does nothing otherwise. The Withdraw screen itself renders identically to today.

```swift
// In wherever Withdraw is launched from (HomeViewModel, WalletViewModel, etc.):
func openWithdraw(for balance: Balance, destination: PublicKey) {
    Task { @MainActor in
        guard let pinnedState = await ratesController.currentPinnedState(
            for: ratesController.entryCurrency,
            mint: balance.mint
        ) else {
            logger.warning("Tried to open Withdraw without a pinnedState", metadata: [
                "mint": "\(balance.mint.base58)"
            ])
            return
        }
        let vm = WithdrawViewModel(
            pinnedState: pinnedState,
            selectedBalance: balance,
            destination: destination,
            session: session,
            owner: owner
        )
        navigator.push(.withdraw(vm))
    }
}
```

If the Withdraw screen previously had an `isSubmitEnabled` (or equivalent) boolean wired to the submit button, point it at `vm.canSubmit`. No other visual changes.

- [ ] **Step 5: Run tests to verify they pass**

```bash
xcodebuild test -scheme Flipcash -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FlipcashTests/WithdrawViewModelPinningTests 2>&1 | tail -20
```
Expected: all 4 tests pass.

- [ ] **Step 6: Commit**

```bash
git add Flipcash/Core/Screens/Main/Withdraw/WithdrawViewModel.swift \
        <navigation file where Withdraw is launched> \
        FlipcashTests/WithdrawViewModelTests.swift \
        FlipcashTests/TestSupport/WithdrawViewModel+TestSupport.swift
git commit -m "feat(withdraw): pin VerifiedState for the duration of the flow"
```

---

## Task 14: Pin `VerifiedState` in `CurrencySellViewModel`

Zero UX changes. Sell sheet looks identical to today. Submit is gated on the pin being fresh.

**Files:**
- Modify: `Flipcash/Core/Screens/Currency/CurrencySellViewModel.swift`
- Modify: whichever view presents the Sell sheet (typically a Button on a currency detail screen)
- Create: `FlipcashTests/CurrencySellViewModelTests.swift`
- Create: `FlipcashTests/TestSupport/CurrencySellViewModel+TestSupport.swift`

Sell is bonded-only (user sells a bonded currency for USDF). The pin MUST carry a `reserveProto` — `currentPinnedState` returns `nil` if either the rate or the reserve is missing/stale, so the navigation gate handles it.

- [ ] **Step 1: Failing tests**

Create `FlipcashTests/CurrencySellViewModelTests.swift`:

```swift
import Testing
import Foundation
@testable import Flipcash
@testable import FlipcashCore

@Suite("CurrencySellViewModel pinning")
struct CurrencySellViewModelPinningTests {

    @Test("ExchangedFiat computes against pinned supply, not currencyMetadata supply")
    func usesPinnedSupply() {
        let pinnedSupply: UInt64 = 1_000_000
        let cachedMetadataSupply: UInt64 = 9_999_999
        let pinnedState = VerifiedState.makeForTest(
            rateTimestamp: Date(),
            reserveTimestamp: Date(),
            supplyFromBonding: pinnedSupply
        )
        let vm = CurrencySellViewModel.makeForTest(
            pinnedState: pinnedState,
            currencyMetadata: .testBondedMetadata(supplyFromBonding: cachedMetadataSupply)
        )
        vm.updateAmount("5.00")

        let expected = ExchangedFiat.compute(
            fromEntered: FiatAmount(value: Decimal(5), currency: .usd),
            rate: pinnedState.rate,
            mint: .testBondedMint,
            supplyQuarks: pinnedSupply
        )
        #expect(vm.computedExchangedFiat == expected)
    }

    @Test("Stream updates to the cache do not replace pinnedState")
    func streamUpdatesAreIgnored() async {
        let pinnedState = VerifiedState.makeForTest(
            rateTimestamp: Date(),
            reserveTimestamp: Date(),
            supplyFromBonding: 1_000_000
        )
        let ratesController = RatesController.makeForTest()
        let vm = CurrencySellViewModel.makeForTest(
            pinnedState: pinnedState,
            ratesController: ratesController
        )

        await ratesController.verifiedProtoService.saveReserveStates([
            PublicKey.testBondedMint: .freshReserve(supplyFromBonding: 2_000_000)
        ])
        try? await Task.sleep(nanoseconds: 100_000_000)

        #expect(vm.pinnedState == pinnedState)
    }

    @Test("canSubmit is false when pinnedState is stale")
    func canSubmit_falseWhenStale() {
        let stalePinned = VerifiedState.makeForTest(
            rateTimestamp: Date().addingTimeInterval(-VerifiedState.clientMaxAge - 1),
            reserveTimestamp: Date().addingTimeInterval(-VerifiedState.clientMaxAge - 1),
            supplyFromBonding: 1
        )
        let vm = CurrencySellViewModel.makeForTest(pinnedState: stalePinned)
        vm.updateAmount("5.00")
        #expect(vm.canSubmit == false)
    }

    @Test("Submit forwards pinnedState to Session.sell")
    func submitPassesState() async throws {
        let client = FakeFlipClient()
        let session = Session.makeForTest(client: client)
        let pinnedState = VerifiedState.makeForTest(
            rateTimestamp: Date(),
            reserveTimestamp: Date(),
            supplyFromBonding: 1_000_000
        )
        let vm = CurrencySellViewModel.makeForTest(
            pinnedState: pinnedState,
            session: session
        )
        vm.updateAmount("5.00")
        try await vm.submit()
        #expect(client.lastSellCall?.verifiedState == pinnedState)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -scheme Flipcash -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FlipcashTests/CurrencySellViewModelPinningTests 2>&1 | tail -30
```

- [ ] **Step 3: Update `CurrencySellViewModel`**

```swift
@Observable
final class CurrencySellViewModel {
    let pinnedState: VerifiedState

    // existing fields: currencyMetadata, enteredAmount, session, owner, etc.

    init(
        pinnedState: VerifiedState,
        currencyMetadata: CurrencyMetadata,
        session: Session,
        owner: KeyPair
    ) {
        self.pinnedState = pinnedState
        // existing init continues
    }

    private func computeExchangedFiat(for entered: FiatAmount) -> ExchangedFiat? {
        guard let supplyQuarks = pinnedState.supplyFromBonding else { return nil }
        return ExchangedFiat.compute(
            fromEntered: entered,
            rate: pinnedState.rate,
            mint: currencyMetadata.mint,
            supplyQuarks: supplyQuarks
        )
    }

    var canSubmit: Bool {
        guard let computed = computedExchangedFiat else { return false }
        return computed.onChainAmount.quarks > 0
            && !pinnedState.isStale
    }

    func submit() async throws {
        guard let amount = computedExchangedFiat, canSubmit else { return }
        do {
            try await session.sell(
                amount: amount,
                verifiedState: pinnedState,
                mint: currencyMetadata.mint,
                owner: owner
            )
        } catch Session.Error.verifiedStateStale {
            logger.warning("Submit reached Session.sell with stale pinnedState", metadata: [
                "ageSeconds": "\(pinnedState.age)"
            ])
        }
    }
}
```

- [ ] **Step 4: Update the screen that presents the Sell sheet**

Find the `.sheet { CurrencySellSheet(...) }` or equivalent presentation. The presenting view reads `ratesController.currentPinnedState` before setting the sheet binding; if nil, the binding isn't toggled (silent no-op) and the sheet doesn't appear. The Sell sheet's own rendering does not change — it receives a `CurrencySellViewModel` and draws it exactly as today.

```swift
// Typical pattern on a currency detail screen or similar:
struct CurrencyDetailScreen: View {
    @Environment(\.ratesController) private var ratesController
    @State private var presentedSellVM: CurrencySellViewModel?

    let currencyMetadata: CurrencyMetadata
    // other deps

    var body: some View {
        // ... existing body ...
        .sheet(item: $presentedSellVM) { vm in
            CurrencySellSheet(viewModel: vm)
        }
    }

    private func onSellTapped() {
        Task { @MainActor in
            guard let pinnedState = await ratesController.currentPinnedState(
                for: currencyMetadata.entryCurrency,
                mint: currencyMetadata.mint
            ) else {
                logger.warning("Sell tapped without a pinnedState", metadata: [
                    "mint": "\(currencyMetadata.mint.base58)"
                ])
                return
            }
            presentedSellVM = CurrencySellViewModel(
                pinnedState: pinnedState,
                currencyMetadata: currencyMetadata,
                session: session,
                owner: owner
            )
        }
    }
}
```

`CurrencySellViewModel` needs to conform to `Identifiable` for `.sheet(item:)` — if it doesn't already, add `public var id = UUID()` as a stored property. If the existing presentation uses `.sheet(isPresented:)` instead, the same principle applies: the handler constructs the VM first, then toggles the binding. If the VM can't be built, the binding stays false.

Make sure any submit button or equivalent action in `CurrencySellSheet` is wired to `vm.canSubmit` (rename existing boolean if needed). No other visual changes.

- [ ] **Step 5: Run tests to verify they pass**

```bash
xcodebuild test -scheme Flipcash -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FlipcashTests/CurrencySellViewModelPinningTests 2>&1 | tail -20
```
Expected: all 4 tests pass.

- [ ] **Step 6: Commit**

```bash
git add Flipcash/Core/Screens/Currency/CurrencySellViewModel.swift \
        <presenting view file> \
        FlipcashTests/CurrencySellViewModelTests.swift \
        FlipcashTests/TestSupport/CurrencySellViewModel+TestSupport.swift
git commit -m "feat(sell): pin VerifiedState for the duration of the flow"
```

---

## Task 15: Remove dead `Error.missingVerifiedState` case

**Files:**
- Modify: `Flipcash/Core/Session/Session.swift`
- Modify: anywhere that switches on `Session.Error`

After Tasks 9–11, no caller throws `missingVerifiedState` — it was the error surfaced when the internal `getVerifiedState()` returned `nil`, which no longer exists. Safe to remove.

- [ ] **Step 1: Verify no references remain**

Run:
```bash
grep -rn "missingVerifiedState" Flipcash FlipcashCore FlipcashTests
```
Expected: only the case declaration and (possibly) exhaustive `switch` arms handling it. If anything still throws it, STOP — there's still a path that fetches internally, fix it first.

- [ ] **Step 2: Remove**

Delete the enum case. Delete any `case .missingVerifiedState` branches in switches.

- [ ] **Step 3: Build**

```bash
xcodebuild build -scheme Flipcash -destination 'generic/platform=iOS' -quiet
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add Flipcash/Core/Session/Session.swift <any switch-sites touched>
git commit -m "refactor(session): remove dead missingVerifiedState error"
```

---

## Task 16: Verify `Session.sell` workaround is obsolete (decision point)

**Files:**
- Modify (possibly): `Flipcash/Core/Session/Session.swift`

Revisit the "on-chain amount exceeds balance" branch at `Session.swift:747-757`. Now that UI math and intent math share one `VerifiedState`, the ExchangedFiat produced by the ViewModel already fits the balance. The workaround should never fire.

- [ ] **Step 1: Add a temporary assertion-logger**

In the workaround branch, add:

```swift
logger.error("Sell workaround branch fired — investigate; pinning should have prevented this", metadata: [
    "currency": "\(amount.nativeAmount.currency.rawValue)",
    "mint": "\(mint.base58)",
    "enteredQuarks": "\(amount.onChainAmount.quarks)",
    "balanceQuarks": "\(balance.quarks)"
])
```

- [ ] **Step 2: Manual test — exercise Sell on a bonded currency**

On a TestFlight build (or local run), perform a sell against a freshly launched currency. Verify the logger does NOT fire.

- [ ] **Step 3: If confirmed unused, remove the workaround**

Delete the `if let balance = balance(for: mint), amount.onChainAmount.quarks > balance.quarks, mint != .usdf` branch and go straight to `submitIntent(amount, verifiedState: ...)`.

If it DOES fire, leave the workaround in place, keep the logger, and add a follow-up TODO with the investigation details.

- [ ] **Step 4: Commit**

```bash
git commit -m "refactor(session): remove obsolete sell balance-cap workaround"
# or, if left in:
git commit -m "chore(session): log when sell balance-cap workaround fires"
```

---

## Task 17: Regression test for the root cause

**Files:**
- Create: `FlipcashTests/Regressions/Regression_native_amount_mismatch.swift`

- [ ] **Step 1: Write the tests**

```swift
import Testing
import Foundation
@testable import Flipcash
@testable import FlipcashCore

@Suite("Regression: native amount mismatch — pinning prevents drift between UI and intent")
struct Regression_native_amount_mismatch {

    @Test("Scenario A: stream delivers a newer state mid-flow; UI and intent still agree")
    func scenarioA_streamUpdateIgnoredMidFlow() async throws {
        let pinned = VerifiedState.makeForTest(
            rateTimestamp: Date(),
            reserveTimestamp: Date(),
            supplyFromBonding: 1_000_000
        )
        let ratesController = RatesController.makeForTest()
        let client = FakeFlipClient()
        let session = Session.makeForTest(client: client, ratesController: ratesController)

        let vm = GiveViewModel.makeForTest(
            pinnedState: pinned,
            selectedBalance: .testBondedBalance(supplyFromBonding: 1_000_000),
            session: session
        )
        vm.updateAmount("5.00")
        let uiAmount = vm.computedExchangedFiat

        // Stream delivers a newer reserve state with a different supply. Under the
        // old code, the intent would carry this newer state while the UI math used
        // the old one — exactly the bug we're regressing.
        await ratesController.verifiedProtoService.saveReserveStates([
            PublicKey.testBondedMint: .freshReserve(supplyFromBonding: 2_000_000)
        ])
        try await Task.sleep(nanoseconds: 50_000_000)

        // User submits. With pinning, the intent carries the pinned state and
        // the UI amount is consistent with it — server won't reject.
        try await vm.submit()
        #expect(client.lastBuyCall?.verifiedState == pinned)
        #expect(client.lastBuyCall?.amount == uiAmount)
    }

    @Test("Scenario B: a stale cached pin cannot be used to construct a ViewModel")
    func scenarioB_stalePinBlocksOpeningFlow() async throws {
        let ratesController = RatesController.makeForTest()
        // Simulate what warm-load / a prior session would leave in the cache:
        // protos whose server timestamps are already past clientMaxAge.
        let staleTimestamp = Date().addingTimeInterval(-VerifiedState.clientMaxAge - 60)
        await ratesController.verifiedProtoService.saveRates([
            "USD": .rate(withServerTimestamp: staleTimestamp)
        ])
        await ratesController.verifiedProtoService.saveReserveStates([
            PublicKey.testBondedMint: .reserve(
                supplyFromBonding: 1,
                serverTimestamp: staleTimestamp
            )
        ])

        // Navigation handler probes the cache. Stale → nil → silent no-op.
        // No UX shown, no error surfaced; the user simply doesn't enter the flow.
        let pin = await ratesController.currentPinnedState(for: .usd, mint: .testBondedMint)
        #expect(pin == nil)
    }

    @Test("Scenario C: once the pin ages past clientMaxAge while the screen is open, canSubmit becomes false")
    func scenarioC_pinAgesOutMidFlow_disablesSubmit() {
        // Pin that's exactly at the threshold — isStale true.
        let agedOut = VerifiedState.makeForTest(
            rateTimestamp: Date().addingTimeInterval(-VerifiedState.clientMaxAge - 1),
            reserveTimestamp: Date().addingTimeInterval(-VerifiedState.clientMaxAge - 1),
            supplyFromBonding: 1
        )
        let vm = GiveViewModel.makeForTest(pinnedState: agedOut)
        vm.updateAmount("5.00")
        #expect(vm.canSubmit == false)
    }
}
```

`.serializedDataOrEmpty()` is a small `try?`-wrapped helper in `FlipcashTests/TestSupport/` — if the proto fixtures make serialization trivial, inline `try! proto.serializedData()` is acceptable; just keep the test readable.

- [ ] **Step 2: Run tests to verify they pass**

```bash
xcodebuild test -scheme Flipcash -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FlipcashTests/Regression_native_amount_mismatch 2>&1 | tail -20
```
Expected: both tests pass.

- [ ] **Step 3: Commit**

```bash
git add FlipcashTests/Regressions/Regression_native_amount_mismatch.swift
git commit -m "test: regression coverage for native amount mismatch pinning"
```

---

## Task 18: Full test sweep + manual verification

**Files:** none

- [ ] **Step 1: Run every test file this plan touched**

```bash
xcodebuild test -scheme Flipcash -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:FlipcashTests/VerifiedStateTests \
  -only-testing:FlipcashTests/DatabaseVerifiedProtosTests \
  -only-testing:FlipcashTests/VerifiedProtoServiceTests \
  -only-testing:FlipcashTests/RatesControllerCurrentPinnedStateTests \
  -only-testing:FlipcashTests/SessionBuyVerifiedStateTests \
  -only-testing:FlipcashTests/SessionSellVerifiedStateTests \
  -only-testing:FlipcashTests/SessionWithdrawVerifiedStateTests \
  -only-testing:FlipcashTests/GiveViewModelPinningTests \
  -only-testing:FlipcashTests/WithdrawViewModelPinningTests \
  -only-testing:FlipcashTests/CurrencySellViewModelPinningTests \
  -only-testing:FlipcashTests/Regression_native_amount_mismatch \
  2>&1 | tail -30
```
Expected: all pass. If anything fails, stop and fix before moving on.

- [ ] **Step 2: Clean build**

```bash
xcodebuild clean build -scheme Flipcash -destination 'generic/platform=iOS' -quiet
```
Expected: `BUILD SUCCEEDED` with no new warnings.

- [ ] **Step 3: Manual verification on simulator**

Hand this list to the user before requesting commits on the PR. The headline property to confirm: **every amount-entry screen looks and behaves exactly like it did before** — same layout, no new loading state, no new prompts. The only observable change is that submit is blocked in the stale/missing-pin case.

1. **Give → Buy a bonded currency**, enter an amount, submit. Should succeed. No "native amount does not match" error.
2. **Give → Send Link** (Send Cash path) against the same bonded currency. Should succeed.
3. **Withdraw USDF** to an external address. Should succeed.
4. **Sell a bonded currency** → USDF. Should succeed.
5. **Screen visual diff**: Give / Withdraw / Sell screens must be pixel-identical to the previous build. No new spinners, no new error cards, no layout shifts.
6. **Cold start, immediate Give**: kill the app, relaunch, tap Give. Screen opens immediately (DB warm-load populates the cache during init). No spinner.
7. **Long idle**: open Give, leave screen open for 20+ minutes, then try to submit. The submit button silently stops responding (disabled because `pinnedState.isStale`). Close and reopen Give — submit works again because a fresh pin was acquired at the new navigation.
8. **Checking logs**:
   - `"Tried to open Give/Withdraw/Sell without a pinnedState"` warnings should not fire in normal operation. If they do, it means the stream + DB warm-load failed to prime the cache.
   - `"Submit reached Session.* with stale pinnedState"` warnings should also be absent — their presence means the `canSubmit` guard has a race.
   - No `Sell workaround branch fired` logs (if Task 16 left the workaround in place).

- [ ] **Step 4: Summary commit (if anything changed in Step 3 manual testing)**

If manual testing surfaces small fixes, commit each under `fix(...)` with the scope (`give`, `withdraw`, `sell`, `session`). Otherwise nothing to commit.

---

## Task 19: Open the pull request

**Files:** none

- [ ] **Step 1: Ensure upstream is set and branch has everything**

```bash
git log --oneline origin/main..HEAD
```
Expected: the sequence of commits from Tasks 0 through 18.

- [ ] **Step 2: Push**

```bash
git push -u origin fix/verified-state-pinning
```

- [ ] **Step 3: Open the PR**

```bash
gh pr create --title "fix: pin VerifiedState across amount-entry flows" --body "$(cat <<'EOF'
## Summary
- Pin one VerifiedState per amount-entry flow so UI math and intent submission always use the same proof.
- Persist verified rate and reserve protos to SQLite so they survive cold start.
- Replace silent refresh with an explicit "Prices out of date — refresh" action when the pin ages past the 13-minute client cutoff.

## Test plan
- [ ] Give → buy a bonded currency succeeds without a native-amount error
- [ ] Give → send link succeeds
- [ ] Withdraw USDF to external address succeeds
- [ ] Sell a bonded currency → USDF succeeds
- [ ] Cold start Give shows a brief "Updating prices…" state then loads
- [ ] Long idle on Give surfaces the refresh prompt and recovers
EOF
)"
```

Per user preference, the PR body stays plain English, no code references, one test-plan item per line. No co-author lines, no Claude footer.

---

## Spec coverage check

Every design-doc requirement maps to at least one task:

- Two new SQLite tables → Task 2
- Row models → Task 2
- Database helpers → Task 3
- SQLiteVersion bump → Task 4
- `VerifiedProtoStore` abstraction → Task 5
- `VerifiedProtoService` persists + warm-loads → Task 6
- `serverTimestamp`, `clientMaxAge`, `isStale` on `VerifiedState` → Task 1
- `RatesController.currentPinnedState(for:mint:)` convenience → Task 7
- `Session.Error.verifiedStateStale` → Task 8
- `Session.buy/sell/withdraw` take pinned state + staleness re-check → Tasks 9, 10, 11
- Remove `Error.missingVerifiedState` → Task 15
- Verify `Session.sell` workaround → Task 16
- `GiveViewModel` / `WithdrawViewModel` / `CurrencySellViewModel` pin and never re-pin mid-flow → Tasks 12, 13, 14
- Navigation-time gate (silent no-op when `currentPinnedState` is nil) → Tasks 12, 13, 14
- `canSubmit` gates submit when pin ages out mid-flow → Tasks 12, 13, 14
- Regression tests covering pinning correctness, stale-gate, and cold-start → Task 17
- Manual verification checklist → Task 18

**Zero UX changes is a hard requirement** — the plan takes care of this by (a) moving the staleness/presence check to the navigation handler so screens never open without a valid pin, and (b) tying the submit button's existing enabled state to `canSubmit` (which now also considers `pinnedState.isStale`). No new loading states, phase enums, refresh prompts, or error cards are introduced on any amount-entry screen.

Open questions from the spec:

- "Age source: proof timestamp vs receive time" → resolved: Task 1 uses the proof's server-signed timestamp.
- "Re-pin UX for Give with a live bill" → `SendCashOperation` already owns its own freshness check (`SendCashOperation.swift:55, 197-200`); Task 18's manual test #2 verifies the bill flow still works.
