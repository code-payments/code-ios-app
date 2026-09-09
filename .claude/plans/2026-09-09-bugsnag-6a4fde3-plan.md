# One Database Per Owner (Bugsnag 6a4fde3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop `replaceConversationFeed` failing with `database is locked (code: 5)` when repeat logins in one process open several SQLite writers on the same owner store.

**Architecture:** A new `DatabaseStore` on `Container` opens one `Database` per owner and returns the cached instance on every later login, so all `SessionContainer`s for an owner share one writer `Connection`. As defence in depth, read-then-write transactions become `BEGIN IMMEDIATE` so the busy handler is consulted instead of an instant `SQLITE_BUSY`, and `busyTimeout` is corrected from ~33 minutes to the 2 seconds its comment promises. Two `debug` login logs are promoted to `info` so the still-unexplained five-login trigger shows up in future Bugsnag reports.

**Tech Stack:** Swift 6 (app target has `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`), SQLite.swift (`Connection`, `TransactionMode`), Swift Testing (`@Suite`, `@Test`, `.bug`), `./Scripts/test.sh` on the iPhone 17 simulator.

**Spec:** `.claude/plans/2026-09-09-bugsnag-6a4fde3.md` (the triage brief). Read it first.

**Not available in this environment:** the brief says to load `karpathy-guidelines` before writing code. That skill is not installed here (`Skill` returns "Unknown skill"). Follow the project's `.claude/docs/hard-rules.md` and `.claude/reflections/index.md` instead; the relevant reflection is 2026-07-11 (regression test at the wrong layer).

---

## File map

| File | Change | Responsibility |
|---|---|---|
| `FlipcashTests/Regressions/Regression_6a4fde33e96556123eb1f0ec.swift` | Create | Regression suite: contention at the crash layer, busy-timeout units, one `Database` per owner |
| `Flipcash/Core/Controllers/Database/DatabaseStore.swift` | Create | Per-owner `Database` cache; owns the open/version-check logic that today lives in `SessionAuthenticator.initializeDatabase` |
| `Flipcash/Core/Container.swift` | Modify | Hold `let databaseStore` beside the other process-lifetime units |
| `Flipcash/Core/Session/SessionAuthenticator.swift` | Modify | `createSessionContainer` asks the store; delete `initializeDatabase` / `createApplicationSupportIfNeeded`; promote two logs to `info` |
| `Flipcash/Core/Controllers/Database/Database.swift` | Modify | `busyTimeout = 2`; `Database.transaction` helper uses `.immediate` |
| `Flipcash/Core/Controllers/Database/Database+Conversations.swift` | Modify | `.immediate` on the two read-then-write transactions |

Nothing else changes. No schema change, so `SQLiteVersion` stays as is. No new SPM dependency, so `Package.resolved` is untouched.

Both `Flipcash/` and `FlipcashTests/` are `PBXFileSystemSynchronizedRootGroup`s (`Code.xcodeproj/project.pbxproj:136-137`), so new files under them join their targets without editing the project file.

## How the tests are run

`./Scripts/test.sh <Target>/<Suite>[/<Test>]` builds and runs on the iPhone 17 simulator. The suite identifier is the Swift type name, not the display string:

```bash
./Scripts/test.sh FlipcashTests/Regression_6a4fde3
```

A single test:

```bash
./Scripts/test.sh FlipcashTests/Regression_6a4fde3/replaceFeed_rivalWriterHoldsLock_waitsThenCommits
```

`xcodebuild` ends with `** TEST SUCCEEDED **` or `** TEST FAILED **`. Never run the full `AllTargets` plan; that is the user's job.

---

### Task 0: Branch

**Files:** none

- [x] **Step 1: Create the fix branch from the current HEAD**

The worktree sits on `claude/flipcash-ios-error-triage-7e50ad` at `8042ff9d`, which is `main`. The user's rules forbid `claude/`-prefixed branch names for the work itself.

```bash
git checkout -b fix/database-per-owner
```

Expected: `Switched to a new branch 'fix/database-per-owner'`

- [x] **Step 2: Confirm the tree is clean apart from the two plan files**

```bash
git status --short
```

Expected:

```
?? .claude/plans/2026-09-09-bugsnag-6a4fde3-plan.md
?? .claude/plans/2026-09-09-bugsnag-6a4fde3.md
```

- [x] **Step 3: Commit the triage brief and this plan**

```bash
git add .claude/plans/2026-09-09-bugsnag-6a4fde3.md .claude/plans/2026-09-09-bugsnag-6a4fde3-plan.md
git commit -m "docs(plans): triage brief and plan for Bugsnag 6a4fde3 database lock"
```

---

### Task 1: Regression test at the crash layer (red)

This test reproduces the production failure through `Database.replaceConversationFeed`, the exact call that threw in `ConversationController.persist(operation: "replace-feed")`. A second `Database` on the same file plays the role of the other `SessionContainer`s' writers.

Why it discriminates: on unfixed code the transaction is `BEGIN DEFERRED`. The `SELECT` at `Database+Conversations.swift:239` opens a read snapshot; the `DELETE` at `:242` then needs the write lock the rival holds, and SQLite returns `SQLITE_BUSY` **without invoking the busy handler** because the connection already has a read transaction open. So the call throws at t≈0 even though the rival releases the lock 200 ms later. After the fix the transaction is `BEGIN IMMEDIATE`, which takes the write lock first, so the busy handler waits, the rival commits at 200 ms, and the feed write goes through.

**Files:**
- Create: `FlipcashTests/Regressions/Regression_6a4fde33e96556123eb1f0ec.swift`

- [x] **Step 1: Write the failing test**

```swift
//
//  Regression_6a4fde33e96556123eb1f0ec.swift
//  FlipcashTests
//
//  "Failed to persist conversation state [replace-feed]" — database is locked (code: 5).
//  One cold launch ran completeLogin five times for the same owner; each built a
//  SessionContainer with its own Database, so four writer Connections shared one
//  SQLite file. replaceConversationFeed ran a DEFERRED transaction that read before
//  it wrote: once a rival writer held the lock, the snapshot upgrade returned
//  SQLITE_BUSY immediately, bypassing the busy handler.
//
//  Fix: Container.databaseStore hands out one Database per owner, so repeat logins
//  share a single writer; read-then-write transactions take the write lock up front
//  with BEGIN IMMEDIATE; busyTimeout is 2 seconds rather than 2000.
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("Regression: 6a4fde3 – replace-feed fails SQLITE_BUSY against a rival writer", .bug("6a4fde33e96556123eb1f0ec"))
struct Regression_6a4fde3 {

    private func conversation(_ byte: UInt8) -> Conversation {
        Conversation(id: .test(byte), members: [], lastMessage: nil, lastActivity: Date(timeIntervalSince1970: 100))
    }

    @Test("replace-feed waits for a rival writer to commit instead of failing the snapshot upgrade")
    func replaceFeed_rivalWriterHoldsLock_waitsThenCommits() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        // Seed a row so the second feed has something to delete — the read-then-write path.
        try database.replaceConversationFeed([conversation(1)], type: .contactDm)

        // A second Database on the same file is exactly what each extra SessionContainer opened.
        let rival = try Database(url: url)
        try rival.writer.run("BEGIN IMMEDIATE TRANSACTION")
        let release = Task.detached {
            try await Task.delay(milliseconds: 200)
            try rival.writer.run("COMMIT TRANSACTION")
        }

        try database.replaceConversationFeed([conversation(2)], type: .contactDm)
        try await release.value

        let ids = try database.getConversations().map(\.id)
        #expect(ids == [.test(2)])
    }
}
```

- [x] **Step 2: Run it and watch it fail at the crash layer**

```bash
./Scripts/test.sh FlipcashTests/Regression_6a4fde3/replaceFeed_rivalWriterHoldsLock_waitsThenCommits
```

Expected: `** TEST FAILED **`. The failure for `replaceFeed_rivalWriterHoldsLock_waitsThenCommits` must be a thrown error whose text contains `database is locked` and `(code: 5)`, the production signature. SQLite.swift includes the failing statement in the description when it has one, so the local text will read `database is locked (DELETE FROM "conversations" ...) (code: 5)` where production showed only `database is locked (code: 5)`; the shared part is what matters. If the test instead fails on the `#expect`, or passes, stop: the reproduction is not hitting the deferred-snapshot path and the test needs rethinking, not the fix.

- [x] **Step 3: Commit the red test**

```bash
git add FlipcashTests/Regressions/Regression_6a4fde33e96556123eb1f0ec.swift
git commit -m "test(database): reproduce replace-feed SQLITE_BUSY against a rival writer (6a4fde3)"
```

---

### Task 2: Immediate transactions for read-then-write paths (green)

**Files:**
- Modify: `Flipcash/Core/Controllers/Database/Database+Conversations.swift:230` and `:284`
- Modify: `Flipcash/Core/Controllers/Database/Database.swift:56`
- Test: `FlipcashTests/Regressions/Regression_6a4fde33e96556123eb1f0ec.swift`

Three sites read inside the transaction before writing: `replaceConversationFeed` (the `SELECT` of doomed ids), `persistMessages` (the `pluck` of the current cursor), and every caller of the `Database.transaction` helper (`Database+Balance.swift:158`, `:203`, `Database+Rates.swift:45`, `Database+VerifiedProtos.swift:21`, `:56` all read rows before upserting). The remaining `writer.transaction {` sites begin with a `DELETE` or `INSERT`, which takes the write lock as its first statement and so already consults the busy handler; leave them alone.

- [x] **Step 1: Make `replaceConversationFeed` immediate**

In `Database+Conversations.swift`, change line 230 from:

```swift
        try writer.transaction {
```

to:

```swift
        // IMMEDIATE: this transaction reads before it writes. A DEFERRED one that
        // reads first fails the write with SQLITE_BUSY at once when another writer
        // holds the lock, without consulting the busy handler.
        try writer.transaction(.immediate) {
```

- [x] **Step 2: Make `persistMessages` immediate**

In `Database+Conversations.swift`, change line 284 (inside `persistMessages`) from:

```swift
        try writer.transaction {
```

to:

```swift
        try writer.transaction(.immediate) {
```

- [x] **Step 3: Make the `Database.transaction` helper immediate**

In `Database.swift`, change line 56 from:

```swift
            try writer.transaction { [unowned self] in
```

to:

```swift
            try writer.transaction(.immediate) { [unowned self] in
```

- [x] **Step 4: Run the regression test and see it pass**

```bash
./Scripts/test.sh FlipcashTests/Regression_6a4fde3/replaceFeed_rivalWriterHoldsLock_waitsThenCommits
```

Expected: `** TEST SUCCEEDED **`. The test now takes a little over 200 ms because `BEGIN IMMEDIATE` waits for the rival's commit.

- [x] **Step 5: Run the existing database and conversation suites to catch a regression in the helper change**

```bash
./Scripts/test.sh FlipcashTests/DatabaseBalanceUpsertTests FlipcashTests/DatabaseLiveSupplyTests FlipcashTests/ConversationControllerTests
```

Those are the struct names at `FlipcashTests/Database/Database+BalanceUpsertTests.swift:12`, `FlipcashTests/Database/Database+LiveSupplyTests.swift:15`, and `FlipcashTests/ConversationControllerTests.swift:13`; the first two go through the `Database.transaction` helper.

Expected: `** TEST SUCCEEDED **`.

- [x] **Step 6: Commit**

```bash
git add Flipcash/Core/Controllers/Database/Database+Conversations.swift Flipcash/Core/Controllers/Database/Database.swift
git commit -m "fix(database): take the write lock up front in read-then-write transactions"
```

---

### Task 3: Busy timeout in seconds (red, then green)

`Connection.busyTimeout` is a `Double` in **seconds** (SQLite.swift `Connection.swift:415-419` multiplies by 1 000 before calling `sqlite3_busy_timeout`). `Database.init` sets `2000` with the comment `// 2 sec`, which arms a ~33 minute wait.

**Files:**
- Modify: `Flipcash/Core/Controllers/Database/Database.swift:36` and `:42`
- Test: `FlipcashTests/Regressions/Regression_6a4fde33e96556123eb1f0ec.swift`

- [x] **Step 1: Add the failing test**

Append inside `struct Regression_6a4fde3`, after `replaceFeed_rivalWriterHoldsLock_waitsThenCommits`:

```swift
    @Test("busy timeout is two seconds, not two thousand")
    func busyTimeout_isTwoSeconds() throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }

        // SQLite.swift's busyTimeout is in seconds; 2000 arms a ~33 minute wait.
        #expect(database.writer.busyTimeout == 2)
        #expect(database.reader.busyTimeout == 2)
    }
```

- [x] **Step 2: Run it and see it fail**

```bash
./Scripts/test.sh FlipcashTests/Regression_6a4fde3/busyTimeout_isTwoSeconds
```

Expected: `** TEST FAILED **` with `Expectation failed: (database.writer.busyTimeout → 2000.0) == 2`.

- [x] **Step 3: Fix the two assignments**

In `Database.swift`, replace lines 36 and 42:

```swift
        writer.busyTimeout = 2000 // 2 sec
```

becomes

```swift
        writer.busyTimeout = 2 // seconds
```

and

```swift
        reader.busyTimeout = 2000 // 2 Sec
```

becomes

```swift
        reader.busyTimeout = 2 // seconds
```

- [x] **Step 4: Run the whole regression suite and see it pass**

```bash
./Scripts/test.sh FlipcashTests/Regression_6a4fde3
```

Expected: `** TEST SUCCEEDED **`, two tests passing.

- [x] **Step 5: Commit**

```bash
git add Flipcash/Core/Controllers/Database/Database.swift FlipcashTests/Regressions/Regression_6a4fde33e96556123eb1f0ec.swift
git commit -m "fix(database): busy timeout is in seconds, arm 2s not 33min"
```

---

### Task 4: `DatabaseStore`, one `Database` per owner (red, then green)

This is the root-cause fix. The identity test is written against `DatabaseStore` rather than `SessionAuthenticator.completeLogin` because `completeLogin` builds a full `SessionContainer` whose `HistoryController.sync()` and `PushController` hit the live network from a unit test. Task 5 is the wiring that makes `completeLogin` go through the store, and its verification step greps that the store is the only remaining `Database` constructor call in the app target.

**Files:**
- Create: `Flipcash/Core/Controllers/Database/DatabaseStore.swift`
- Test: `FlipcashTests/Regressions/Regression_6a4fde33e96556123eb1f0ec.swift`

- [x] **Step 1: Add the failing tests**

Append inside `struct Regression_6a4fde3`, after `busyTimeout_isTwoSeconds`:

```swift
    /// `DatabaseStore` writes to the real Application Support directory, so each test
    /// uses a throwaway owner and removes that owner's store and version file after.
    private func withThrowawayOwner(_ body: (PublicKey) throws -> Void) throws {
        let owner = KeyPair.generate()!.publicKey
        defer {
            try? Database.deleteStore(owner: owner)
            try? FileManager.default.removeItem(at: .versionFile(owner: owner))
        }
        try body(owner)
    }

    @Test("one owner gets the same Database on every login")
    func databaseStore_sameOwnerTwice_returnsOneInstance() throws {
        try withThrowawayOwner { owner in
            let store = DatabaseStore()

            let first = try store.database(for: owner)
            let second = try store.database(for: owner)

            #expect(first === second)
        }
    }

    @Test("different owners get different Databases")
    func databaseStore_twoOwners_returnsDistinctInstances() throws {
        try withThrowawayOwner { alice in
            try withThrowawayOwner { bob in
                let store = DatabaseStore()

                let aliceDatabase = try store.database(for: alice)
                let bobDatabase = try store.database(for: bob)

                #expect(aliceDatabase !== bobDatabase)
            }
        }
    }
```

- [x] **Step 2: Run the suite and see it fail to compile**

```bash
./Scripts/test.sh FlipcashTests/Regression_6a4fde3
```

Expected: `** TEST FAILED **` (build failure) with `cannot find 'DatabaseStore' in scope`. This is the expected red state: the type does not exist yet.

- [x] **Step 3: Create `DatabaseStore`**

Create `Flipcash/Core/Controllers/Database/DatabaseStore.swift`. The body of `database(for:)` is `SessionAuthenticator.initializeDatabase` (`SessionAuthenticator.swift:295-310`) and `createApplicationSupportIfNeeded` (`:312-319`) moved verbatim, with the cache lookup in front.

```swift
//
//  DatabaseStore.swift
//  Flipcash
//

import Foundation
import FlipcashCore

private let logger = Logger(label: "flipcash.database-store")

/// Opens one `Database` per owner and returns that same instance on every later request,
/// so repeat logins in one process share a single SQLite writer instead of contending for the file.
final class DatabaseStore {

    private var databases: [PublicKey: Database] = [:]

    /// The owner's `Database`, opened (and rebuilt if its on-disk version is outdated) on first use.
    func database(for owner: PublicKey) throws -> Database {
        if let database = databases[owner] {
            return database
        }

        try createApplicationSupportIfNeeded()

        // Currently we don't do migrations so every time
        // the user version is outdated, we'll rebuild the
        // database during sync.
        let userVersion = (try? Database.userVersion(owner: owner)) ?? 0
        let currentVersion = try InfoPlist.value(for: "SQLiteVersion").integer()
        if currentVersion > userVersion {
            try Database.deleteStore(owner: owner)
            logger.error("Outdated user version, deleted database.")
            try Database.setUserVersion(version: currentVersion, owner: owner)
        }

        let database = try Database(url: .dataStore(owner: owner))
        databases[owner] = database
        return database
    }

    private func createApplicationSupportIfNeeded() throws {
        if !FileManager.default.fileExists(atPath: URL.applicationSupportDirectory.path) {
            try FileManager.default.createDirectory(
                at: .applicationSupportDirectory,
                withIntermediateDirectories: false
            )
        }
    }
}
```

Notes for the implementer:
- `DatabaseStore` is `@MainActor` by the app target's default isolation, the same as `Container` and `SessionAuthenticator.createSessionContainer`, so the dictionary needs no lock.
- `PublicKey` is already used as a dictionary key elsewhere (`TokenCardStack.swift:83`), so it is `Hashable`.
- There is deliberately no `close()` or eviction. SQLite.swift's `Connection` closes only in `deinit`, and `HistoryController.sync()` (`HistoryController.swift:105`) holds the database in a `Task` with no `[weak self]`, so an explicit close would race in-flight work. A cached `Database` lives for the process; the cost is two open connections per owner ever logged in.

- [x] **Step 4: Run the suite and see it pass**

```bash
./Scripts/test.sh FlipcashTests/Regression_6a4fde3
```

Expected: `** TEST SUCCEEDED **`, four tests passing.

- [x] **Step 5: Commit**

```bash
git add Flipcash/Core/Controllers/Database/DatabaseStore.swift FlipcashTests/Regressions/Regression_6a4fde33e96556123eb1f0ec.swift
git commit -m "feat(database): DatabaseStore caches one Database per owner"
```

---

### Task 5: Wire the store through `Container` and `SessionAuthenticator`

**Files:**
- Modify: `Flipcash/Core/Container.swift:16-21`, `:35-40`
- Modify: `Flipcash/Core/Session/SessionAuthenticator.swift:226`, `:293-319`

- [x] **Step 1: Hold the store on `Container`**

In `Container.swift`, add a property after `let notificationController: NotificationController` (line 21):

```swift
    let notificationController: NotificationController
    let databaseStore: DatabaseStore
```

and initialise it in `init()` after `self.notificationController = NotificationController()` (line 40):

```swift
        self.notificationController = NotificationController()
        self.databaseStore          = DatabaseStore()
```

- [x] **Step 2: Ask the store in `createSessionContainer`**

In `SessionAuthenticator.swift`, change line 226 from:

```swift
        let database = try! initializeDatabase(owner: ownerPublicKey)
```

to:

```swift
        let database = try! container.databaseStore.database(for: ownerPublicKey)
```

- [x] **Step 3: Delete the moved code**

In `SessionAuthenticator.swift`, delete lines 293 to 320 in full, that is the `// MARK: - Database -` header, `initializeDatabase(owner:)`, and `createApplicationSupportIfNeeded()`:

```swift
    // MARK: - Database -
    
    private func initializeDatabase(owner: PublicKey) throws -> Database {
        try createApplicationSupportIfNeeded()
        
        // Currently we don't do migrations so every time
        // the user version is outdated, we'll rebuild the
        // database during sync.
        let userVersion = (try? Database.userVersion(owner: owner)) ?? 0
        let currentVersion = try InfoPlist.value(for: "SQLiteVersion").integer()
        if currentVersion > userVersion {
            try Database.deleteStore(owner: owner)
            logger.error("Outdated user version, deleted database.")
            try Database.setUserVersion(version: currentVersion, owner: owner)
        }
        
        return try Database(url: .dataStore(owner: owner))
    }
    
    private func createApplicationSupportIfNeeded() throws {
        if !FileManager.default.fileExists(atPath: URL.applicationSupportDirectory.path) {
            try FileManager.default.createDirectory(
                at: .applicationSupportDirectory,
                withIntermediateDirectories: false
            )
        }
    }
    
```

Leave the `// MARK: - Login -` header that follows in place.

- [x] **Step 4: Verify the store is now the only `Database` constructor in the app target**

```bash
grep -rn "Database(url" Flipcash --include=*.swift
```

Expected, exactly one line:

```
Flipcash/Core/Controllers/Database/DatabaseStore.swift:37:        let database = try Database(url: .dataStore(owner: owner))
```

(The line number may differ by one or two; the file must be the only match.)

- [x] **Step 5: Build the app**

```bash
./Scripts/build.sh
```

Expected: `** BUILD SUCCEEDED **`.

- [x] **Step 6: Run the regression suite plus the suites that construct a `Container`**

```bash
./Scripts/test.sh FlipcashTests/Regression_6a4fde3 FlipcashTests/DeepLinkControllerTests
```

`DeepLinkControllerTests.swift:16` builds `SessionAuthenticator(container: Container())`, so it exercises the new `Container.init` path.

Expected: `** TEST SUCCEEDED **`.

- [x] **Step 7: Commit**

```bash
git add Flipcash/Core/Container.swift Flipcash/Core/Session/SessionAuthenticator.swift
git commit -m "fix(session): share one Database per owner across repeat logins (6a4fde3)"
```

---

### Task 6: Promote the two login logs to `info`

Release builds bootstrap logging at `.info` (`FlipcashCore/Sources/FlipcashCore/Logging/LogStore.swift:34-38`), so the `debug` lines that would have shown *why* one launch ran `completeLogin` five times never reached the Bugsnag report. This task has no test: it changes a log level and adds metadata, with no behaviour to assert.

**Files:**
- Modify: `Flipcash/Core/Session/SessionAuthenticator.swift:128`, `:387`

- [x] **Step 1: Log each `initializeState` attempt at `info` with its retry count**

Change line 128 from:

```swift
        logger.debug("initializeState called")
```

to:

```swift
        logger.info("initializeState called", metadata: ["count": "\(count)"])
```

- [x] **Step 2: Log `completeLogin` at `info`**

Change line 387 from:

```swift
        logger.debug("completeLogin", metadata: ["owner": "\(initializedAccount.keyAccount.ownerPublicKey)"])
```

to:

```swift
        logger.info("completeLogin", metadata: ["owner": "\(initializedAccount.keyAccount.ownerPublicKey)"])
```

- [x] **Step 3: Build**

```bash
./Scripts/build.sh
```

Expected: `** BUILD SUCCEEDED **`.

- [x] **Step 4: Commit**

```bash
git add Flipcash/Core/Session/SessionAuthenticator.swift
git commit -m "chore(session): log login attempts at info so release reports show the count"
```

---

### Task 7: Final check and handoff

**Files:** none

- [x] **Step 1: Run the regression suite one last time on the finished branch**

```bash
./Scripts/test.sh FlipcashTests/Regression_6a4fde3
```

Expected: `** TEST SUCCEEDED **`, four tests.

- [x] **Step 2: Review the branch diff**

```bash
git diff main...HEAD --stat
```

Expected files, and only these:

```
 .claude/plans/2026-09-09-bugsnag-6a4fde3-plan.md
 .claude/plans/2026-09-09-bugsnag-6a4fde3.md
 Flipcash/Core/Container.swift
 Flipcash/Core/Controllers/Database/Database+Conversations.swift
 Flipcash/Core/Controllers/Database/Database.swift
 Flipcash/Core/Controllers/Database/DatabaseStore.swift
 Flipcash/Core/Session/SessionAuthenticator.swift
 FlipcashTests/Regressions/Regression_6a4fde33e96556123eb1f0ec.swift
```

- [x] **Step 3: Report to the user, do not open a PR**

Report in chat: the four regression tests, the fact that the crash-layer test was observed failing with `database is locked (code: 5)` before Task 2, and the two things this branch does **not** do:

1. It does not explain the five `completeLogin` calls on one launch. Task 6 makes the next occurrence show the attempt count in Bugsnag.
2. It does not stop a stale `SessionContainer`'s in-flight writes. `logout()` (`SessionAuthenticator.swift:440-460`) still never stops `historyController`, and `completeLogin` never tears down the previous container. With one shared `Database` those writes now land on the live store, which is the pre-existing defect made visible rather than a new one.

Ask the user to run the full `AllTargets` plan before a PR. If they want the PR opened, use `gh pr create --assignee @me` with a conventional-commit title (`fix(database): share one Database per owner across repeat logins`) and a body written with the `chrisbanes-skills:grounded-writing` skill, no attribution footer, no "Verification" section.

---

## Self-review

**Spec coverage** against the brief's Proposed direction and Verification sections:

| Brief item | Task |
|---|---|
| One `Database` per owner keyed on `Container`, `initializeDatabase` returns the cached instance | 4, 5 |
| No explicit `close()`; ARC teardown | 4 (note in Step 3) |
| `busyTimeout = 2` | 3 |
| `.immediate` for read-then-write transactions | 2 |
| Promote the two `debug` lines to `info` | 6 |
| Regression file at `FlipcashTests/Regressions/Regression_6a4fde33e96556123eb1f0ec.swift` on `Database.makeTemp()` | 1 |
| Force contention with a held `BEGIN IMMEDIATE`, observe `SQLITE_BUSY` on unfixed code | 1 Step 2 |
| Post-fix identity assertion (`===`) across two logins for one owner | 4 |
| Risk: stale container writes land on the live store | 7 Step 3 |

One deviation from the brief: it suggested dropping the loser's `busyTimeout` to `0.05` and asserting the throw. That test would stay red after the fix too (an immediate transaction still times out if the rival never releases), so Task 1 instead has the rival release after 200 ms, which is red on deferred and green on immediate.

**Placeholder scan:** every code step shows the full code; every run step names the command and the expected terminal line. The one "may differ" allowance is a line number in a grep result in Task 5 Step 4, and the file-only requirement there is exact.

**Type consistency:** `DatabaseStore.database(for:)` is the name used in Task 4's tests, Task 4's implementation, and Task 5's call site. `Container.databaseStore` is the property name in Task 5 Steps 1 and 2. `Database.makeTemp()` / `Database.removeTemp(at:)` match `FlipcashTests/TestSupport/Database+TestSupport.swift:14,21`. `Task.delay(milliseconds:)` exists at `FlipcashCore/Sources/FlipcashCore/Extensions/Task+Delay.swift:16`. `ConversationID.test(_:)` is at `FlipcashTests/TestSupport/Conversation+TestSupport.swift:11`. `Database.getConversations()` is at `Database+Conversations.swift:53`. `URL.versionFile(owner:)` is at `Database.swift:135`. `KeyPair.generate()` returns an optional (`KeyPair.swift:33`), hence the force unwrap in the test helper.

---

## Execution notes (2026-09-09)

- `./Scripts/test.sh <Target>/<Suite>/<testName>` selected 0 tests and still printed `** TEST SUCCEEDED **`; every run used the suite form `FlipcashTests/Regression_6a4fde3`.
- Red run on unfixed code failed in 0.009 s with `Caught error: database is locked (code: 5)` — the deferred snapshot upgrade returns SQLITE_BUSY without waiting. Green after `.immediate` took 0.26 s (the rival's 200 ms hold).
- `#expect(try a !== b)` does not compile ("errors thrown from here are not handled"); the two lookups are hoisted into locals.
- The build's `gengoogle` phase rewrites `Flipcash/Supporting Files/GoogleService-Info.plist`; it is on the pre-commit blocklist and was never staged.
