# Analytics: Received Events (iOS) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring iOS to parity with the Android half of `docs/superpowers/specs/2026-08-21-analytics-received-events-design.md` — receive-side people counters, `Tip Received` / `Message Received` events, `Origin` on `Sent Tip`, display-name set/updated events, and a `Token Symbol` alongside every mint.

**Architecture:** Event and property *definitions* go in `Flipcash/Utilities/Events.swift`; anything touching the Mixpanel transport (`people.increment`, the mint→symbol resolver hook, the central enrichment) goes in `Flipcash/Utilities/Analytics.swift`, because `Analytics.isEnabled` is `private` and therefore file-scoped. The receive-side decision logic lands in a new `ConversationReceiptReporter` — a `@MainActor final class` with injectable closures — owned by `ConversationController` as a single `let`, so the rules are unit-testable without the Mixpanel transport (which is hard-disabled in tests).

**Tech Stack:** Swift 6.1 / SwiftUI / SPM, Swift Testing (`@Suite` / `@Test` / `#expect`), SQLite.swift, Mixpanel-swift. The app target builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so top-level types are implicitly main-actor isolated; closure *parameters* still need an explicit `@MainActor`.

---

## Deliberate deviations from the spec's iOS notes

Record these in the PR description too:

1. **Instrument B fires from `ConversationController.markRead`, not `ConversationStore.advanceSelfReadPointer`.** The store lives in `FlipcashCore`, which is deliberately free of controller/network dependencies and cannot reference the app target's `Analytics` enum.
2. **Instrument A's watermark is the pre-write `Database.newestMessageID(conversationID:)`, not a new `analyticsCountedThrough` column.** iOS has no migration framework — the hard rule is "bump `SQLiteVersion` in Info.plist on every schema change (no migrations; DB is rebuilt from server)", so adding a column would delete every user's local cache. `newestMessageID` read *before* the write gives the same monotonic-max semantics for free.
3. **A `.catchUp` delivery into an empty conversation seeds only and counts nothing.** After a `SQLiteVersion` bump the DB is empty, and a `GetDelta` with `afterSequence = 0` replays the whole event log; counting that would inflate an unreversible people property. A `.live` delivery with no watermark still counts, so a brand-new single-message tip DM — the headline case — is not lost.

## Build & test commands

- Build: `./Scripts/build.sh`
- Targeted tests: `./Scripts/test.sh <Target>/<Suite>[/<TestName>]`
- **Never** run `swift test` inside a package directory, and **never** run the full `AllTargets` plan — that is the user's job.

## File structure

**Create:**
- `Flipcash/Core/Controllers/ConversationReceiptReporter.swift` — the receive-side decision unit (which messages count, which event they emit, USD normalisation).
- `FlipcashTests/TestSupport/ReceiptSpy.swift` — records what the reporter would have sent.
- `FlipcashTests/Analytics/TokenSymbolEnrichmentTests.swift`
- `FlipcashTests/Analytics/ReceivedEventsTests.swift`
- `FlipcashTests/Chat/ConversationReceiptReporterTests.swift`
- `FlipcashTests/Chat/ConversationReceiptWiringTests.swift`

**Modify:**
- `Flipcash/Utilities/Analytics.swift` — mint→symbol resolver hook, central enrichment in `track`, `people.increment` transport.
- `Flipcash/Utilities/Events.swift` — `Property.tokenSymbol` / `.paymentTokenSymbol`, `ConversationEvent.tipReceived` / `.messageReceived`, `DisplayNameEvent`, `DisplayNameSource`, `ReceivedCounter`, `TipOrigin.analyticsValue`, `origin:` on `transfer`.
- `Flipcash/Core/Session/SessionAuthenticator.swift` — install the symbol resolver in `completeLogin`; wire `usdRate` in `SessionContainer.init`.
- `Flipcash/Core/Screens/Send/SendAmountViewModel.swift` — pass the tip origin.
- `Flipcash/Core/Screens/Onboarding/OnboardingNameViewModel.swift` — emit `Display Name Set`.
- `Flipcash/Core/Screens/Main/Profile/ProfileNameScreen.swift` — emit set-or-updated with the right `Source`.
- `Flipcash/Core/Controllers/Database/Database+Conversations.swift` — the `(after, through]` range query.
- `Flipcash/Core/Controllers/ConversationController.swift` — own the reporter; hook `persist(event:)`, `catchUp`, `markRead`.
- `FlipcashTests/Database/Database+ConversationsTests.swift` — a case for the new range query.

No `Code.xcodeproj/project.pbxproj` edit is needed: `Flipcash`, `FlipcashTests`, `FlipcashUITests`, and `NotificationService` are `PBXFileSystemSynchronizedRootGroup`s, so new `.swift` files are picked up automatically.

---

### Task 1: Token Symbol alongside every mint

Every event that already carries `Mint` gains `Token Symbol`; `Payment Mint` gains `Payment Token Symbol`. Resolution happens centrally in `track`, via a settable static hook installed at session start — no call site changes. An unresolvable mint **omits** the property rather than sending an empty string.

**Files:**
- Modify: `Flipcash/Utilities/Events.swift` (the `Property` enum, ~line 397)
- Modify: `Flipcash/Utilities/Analytics.swift`
- Test: `FlipcashTests/Analytics/TokenSymbolEnrichmentTests.swift`

- [ ] **Step 1: Add the two properties**

In `Flipcash/Utilities/Events.swift`, inside `extension Analytics { enum Property: String {`, add the two cases immediately after `case paymentMint`:

```swift
        case mint              = "Mint"
        case paymentMint       = "Payment Mint"
        case tokenSymbol       = "Token Symbol"
        case paymentTokenSymbol = "Payment Token Symbol"
```

- [ ] **Step 2: Write the failing test**

Create `FlipcashTests/Analytics/TokenSymbolEnrichmentTests.swift`:

```swift
//
//  TokenSymbolEnrichmentTests.swift
//  FlipcashTests
//

import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("Token symbol enrichment")
struct TokenSymbolEnrichmentTests {

    @Test("Property names are the shared contract")
    func propertyNames() {
        #expect(Analytics.Property.tokenSymbol.rawValue == "Token Symbol")
        #expect(Analytics.Property.paymentTokenSymbol.rawValue == "Payment Token Symbol")
    }

    @Test("A resolvable Mint gains Token Symbol")
    func mintGainsSymbol() {
        let properties: [Analytics.Property: AnalyticsValue] = [.mint: "SomeMint"]
        let enriched = Analytics.withTokenSymbols(properties) { _ in "FLIP" }
        #expect(enriched[.tokenSymbol] as? String == "FLIP")
    }

    @Test("A resolvable Payment Mint gains Payment Token Symbol")
    func paymentMintGainsSymbol() {
        let properties: [Analytics.Property: AnalyticsValue] = [.paymentMint: "SomeMint"]
        let enriched = Analytics.withTokenSymbols(properties) { _ in "USDF" }
        #expect(enriched[.paymentTokenSymbol] as? String == "USDF")
    }

    @Test("Both mints resolve independently")
    func bothMintsResolve() {
        let properties: [Analytics.Property: AnalyticsValue] = [
            .mint: "target",
            .paymentMint: "payment",
        ]
        let enriched = Analytics.withTokenSymbols(properties) { base58 in
            base58 == "target" ? "FLIP" : "USDF"
        }
        #expect(enriched[.tokenSymbol] as? String == "FLIP")
        #expect(enriched[.paymentTokenSymbol] as? String == "USDF")
    }

    @Test("An unresolvable mint omits the symbol entirely")
    func unresolvedMintOmitsSymbol() {
        let properties: [Analytics.Property: AnalyticsValue] = [.mint: "SomeMint"]
        let enriched = Analytics.withTokenSymbols(properties) { _ in nil }
        #expect(enriched[.tokenSymbol] == nil)
        #expect(enriched.count == properties.count)
    }

    @Test("Properties without a mint pass through untouched")
    func noMintPassesThrough() {
        let properties: [Analytics.Property: AnalyticsValue] = [.state: "Success"]
        let enriched = Analytics.withTokenSymbols(properties) { _ in "FLIP" }
        #expect(enriched[.tokenSymbol] == nil)
        #expect(enriched[.paymentTokenSymbol] == nil)
        #expect(enriched.count == 1)
    }
}
```

- [ ] **Step 3: Run it to confirm it fails**

```bash
./Scripts/test.sh FlipcashTests/TokenSymbolEnrichmentTests
```

Expected: a compile failure — `withTokenSymbols` does not exist.

- [ ] **Step 4: Implement the resolver hook, the pure enrichment, and apply it in `track`**

In `Flipcash/Utilities/Analytics.swift`, replace the whole `enum Analytics { … }` block (lines 25–56) with:

```swift
enum Analytics {

    private static var isEnabled = false

    /// Resolves a mint's base58 address to its ticker symbol. Installed once at
    /// session start (see `SessionAuthenticator.completeLogin`) so no call site has
    /// to look a symbol up; nil before login, and nil per-mint when the mint isn't
    /// cached locally — in which case the symbol property is omitted, never blank.
    static var tokenSymbolResolver: (@MainActor (String) -> String?)?

    static func initialize() {
        let apiKey = try? InfoPlist.value(for: "mixpanel").value(for: "apiKey").string()
        if let apiKey {
            logger.info("Initializing Mixpanel")
            Mixpanel.initialize(token: apiKey, trackAutomaticEvents: true)
            isEnabled = true
        } else {
            logger.error("Failed to initialize Mixpanel. No API key found in Info.plist")
        }
    }

    static func track(event: some AnalyticsEvent, properties: [Property: AnalyticsValue]? = nil, error: Error? = nil) {
        guard isEnabled else { return }

        var container: [String: AnalyticsValue] = [:]

        let resolved: [Property: AnalyticsValue]
        if let properties, let tokenSymbolResolver {
            resolved = withTokenSymbols(properties, resolve: tokenSymbolResolver)
        } else {
            resolved = properties ?? [:]
        }

        resolved.forEach { key, value in
            container[key.rawValue] = value
        }

        if let error {
            let swiftError = error as NSError
            container["Error"] = "\(swiftError.domain).\(error):\(swiftError.code)"
        }

        mixpanel.track(event: event.eventName, properties: container)
    }

    /// Pairs every mint-valued property with the symbol property that shadows it.
    private static let mintProperties: [(mint: Property, symbol: Property)] = [
        (.mint, .tokenSymbol),
        (.paymentMint, .paymentTokenSymbol),
    ]

    /// Adds the ticker symbol beside each mint `properties` carries. An unresolvable
    /// mint leaves its symbol property absent — an empty or placeholder value would
    /// be indistinguishable from a real symbol in a Mixpanel breakdown.
    static func withTokenSymbols(
        _ properties: [Property: AnalyticsValue],
        resolve: (String) -> String?
    ) -> [Property: AnalyticsValue] {
        var enriched = properties
        for pair in mintProperties {
            guard let base58 = properties[pair.mint] as? String,
                  let symbol = resolve(base58) else { continue }
            enriched[pair.symbol] = symbol
        }
        return enriched
    }
}
```

- [ ] **Step 5: Run the test to verify it passes**

```bash
./Scripts/test.sh FlipcashTests/TokenSymbolEnrichmentTests
```

Expected: PASS, 6 tests.

- [ ] **Step 6: Commit**

```bash
git add Flipcash/Utilities/Analytics.swift Flipcash/Utilities/Events.swift FlipcashTests/Analytics/TokenSymbolEnrichmentTests.swift && git commit -m "feat(analytics): report token symbol alongside every mint"
```

---

### Task 2: Install the symbol resolver at session start

**Files:**
- Modify: `Flipcash/Core/Session/SessionAuthenticator.swift:386-400`

- [ ] **Step 1: Install the resolver beside `setIdentity`**

In `completeLogin(with:)`, replace:

```swift
        Analytics.setIdentity(initializedAccount.userID)
```

with:

```swift
        Analytics.setIdentity(initializedAccount.userID)

        // Mint metadata lives in the session's local cache, so the symbol lookup can
        // only be wired once a session exists. Weak: the resolver outlives a logout,
        // and a stale session must not be kept alive by an analytics closure.
        let sessionModel = session.session
        Analytics.tokenSymbolResolver = { [weak sessionModel] base58 in
            guard let mint = try? PublicKey(base58: base58) else { return nil }
            return sessionModel?.storedMintMetadata(for: mint)?.symbol
        }
```

- [ ] **Step 2: Build**

```bash
./Scripts/build.sh
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add Flipcash/Core/Session/SessionAuthenticator.swift && git commit -m "feat(analytics): resolve token symbols from the session mint cache"
```

---

### Task 3: `Origin` on `Sent Tip`

A tip sent from the money button inside a tip chat is currently indistinguishable from the first tip off a tip card. `SendTarget.tip(TipRecipient)` already carries the `TipOrigin` the server is told about; report the same value.

**Files:**
- Modify: `Flipcash/Utilities/Events.swift`
- Modify: `Flipcash/Core/Screens/Send/SendAmountViewModel.swift:198-216`
- Test: `FlipcashTests/Analytics/ReceivedEventsTests.swift` (created here, extended in Task 6)

- [ ] **Step 1: Write the failing test**

Create `FlipcashTests/Analytics/ReceivedEventsTests.swift`:

```swift
//
//  ReceivedEventsTests.swift
//  FlipcashTests
//

import Testing
import FlipcashCore
@testable import Flipcash

@Suite("Received & origin event contract")
struct ReceivedEventsTests {

    @Test("Tip origin property values are shared verbatim with Android")
    func tipOriginValues() {
        #expect(TipOrigin.tipcard.analyticsValue == "Tipcard")
        #expect(TipOrigin.chat.analyticsValue == "Chat")
    }
}
```

- [ ] **Step 2: Run it to confirm it fails**

```bash
./Scripts/test.sh FlipcashTests/ReceivedEventsTests
```

Expected: compile failure — `analyticsValue` is not a member of `TipOrigin`.

- [ ] **Step 3: Add `TipOrigin.analyticsValue` and the `origin:` parameter**

In `Flipcash/Utilities/Events.swift`, add below the existing `extension DepositMethod` (~line 285):

```swift
extension TipOrigin {
    /// The `Origin` property value, shared verbatim with Android.
    var analyticsValue: String {
        switch self {
        case .tipcard: "Tipcard"
        case .chat:    "Chat"
        }
    }
}
```

Then change the `transfer(event:exchangedFiat:grabTime:successful:error:)` overload (~line 191) to:

```swift
    /// `origin` applies to `Sent Tip` only: which surface the tip came from —
    /// a scanned/opened tip card, or the money button inside an existing tip chat.
    static func transfer(event: TransferEvent, exchangedFiat: ExchangedFiat?, grabTime: Double?, successful: Bool, error: Error?, origin: TipOrigin? = nil) {
        var properties: [Property: AnalyticsValue] = exchangedFiat.map(amountProperties) ?? [:]
        properties[.state] = successful ? String.success : String.failure

        if let grabTime {
            properties[.grabTime] = grabTime
        }

        if let origin {
            properties[.origin] = origin.analyticsValue
        }

        track(
            event: event,
            properties: properties,
            error: error
        )
    }
```

Add the property case to the `Property` enum, after `case source`:

```swift
        case origin            = "Origin"
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
./Scripts/test.sh FlipcashTests/ReceivedEventsTests
```

Expected: PASS.

- [ ] **Step 5: Pass the origin from the send call site**

In `Flipcash/Core/Screens/Send/SendAmountViewModel.swift`, replace the block starting `let transferEvent: Analytics.TransferEvent = …` through the end of the `do/catch` (lines 198–216) with:

```swift
            // A payment into a tip DM reports as a tip; a contact DM is a plain
            // cash send. This covers both the scanned-tipcard flow and the
            // Send Cash action inside a tip thread, since both submit here —
            // `Origin` is what tells the two apart.
            let tipOrigin: TipOrigin? = if case .tip(let recipient) = target { recipient.origin } else { nil }
            let transferEvent: Analytics.TransferEvent = tipOrigin == nil ? .sentCash : .sentTip

            do {
                try await sender.send(
                    amount: amountToSend,
                    verifiedState: pinnedState,
                    to: recipient,
                    chat: chatPaymentMetadata()
                )
                Analytics.transfer(event: transferEvent, exchangedFiat: amountToSend, grabTime: nil, successful: true, error: nil, origin: tipOrigin)
                return .success
            } catch {
                Analytics.transfer(event: transferEvent, exchangedFiat: amountToSend, grabTime: nil, successful: false, error: error, origin: tipOrigin)
                showSendError()
                return .failed
            }
```

- [ ] **Step 6: Build**

```bash
./Scripts/build.sh
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 7: Commit**

```bash
git add Flipcash/Utilities/Events.swift Flipcash/Core/Screens/Send/SendAmountViewModel.swift FlipcashTests/Analytics/ReceivedEventsTests.swift && git commit -m "feat(analytics): tag Sent Tip with its origin"
```

---

### Task 4: Display Name Set / Updated

Two events, both carrying `Source`. Set-vs-updated is decided by whether a prior name existed — **not** by which screen the user came from — so someone who skips the onboarding step and names themselves from the tip card still gets `Display Name Set`.

**Files:**
- Modify: `Flipcash/Utilities/Events.swift`
- Modify: `Flipcash/Core/Screens/Onboarding/OnboardingNameViewModel.swift:62-64`
- Modify: `Flipcash/Core/Screens/Main/Profile/ProfileNameScreen.swift:96-122`
- Test: `FlipcashTests/Analytics/ReceivedEventsTests.swift`

- [ ] **Step 1: Write the failing test**

Append these tests inside `ReceivedEventsTests` in `FlipcashTests/Analytics/ReceivedEventsTests.swift`:

```swift
    @Test("Display name event names are the shared contract")
    func displayNameEventNames() {
        #expect(Analytics.DisplayNameEvent.set.eventName == "Display Name Set")
        #expect(Analytics.DisplayNameEvent.updated.eventName == "Display Name Updated")
    }

    @Test("Display name sources are shared verbatim with Android")
    func displayNameSourceValues() {
        #expect(Analytics.DisplayNameSource.onboarding.analyticsValue == "Onboarding")
        #expect(Analytics.DisplayNameSource.myAccount.analyticsValue == "My Account")
        #expect(Analytics.DisplayNameSource.tipCardSetup.analyticsValue == "Tip Card Setup")
    }

    @Test("A first name is Set, a replacement is Updated", arguments: [
        (false, Analytics.DisplayNameEvent.set),
        (true, Analytics.DisplayNameEvent.updated),
    ])
    func setVersusUpdated(_ hadPreviousName: Bool, _ expected: Analytics.DisplayNameEvent) {
        #expect(Analytics.displayNameEvent(hadPreviousName: hadPreviousName) == expected)
    }
```

- [ ] **Step 2: Run it to confirm it fails**

```bash
./Scripts/test.sh FlipcashTests/ReceivedEventsTests
```

Expected: compile failure — `DisplayNameEvent` does not exist.

- [ ] **Step 3: Define the events, the source, and the emitter**

In `Flipcash/Utilities/Events.swift`, add to the domain-event enums (after `enum ConversationEvent`, ~line 63):

```swift
    /// The display name a user is known by. `Set` is a first name, `Updated` a
    /// replacement — decided by whether a name already existed, not by the screen.
    enum DisplayNameEvent: String, AnalyticsEvent {
        case set     = "Display Name Set"
        case updated = "Display Name Updated"
    }

    /// The surface a display-name submission came from.
    enum DisplayNameSource {
        case onboarding
        case myAccount
        case tipCardSetup
    }
```

Add, in the `// MARK: - Conversation -` neighbourhood (a new `// MARK: - Display Name -` section just above it):

```swift
// MARK: - Display Name -

extension Analytics {
    /// Which of the two display-name events a submission is. Split out from
    /// `displayNameSubmitted` so the rule is testable without the transport.
    static func displayNameEvent(hadPreviousName: Bool) -> DisplayNameEvent {
        hadPreviousName ? .updated : .set
    }

    /// A successful `SetDisplayName`. `hadPreviousName` is read *before* the RPC —
    /// after it, every submission looks like a replacement.
    static func displayNameSubmitted(source: DisplayNameSource, hadPreviousName: Bool) {
        track(
            event: displayNameEvent(hadPreviousName: hadPreviousName),
            properties: [.source: source.analyticsValue]
        )
    }
}

extension Analytics.DisplayNameSource {
    /// The `Source` property value, shared verbatim with Android.
    var analyticsValue: String {
        switch self {
        case .onboarding:   "Onboarding"
        case .myAccount:    "My Account"
        case .tipCardSetup: "Tip Card Setup"
        }
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
./Scripts/test.sh FlipcashTests/ReceivedEventsTests
```

Expected: PASS.

- [ ] **Step 5: Emit from the onboarding step**

In `Flipcash/Core/Screens/Onboarding/OnboardingNameViewModel.swift`, replace:

```swift
                try await flipClient.setDisplayName(name, owner: owner)
                onComplete?()
```

with:

```swift
                try await flipClient.setDisplayName(name, owner: owner)
                // Onboarding runs pre-login against a brand-new account, so there is
                // never a prior name here — this is always a first set.
                Analytics.displayNameSubmitted(source: .onboarding, hadPreviousName: false)
                onComplete?()
```

- [ ] **Step 6: Emit from the profile-name screen**

In `Flipcash/Core/Screens/Main/Profile/ProfileNameScreen.swift`, replace the head of `submit()` — from `guard let name = …` down to and including `guard !Task.isCancelled else { return }` — with:

```swift
    private func submit() {
        guard let name = state.validatedDisplayName, !isSubmitting else { return }

        // Read before the RPC: `updateProfile()` below installs the new name, after
        // which every submission would look like a replacement.
        let hadPreviousName = !(sessionContainer.session.profile?.displayName ?? "").isEmpty
        let source: Analytics.DisplayNameSource = switch completion {
        case .tipcard: .tipCardSetup
        case .back:    .myAccount
        }

        submitTask = Task {
            defer { submitTask = nil }

            do {
                try await container.flipClient.setDisplayName(
                    name,
                    owner: sessionContainer.session.ownerKeyPair
                )
                Analytics.displayNameSubmitted(source: source, hadPreviousName: hadPreviousName)
                try await sessionContainer.session.updateProfile()

                guard !Task.isCancelled else { return }
```

Leave the rest of the method — the `switch completion` navigation and the three catch arms — unchanged.

- [ ] **Step 7: Build**

```bash
./Scripts/build.sh
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 8: Commit**

```bash
git add Flipcash/Utilities/Events.swift Flipcash/Core/Screens/Onboarding/OnboardingNameViewModel.swift Flipcash/Core/Screens/Main/Profile/ProfileNameScreen.swift FlipcashTests/Analytics/ReceivedEventsTests.swift && git commit -m "feat(analytics): distinguish display name set from updated"
```

---

### Task 5: The crossed-window database query

Instrument B reports one event per inbound message the read pointer just crossed — the half-open interval `(previousPointer, latestID]`. No such query exists yet.

**Files:**
- Modify: `Flipcash/Core/Controllers/Database/Database+Conversations.swift` (after `messages(conversationID:from:)`, ~line 168)
- Test: `FlipcashTests/Database/Database+ConversationsTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `DatabaseConversationsTests` in `FlipcashTests/Database/Database+ConversationsTests.swift`:

```swift
    @Test("The crossed window is the half-open interval (after, through]")
    func crossedWindowIsHalfOpen() throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let id = ConversationID.test(1)

        try database.upsertConversationMessages(
            [textMessage(id: 1, at: 10), textMessage(id: 2, at: 20), textMessage(id: 3, at: 30), textMessage(id: 4, at: 40)],
            conversationID: id
        )

        let crossed = try database.messages(conversationID: id, after: MessageID(value: 2), through: MessageID(value: 3))
        #expect(crossed.map(\.id.value) == [3])
    }

    @Test("A nil lower bound means the whole history up to the pointer")
    func crossedWindowWithNoLowerBound() throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let id = ConversationID.test(1)

        try database.upsertConversationMessages(
            [textMessage(id: 1, at: 10), textMessage(id: 2, at: 20), textMessage(id: 3, at: 30)],
            conversationID: id
        )

        let crossed = try database.messages(conversationID: id, after: nil, through: MessageID(value: 2))
        #expect(crossed.map(\.id.value) == [1, 2])
    }
```

- [ ] **Step 2: Run it to confirm it fails**

```bash
./Scripts/test.sh FlipcashTests/DatabaseConversationsTests
```

Expected: compile failure — no `messages(conversationID:after:through:)`.

- [ ] **Step 3: Add the query**

In `Flipcash/Core/Controllers/Database/Database+Conversations.swift`, directly below `messages(conversationID:from:)`:

```swift
    /// Every message in the half-open id interval `(after, through]`, oldest-first — the window a
    /// read-pointer advance just crossed. A nil `after` means the pointer had never been set, so the
    /// whole stored history up to `through` counts as newly read. Index-backed by the composite
    /// `(conversationId, id)` primary key.
    func messages(conversationID: ConversationID, after: MessageID?, through: MessageID) throws -> [ConversationMessage] {
        let m = ConversationMessageTable()
        var query = m.table.filter(m.conversationId == conversationID.data && m.id <= through.value)
        if let after {
            query = query.filter(m.id > after.value)
        }
        let rows = try reader.prepareRowIterator(query.order(m.id.asc))
        return try rows.map { conversationMessage(from: $0) }.compactMap { $0 }
    }
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
./Scripts/test.sh FlipcashTests/DatabaseConversationsTests
```

Expected: PASS (all cases in the suite).

- [ ] **Step 5: Commit**

```bash
git add Flipcash/Core/Controllers/Database/Database+Conversations.swift FlipcashTests/Database/Database+ConversationsTests.swift && git commit -m "feat(chat): query the message window a read pointer crossed"
```

---

### Task 6: Counter transport and the two received events

**Files:**
- Modify: `Flipcash/Utilities/Analytics.swift`
- Modify: `Flipcash/Utilities/Events.swift`
- Test: `FlipcashTests/Analytics/ReceivedEventsTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `ReceivedEventsTests`:

```swift
    @Test("Received event names are the shared contract")
    func receivedEventNames() {
        #expect(Analytics.ConversationEvent.tipReceived.eventName == "Tip Received")
        #expect(Analytics.ConversationEvent.messageReceived.eventName == "Message Received")
    }

    @Test("Received counter names are the shared contract")
    func receivedCounterNames() {
        #expect(Analytics.ReceivedCounter.tips.rawValue == "Tips Received")
        #expect(Analytics.ReceivedCounter.tipsValue.rawValue == "Tips Received Value")
        #expect(Analytics.ReceivedCounter.messages.rawValue == "Messages Received")
    }
```

- [ ] **Step 2: Run it to confirm it fails**

```bash
./Scripts/test.sh FlipcashTests/ReceivedEventsTests
```

Expected: compile failure — `tipReceived` / `ReceivedCounter` do not exist.

- [ ] **Step 3: Add the counter enum and the `people.increment` transport**

In `Flipcash/Utilities/Analytics.swift`, add a new section directly above `// MARK: - Private -`:

```swift
// MARK: - People counters -

extension Analytics {
    /// Cumulative per-user counters, stored as Mixpanel *people* properties.
    ///
    /// A people property carries no event identity and cannot be decremented, so a
    /// replayed increment inflates the profile permanently and unattributably. Every
    /// caller must therefore sit behind a watermark — see `ConversationReceiptReporter`.
    enum ReceivedCounter: String {
        case tips      = "Tips Received"
        case tipsValue = "Tips Received Value"
        case messages  = "Messages Received"
    }

    static func increment(_ counter: ReceivedCounter, by amount: Double = 1) {
        guard isEnabled else { return }
        mixpanel.people.increment(property: counter.rawValue, by: amount)
    }
}
```

(This must live in `Analytics.swift`: `isEnabled` is `private`, i.e. file-scoped.)

- [ ] **Step 4: Add the two events**

In `Flipcash/Utilities/Events.swift`, extend `ConversationEvent`:

```swift
    enum ConversationEvent: String, AnalyticsEvent {
        case sentMessage     = "Sent Message"
        case tipReceived     = "Tip Received"
        case messageReceived = "Message Received"
    }
```

and add the two emitters to the existing `// MARK: - Conversation -` extension, below `sentMessage`:

```swift
    /// An inbound tipped Cash message the user has now read. Mutually exclusive with
    /// `messageReceived` — a tip reports only as a tip.
    static func tipReceived(chatType: ConversationType?, exchangedFiat: ExchangedFiat) {
        var properties = amountProperties(exchangedFiat)
        properties[.chatType] = chatType.analyticsValue
        track(event: ConversationEvent.tipReceived, properties: properties)
    }

    /// An inbound non-tip message the user has now read.
    static func messageReceived(chatType: ConversationType?) {
        track(event: ConversationEvent.messageReceived, properties: [.chatType: chatType.analyticsValue])
    }
```

- [ ] **Step 5: Run the test to verify it passes**

```bash
./Scripts/test.sh FlipcashTests/ReceivedEventsTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Flipcash/Utilities/Analytics.swift Flipcash/Utilities/Events.swift FlipcashTests/Analytics/ReceivedEventsTests.swift && git commit -m "feat(analytics): add received counters and received chat events"
```

---

### Task 7: `ConversationReceiptReporter`

The decision unit: which delivered messages count, what a read-pointer advance emits, and how a foreign-currency tip becomes a USD number. Injectable closures so the rules are testable with the transport off.

**Files:**
- Create: `Flipcash/Core/Controllers/ConversationReceiptReporter.swift`
- Create: `FlipcashTests/TestSupport/ReceiptSpy.swift`
- Test: `FlipcashTests/Chat/ConversationReceiptReporterTests.swift`

- [ ] **Step 1: Write the spy**

Create `FlipcashTests/TestSupport/ReceiptSpy.swift`:

```swift
//
//  ReceiptSpy.swift
//  FlipcashTests
//

import Foundation
import FlipcashCore
@testable import Flipcash

/// Records everything a `ConversationReceiptReporter` would have sent to Mixpanel.
/// The real transport is inert in tests (`Analytics.isEnabled` is false), so the
/// reporter's closures are the only observable seam.
@MainActor
final class ReceiptSpy {

    var counters: [(counter: Analytics.ReceivedCounter, amount: Double)] = []
    var tips: [(chatType: ConversationType?, exchangedFiat: ExchangedFiat)] = []
    var messages: [ConversationType?] = []

    /// Rates the reporter will find when normalising a tip to USD.
    var rates: [CurrencyCode: Rate] = [:]

    func amount(for counter: Analytics.ReceivedCounter) -> Double {
        counters.filter { $0.counter == counter }.reduce(0) { $0 + $1.amount }
    }

    func count(of counter: Analytics.ReceivedCounter) -> Int {
        counters.count { $0.counter == counter }
    }

    func makeReporter(selfUserID: UserID) -> ConversationReceiptReporter {
        let reporter = ConversationReceiptReporter(
            selfUserID: selfUserID,
            increment: { [self] counter, amount in counters.append((counter, amount)) },
            trackTipReceived: { [self] chatType, exchangedFiat in tips.append((chatType, exchangedFiat)) },
            trackMessageReceived: { [self] chatType in messages.append(chatType) }
        )
        reporter.usdRate = { [self] currency in rates[currency] }
        return reporter
    }
}
```

- [ ] **Step 2: Write the failing tests**

Create `FlipcashTests/Chat/ConversationReceiptReporterTests.swift`:

```swift
//
//  ConversationReceiptReporterTests.swift
//  FlipcashTests
//

import Testing
import Foundation
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("ConversationReceiptReporter")
struct ConversationReceiptReporterTests {

    private let me: UserID = UUID()
    private let them: UserID = UUID()

    // MARK: - Fixtures

    private func exchangedFiat(_ value: Decimal, _ currency: CurrencyCode, fx: Decimal = 1) -> ExchangedFiat {
        ExchangedFiat(
            onChainAmount: TokenAmount(quarks: 1_000_000, mint: .usdf),
            nativeAmount: FiatAmount(value: value, currency: currency),
            currencyRate: Rate(fx: fx, currency: currency)
        )
    }

    private func text(id: UInt64, from sender: UserID?) -> ConversationMessage {
        ConversationMessage(
            id: MessageID(value: id),
            senderID: sender,
            content: .text("hi"),
            date: Date(timeIntervalSince1970: TimeInterval(id)),
            unreadSeq: id
        )
    }

    private func tip(id: UInt64, from sender: UserID?, _ value: Decimal = 5, _ currency: CurrencyCode = .usd, fx: Decimal = 1) -> ConversationMessage {
        ConversationMessage(
            id: MessageID(value: id),
            senderID: sender,
            content: .cash(exchangedFiat(value, currency, fx: fx)),
            cashAction: .tipped,
            date: Date(timeIntervalSince1970: TimeInterval(id)),
            unreadSeq: id
        )
    }

    private func cash(id: UInt64, from sender: UserID?) -> ConversationMessage {
        ConversationMessage(
            id: MessageID(value: id),
            senderID: sender,
            content: .cash(exchangedFiat(5, .usd)),
            cashAction: .sent,
            date: Date(timeIntervalSince1970: TimeInterval(id)),
            unreadSeq: id
        )
    }

    // MARK: - Counters (instrument A)

    @Test("An inbound text counts as one message and no tip")
    func inboundTextCountsAsMessage() {
        let spy = ReceiptSpy()
        let reporter = spy.makeReporter(selfUserID: me)

        reporter.countReceived([text(id: 1, from: them)], countedThrough: nil, delivery: .live)

        #expect(spy.count(of: .messages) == 1)
        #expect(spy.count(of: .tips) == 0)
        #expect(spy.count(of: .tipsValue) == 0)
    }

    @Test("An inbound tip counts as both a tip and a message")
    func inboundTipCountsBoth() {
        let spy = ReceiptSpy()
        let reporter = spy.makeReporter(selfUserID: me)

        reporter.countReceived([tip(id: 1, from: them, 5)], countedThrough: nil, delivery: .live)

        #expect(spy.count(of: .messages) == 1)
        #expect(spy.count(of: .tips) == 1)
        #expect(spy.amount(for: .tipsValue) == 5)
    }

    @Test("A non-tip cash message is a message, not a tip")
    func inboundCashIsNotATip() {
        let spy = ReceiptSpy()
        let reporter = spy.makeReporter(selfUserID: me)

        reporter.countReceived([cash(id: 1, from: them)], countedThrough: nil, delivery: .live)

        #expect(spy.count(of: .messages) == 1)
        #expect(spy.count(of: .tips) == 0)
    }

    @Test("Own messages are never counted")
    func outboundIsNotCounted() {
        let spy = ReceiptSpy()
        let reporter = spy.makeReporter(selfUserID: me)

        reporter.countReceived([text(id: 1, from: me), tip(id: 2, from: me)], countedThrough: nil, delivery: .live)

        #expect(spy.counters.isEmpty)
    }

    @Test("Messages at or below the watermark are not re-counted")
    func watermarkSuppressesReplay() {
        let spy = ReceiptSpy()
        let reporter = spy.makeReporter(selfUserID: me)

        reporter.countReceived(
            [text(id: 1, from: them), text(id: 2, from: them), text(id: 3, from: them)],
            countedThrough: MessageID(value: 2),
            delivery: .live
        )

        #expect(spy.count(of: .messages) == 1)
    }

    @Test("A cold catch-up seeds without counting")
    func coldCatchUpDoesNotCount() {
        let spy = ReceiptSpy()
        let reporter = spy.makeReporter(selfUserID: me)

        reporter.countReceived([text(id: 1, from: them), tip(id: 2, from: them)], countedThrough: nil, delivery: .catchUp)

        #expect(spy.counters.isEmpty)
    }

    @Test("A live delivery into an empty conversation still counts")
    func liveDeliveryWithNoWatermarkCounts() {
        let spy = ReceiptSpy()
        let reporter = spy.makeReporter(selfUserID: me)

        reporter.countReceived([tip(id: 1, from: them, 3)], countedThrough: nil, delivery: .live)

        #expect(spy.count(of: .tips) == 1)
        #expect(spy.amount(for: .tipsValue) == 3)
    }

    @Test("A foreign-currency tip is normalised to USD")
    func foreignTipNormalisesToUSD() {
        let spy = ReceiptSpy()
        spy.rates = [.eur: Rate(fx: 2, currency: .eur)]
        let reporter = spy.makeReporter(selfUserID: me)

        reporter.countReceived([tip(id: 1, from: them, 10, .eur, fx: 2)], countedThrough: nil, delivery: .live)

        #expect(spy.count(of: .tips) == 1)
        #expect(spy.amount(for: .tipsValue) == 5)
    }

    @Test("With no cached rate the tip is counted but its value is skipped")
    func missingRateSkipsValueOnly() {
        let spy = ReceiptSpy()
        let reporter = spy.makeReporter(selfUserID: me)

        reporter.countReceived([tip(id: 1, from: them, 10, .eur, fx: 2)], countedThrough: nil, delivery: .live)

        #expect(spy.count(of: .tips) == 1)
        #expect(spy.count(of: .messages) == 1)
        #expect(spy.count(of: .tipsValue) == 0)
    }

    // MARK: - Events (instrument B)

    @Test("A crossed inbound tip emits Tip Received only")
    func crossedTipEmitsTipOnly() {
        let spy = ReceiptSpy()
        let reporter = spy.makeReporter(selfUserID: me)

        reporter.reportRead([tip(id: 1, from: them)], chatType: .tipDm)

        #expect(spy.tips.count == 1)
        #expect(spy.tips.first?.chatType == .tipDm)
        #expect(spy.messages.isEmpty)
    }

    @Test("A crossed inbound text emits Message Received")
    func crossedTextEmitsMessage() {
        let spy = ReceiptSpy()
        let reporter = spy.makeReporter(selfUserID: me)

        reporter.reportRead([text(id: 1, from: them)], chatType: .contactDm)

        #expect(spy.messages == [.contactDm])
        #expect(spy.tips.isEmpty)
    }

    @Test("Own crossed messages emit nothing")
    func crossedOwnMessagesEmitNothing() {
        let spy = ReceiptSpy()
        let reporter = spy.makeReporter(selfUserID: me)

        reporter.reportRead([text(id: 1, from: me), tip(id: 2, from: me)], chatType: .tipDm)

        #expect(spy.messages.isEmpty)
        #expect(spy.tips.isEmpty)
    }

    @Test("Every crossed inbound message emits its own event")
    func crossedWindowEmitsOnePerMessage() {
        let spy = ReceiptSpy()
        let reporter = spy.makeReporter(selfUserID: me)

        reporter.reportRead(
            [text(id: 1, from: them), tip(id: 2, from: them), text(id: 3, from: them)],
            chatType: .tipDm
        )

        #expect(spy.messages.count == 2)
        #expect(spy.tips.count == 1)
    }
}
```

- [ ] **Step 3: Run them to confirm they fail**

```bash
./Scripts/test.sh FlipcashTests/ConversationReceiptReporterTests
```

Expected: compile failure — `ConversationReceiptReporter` does not exist.

- [ ] **Step 4: Implement the reporter**

Create `Flipcash/Core/Controllers/ConversationReceiptReporter.swift`:

```swift
//
//  ConversationReceiptReporter.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore

/// The receive-side analytics concern, split out of `ConversationController`: which
/// delivered messages count toward the cumulative received counters, what a
/// read-pointer advance reports, and how a foreign-currency tip becomes a USD number.
///
/// Every dependency is an injectable closure, defaulting to the real `Analytics`
/// entry points, so the rules can be exercised without the Mixpanel transport (which
/// is inert in tests).
@MainActor
final class ConversationReceiptReporter {

    /// How a batch of messages reached the client. The distinction only matters when
    /// the client holds nothing for the conversation yet: a **live** delivery into an
    /// empty chat is a genuine first message and counts, while a **catch-up** into an
    /// empty chat is a cold backfill replaying the event log — counting it would
    /// permanently inflate a people property that cannot be decremented.
    enum Delivery: Equatable {
        case live
        case catchUp
    }

    /// The rate for a currency, native-per-USD, or nil when none is cached. Wired to
    /// `RatesController` by `SessionContainer`; nil-returning by default so an
    /// unwired reporter under-reports value rather than reporting it wrongly.
    var usdRate: @MainActor (CurrencyCode) -> Rate? = { _ in nil }

    private let selfUserID: UserID
    private let increment: @MainActor (Analytics.ReceivedCounter, Double) -> Void
    private let trackTipReceived: @MainActor (ConversationType?, ExchangedFiat) -> Void
    private let trackMessageReceived: @MainActor (ConversationType?) -> Void

    init(
        selfUserID: UserID,
        increment: @escaping @MainActor (Analytics.ReceivedCounter, Double) -> Void = { Analytics.increment($0, by: $1) },
        trackTipReceived: @escaping @MainActor (ConversationType?, ExchangedFiat) -> Void = { Analytics.tipReceived(chatType: $0, exchangedFiat: $1) },
        trackMessageReceived: @escaping @MainActor (ConversationType?) -> Void = { Analytics.messageReceived(chatType: $0) }
    ) {
        self.selfUserID = selfUserID
        self.increment = increment
        self.trackTipReceived = trackTipReceived
        self.trackMessageReceived = trackMessageReceived
    }

    // MARK: - Counters

    /// Credits the cumulative received counters for the inbound messages in `messages`
    /// that sit above `countedThrough` — the newest message id already stored for the
    /// conversation, read *before* this batch was persisted.
    ///
    /// A tip increments both `Tips Received` and `Messages Received`: the message
    /// counter is a total, not a non-tip remainder.
    func countReceived(
        _ messages: [ConversationMessage],
        countedThrough: MessageID?,
        delivery: Delivery
    ) {
        // Nothing stored and nothing live: a cold backfill. Seed the watermark by
        // letting the write land, but credit nothing.
        if countedThrough == nil, delivery == .catchUp { return }

        for message in messages {
            guard isInbound(message) else { continue }
            if let countedThrough, message.id <= countedThrough { continue }

            increment(.messages, 1)

            guard message.cashAction == .tipped, case .cash(let exchanged) = message.content else { continue }
            increment(.tips, 1)

            // Chat cash arrives in the SENDER's native currency. With no cached rate we
            // count the tip but skip its value: an understated total is recoverable, a
            // wrong one is permanent and unattributable.
            guard let usd = usdValue(of: exchanged) else { continue }
            increment(.tipsValue, usd)
        }
    }

    // MARK: - Events

    /// Reports one event per inbound message in the window a read-pointer advance just
    /// crossed. `Tip Received` and `Message Received` are mutually exclusive — a tip
    /// reports only as a tip.
    func reportRead(_ messages: [ConversationMessage], chatType: ConversationType?) {
        for message in messages {
            guard isInbound(message) else { continue }
            if message.cashAction == .tipped, case .cash(let exchanged) = message.content {
                trackTipReceived(chatType, exchanged)
            } else {
                trackMessageReceived(chatType)
            }
        }
    }

    // MARK: - Private

    /// Anything not sent by the signed-in user, matching Android: a system message
    /// (no sender) is still something the user received.
    private func isInbound(_ message: ConversationMessage) -> Bool {
        !message.isFromSelf(selfUserID)
    }

    private func usdValue(of exchanged: ExchangedFiat) -> Double? {
        let native = exchanged.nativeAmount
        if native.currency == .usd { return native.doubleValue }
        guard let rate = usdRate(native.currency) else { return nil }
        return native.convertingToUSD(rate: rate).doubleValue
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
./Scripts/test.sh FlipcashTests/ConversationReceiptReporterTests
```

Expected: PASS, 13 tests.

- [ ] **Step 6: Commit**

```bash
git add Flipcash/Core/Controllers/ConversationReceiptReporter.swift FlipcashTests/TestSupport/ReceiptSpy.swift FlipcashTests/Chat/ConversationReceiptReporterTests.swift && git commit -m "feat(analytics): add the conversation receipt reporter"
```

---

### Task 8: Wire the reporter into `ConversationController`

Three hooks. Live deliveries and gap-filled/reconnect deliveries both count, because `catchUp` writes through its own `onBatch` closure and never routes through `persist(event:)` — hooking only one would miss every reconnect. `resyncAfterReset`, `loadMessages`, and older-paging are deliberately **not** hooked: they are history loads, and counting them would be retroactive.

**Files:**
- Modify: `Flipcash/Core/Controllers/ConversationController.swift`
- Test: `FlipcashTests/Chat/ConversationReceiptWiringTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `FlipcashTests/Chat/ConversationReceiptWiringTests.swift`:

```swift
//
//  ConversationReceiptWiringTests.swift
//  FlipcashTests
//

import Testing
import Foundation
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("Conversation receipt wiring")
struct ConversationReceiptWiringTests {

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<50 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(condition())
    }

    private func makeController(
        _ mock: MockConversations,
        selfUserID: UserID,
        receipts: ConversationReceiptReporter,
        database: Database
    ) -> ConversationController {
        ConversationController(
            fetching: mock,
            messaging: mock,
            streaming: mock,
            contactNaming: MockDMContactNaming(),
            database: database,
            owner: .generate()!,
            selfUserID: selfUserID,
            receipts: receipts
        )
    }

    private func inboundTip(id: UInt64, from sender: UserID) -> ConversationMessage {
        ConversationMessage(
            id: MessageID(value: id),
            senderID: sender,
            content: .cash(ExchangedFiat(
                onChainAmount: TokenAmount(quarks: 5_000_000, mint: .usdf),
                nativeAmount: FiatAmount(value: 5, currency: .usd),
                currencyRate: Rate(fx: 1, currency: .usd)
            )),
            cashAction: .tipped,
            date: Date(timeIntervalSince1970: TimeInterval(id)),
            unreadSeq: id,
            eventSequence: id
        )
    }

    @Test("A live inbound tip is counted once, and a redelivery is not counted again")
    func liveDeliveryCountsOnce() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let me: UserID = UUID()
        let them: UserID = UUID()
        let spy = ReceiptSpy()
        let mock = MockConversations()
        let controller = makeController(mock, selfUserID: me, receipts: spy.makeReporter(selfUserID: me), database: database)
        let conversationID = ConversationID.test(1)

        controller.start()
        try await waitUntil { mock.streamOpened }

        mock.emit(.newMessages(conversationID, [inboundTip(id: 5, from: them)]))
        try await waitUntil { spy.count(of: .tips) == 1 }

        // The same message delivered again (a reconnect replay) must not re-credit.
        mock.emit(.newMessages(conversationID, [inboundTip(id: 5, from: them)]))
        try await Task.sleep(for: .milliseconds(100))

        #expect(spy.count(of: .tips) == 1)
        #expect(spy.count(of: .messages) == 1)
        #expect(spy.amount(for: .tipsValue) == 5)
    }

    @Test("A cold catch-up seeds the cache without counting")
    func coldCatchUpDoesNotCount() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let me: UserID = UUID()
        let them: UserID = UUID()
        let spy = ReceiptSpy()
        let mock = MockConversations()
        let conversationID = ConversationID.test(1)
        mock.feed = [Conversation(
            id: conversationID,
            members: [ConversationMember(userID: me, displayName: "", readPointer: nil)],
            lastMessage: nil,
            lastActivity: Date(timeIntervalSince1970: 0),
            type: .tipDm
        )]
        mock.deltaBatches = [
            .init(messages: [inboundTip(id: 1, from: them), inboundTip(id: 2, from: them)], checkpoint: 2),
        ]
        mock.deltaHead = 2
        let controller = makeController(mock, selfUserID: me, receipts: spy.makeReporter(selfUserID: me), database: database)

        controller.start()
        try await waitUntil { !controller.conversations.isEmpty }

        await controller.catchUp(conversationID: conversationID)

        #expect(spy.counters.isEmpty)
    }

    @Test("Marking read emits one event per crossed inbound message")
    func markReadEmitsCrossedEvents() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let me: UserID = UUID()
        let them: UserID = UUID()
        let spy = ReceiptSpy()
        let mock = MockConversations()
        let conversationID = ConversationID.test(1)
        mock.feed = [Conversation(
            id: conversationID,
            members: [ConversationMember(userID: me, displayName: "", readPointer: MessageID(value: 1))],
            lastMessage: nil,
            lastActivity: Date(timeIntervalSince1970: 0),
            type: .tipDm
        )]
        let controller = makeController(mock, selfUserID: me, receipts: spy.makeReporter(selfUserID: me), database: database)

        controller.start()
        try await waitUntil { mock.streamOpened && !controller.conversations.isEmpty }

        mock.emit(.newMessages(conversationID, [inboundTip(id: 2, from: them), inboundTip(id: 3, from: them)]))
        try await waitUntil { (try? database.newestMessageID(conversationID: conversationID)) == MessageID(value: 3) }

        await controller.markRead(conversationID: conversationID)

        #expect(spy.tips.count == 2)
        #expect(spy.tips.allSatisfy { $0.chatType == .tipDm })
        #expect(spy.messages.isEmpty)
    }

    @Test("A second mark-read over the same window emits nothing")
    func markReadIsNotReplayed() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let me: UserID = UUID()
        let them: UserID = UUID()
        let spy = ReceiptSpy()
        let mock = MockConversations()
        let conversationID = ConversationID.test(1)
        mock.feed = [Conversation(
            id: conversationID,
            members: [ConversationMember(userID: me, displayName: "", readPointer: MessageID(value: 1))],
            lastMessage: nil,
            lastActivity: Date(timeIntervalSince1970: 0),
            type: .tipDm
        )]
        let controller = makeController(mock, selfUserID: me, receipts: spy.makeReporter(selfUserID: me), database: database)

        controller.start()
        try await waitUntil { mock.streamOpened && !controller.conversations.isEmpty }

        mock.emit(.newMessages(conversationID, [inboundTip(id: 2, from: them)]))
        try await waitUntil { (try? database.newestMessageID(conversationID: conversationID)) == MessageID(value: 2) }

        await controller.markRead(conversationID: conversationID)
        await controller.markRead(conversationID: conversationID)

        #expect(spy.tips.count == 1)
    }
}
```

> If `Conversation.init` or `ConversationMember.init` reject these argument lists, copy the exact fixture shape used by `FlipcashTests/ConversationControllerTests.swift` — it constructs the same two types — and keep the ids and read pointers above.

- [ ] **Step 2: Run them to confirm they fail**

```bash
./Scripts/test.sh FlipcashTests/ConversationReceiptWiringTests
```

Expected: compile failure — `ConversationController.init` has no `receipts:` parameter.

- [ ] **Step 3: Own the reporter**

In `Flipcash/Core/Controllers/ConversationController.swift`, add the stored property beside `receiptSettle` (~line 132):

```swift
    @ObservationIgnored private let receiptSettle = ReceiptSettleGate()
    /// The receive-side analytics concern (cumulative counters + received events),
    /// owned by its own unit. Exposed so `SessionContainer` can wire its rate lookup.
    @ObservationIgnored let receipts: ConversationReceiptReporter
```

Add the init parameter — last, defaulted, so no existing call site changes — by replacing the tail of the parameter list and the assignments:

```swift
        typingHeartbeatInterval: Duration = .seconds(3),
        typingTimeout: Duration = .seconds(5),
        incomingTypingExpiry: Duration = .seconds(10),
        receipts: ConversationReceiptReporter? = nil
    ) {
        self.fetching = fetching
        self.messaging = messaging
        self.streaming = streaming
        self.contactNaming = contactNaming
        self.database = database
        self.owner = owner
        self.selfUserID = selfUserID
        self.receipts = receipts ?? ConversationReceiptReporter(selfUserID: selfUserID)
```

Leave the rest of `init` (the `ConversationTyping` construction) unchanged.

- [ ] **Step 4: Count live deliveries**

Still in `ConversationController.swift`, in `persist(event:)`, add the watermark read and the count to both message-bearing cases.

Replace the `.newMessages` case body with:

```swift
        case .newMessages(let conversationID, let messages):
            // Read before the write: the newest stored id is the analytics watermark,
            // and after the upsert it would already include this batch.
            let countedThrough = try? database.newestMessageID(conversationID: conversationID)
            let (reconciled, pairs) = reconciledForPersist(messages, in: conversationID)
            let ok = persist(operation: "upsert-messages") { try database.upsertConversationMessages(reconciled, conversationID: conversationID) }
            if ok {
                commitReconciled(pairs, in: conversationID)
                receipts.countReceived(reconciled, countedThrough: countedThrough ?? nil, delivery: .live)
            } else {
                // The delivered batch is in neither the DB nor the store — refetch it from the event log.
                scheduleGapCatchUp(conversationID)
            }
            refreshFeedPreview(for: conversationID)
            persistConversation(conversationID)
```

Replace the `.chatEvents` case body with:

```swift
        case .chatEvents(let conversationID, let events):
            let countedThrough = try? database.newestMessageID(conversationID: conversationID)
            let (reconciled, pairs) = reconciledForPersist(events.flatMap { $0.mutations.map(\.message) }, in: conversationID)
            // Messages + the advanced cursor persist atomically. `store.apply` already advanced the
            // in-memory cursor optimistically, so if this write rolls back, re-seat the cursor to the
            // persisted value and catch up — otherwise the un-persisted messages are skipped by the next
            // GetDelta and lost (the store no longer holds a confirmed copy).
            let ok = persist(operation: "apply-chat-events") {
                try database.persistMessages(reconciled, cursor: store.appliedCursor(for: conversationID), conversationID: conversationID)
            }
            if ok {
                commitReconciled(pairs, in: conversationID)
                receipts.countReceived(reconciled, countedThrough: countedThrough ?? nil, delivery: .live)
            } else {
                store.reseatCursor((try? database.catchupCursor(conversationID: conversationID)) ?? 0, for: conversationID)
                scheduleGapCatchUp(conversationID)
            }
            refreshFeedPreview(for: conversationID)
            persistConversation(conversationID)
```

- [ ] **Step 5: Count catch-up deliveries**

In `catchUp(conversationID:)`, capture the baseline once for the whole run — a per-batch watermark would let batch 2 of a cold backfill count everything batch 1 seeded — and pass it to every batch:

Replace:

```swift
        let after = store.appliedCursor(for: conversationID)
        do {
```

with:

```swift
        let after = store.appliedCursor(for: conversationID)
        // One baseline for the whole run. A per-batch watermark would let the second
        // batch of a cold backfill count everything the first batch just seeded.
        let countedThrough = (try? database.newestMessageID(conversationID: conversationID)) ?? nil
        do {
```

and inside the `onBatch` closure, add the count immediately after `commitReconciled`:

```swift
                if ok {
                    self.commitReconciled(pairs, in: conversationID)
                    self.receipts.countReceived(reconciled, countedThrough: countedThrough, delivery: .catchUp)
                    if let checkpoint { self.store.setAppliedCursor(checkpoint, for: conversationID) }
                } else {
```

- [ ] **Step 6: Emit the crossed window on mark-read**

Replace `markRead(conversationID:)` in full:

```swift
    func markRead(conversationID: ConversationID) async {
        guard let latestID = (try? database.newestMessageID(conversationID: conversationID)).flatMap({ $0 }) else { return }
        // Skip the round-trip when the server-known READ watermark already covers
        // the latest message. We advance the watermark locally after each success.
        let previousRead = store.selfReadPointer(for: conversationID, selfUserID: selfUserID)
        if let previousRead, latestID <= previousRead {
            return
        }
        do {
            try await messaging.markRead(owner: owner, conversationID: conversationID, messageID: latestID)
            store.advanceSelfReadPointer(to: latestID, in: conversationID, selfUserID: selfUserID)
            persistConversation(conversationID)
            // The read pointer is the receipt signal: everything inbound in the window it
            // just crossed is a message the user has now actually seen. Reported after the
            // advance, so a failed markRead reports nothing and the next attempt retries
            // the same window.
            let crossed = (try? database.messages(conversationID: conversationID, after: previousRead, through: latestID)) ?? []
            receipts.reportRead(crossed, chatType: conversation(withID: conversationID)?.type)
        } catch {
            logger.error("Failed to mark conversation read", metadata: [
                "conversationID": "\(conversationID)",
                "error": "\(error)",
            ])
            ErrorReporting.captureError(error, reason: "Failed to mark conversation read")
        }
    }
```

- [ ] **Step 7: Run the tests to verify they pass**

```bash
./Scripts/test.sh FlipcashTests/ConversationReceiptWiringTests FlipcashTests/ConversationControllerTests
```

Expected: PASS. `ConversationControllerTests` is included because `markRead` and `persist(event:)` both changed — it must stay green.

- [ ] **Step 8: Commit**

```bash
git add Flipcash/Core/Controllers/ConversationController.swift FlipcashTests/Chat/ConversationReceiptWiringTests.swift && git commit -m "feat(analytics): count received tips and messages as they arrive"
```

---

### Task 9: Wire the USD rate lookup

`ConversationController` holds no `RatesController`, but `SessionContainer.init` assigns `ratesController` before constructing the controller, so the closure can be wired there — beside the existing `blockedUserIDs` wiring, the established pattern.

**Files:**
- Modify: `Flipcash/Core/Session/SessionAuthenticator.swift` (`SessionContainer.init`, ~line 555)

- [ ] **Step 1: Wire the closure**

Replace:

```swift
        conversationController.start()
        self.conversationController = conversationController
```

with:

```swift
        // Chat cash arrives in the sender's native currency; the counters are USD.
        // Wired before `start()` so the first delivered message already normalises.
        conversationController.receipts.usdRate = { [weak ratesController] currency in
            ratesController?.rate(for: currency)
        }
        conversationController.start()
        self.conversationController = conversationController
```

- [ ] **Step 2: Build**

```bash
./Scripts/build.sh
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add Flipcash/Core/Session/SessionAuthenticator.swift && git commit -m "feat(analytics): normalise received tip value to USD"
```

---

### Task 10: Full targeted verification

- [ ] **Step 1: Build**

```bash
./Scripts/build.sh
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 2: Run every suite this work touches**

```bash
./Scripts/test.sh FlipcashTests/TokenSymbolEnrichmentTests FlipcashTests/ReceivedEventsTests FlipcashTests/ConversationReceiptReporterTests FlipcashTests/ConversationReceiptWiringTests FlipcashTests/ConversationControllerTests FlipcashTests/DatabaseConversationsTests FlipcashTests/AddMoneyEventsTests
```

Expected: PASS. `AddMoneyEventsTests` is included because `track` and the `Property` enum both changed.

- [ ] **Step 3: Ask the user to run the full `AllTargets` plan**

The full suite is the user's job — report the targeted results and ask them to run it before merge.

---

## Not in scope

- **Hex Mixpanel identity.** Android moved from base58 to lowercase hex to match iOS; iOS already sends `userID.data.hexString()` in `setIdentity` and needs no change.
- **`resyncAfterReset`, `loadMessages`, older-paging.** History loads, not receipts — counting them would be retroactive.
- **A `Database` schema change.** See deviation 2 above.
