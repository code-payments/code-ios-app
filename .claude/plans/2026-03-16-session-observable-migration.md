# Session @Observable Migration Plan

**Date:** 2026-03-16
**Goal:** Migrate Session from `ObservableObject` to `@Observable`, including all prerequisite types.
**Branch:** `refactor-session-observable-migration`

---

## Progress

| Phase | Status | Commits |
|-------|--------|---------|
| **Tier 1: BetaFlags** | ✅ Done | `1504bbdb` |
| **Tier 1: Preferences** | ✅ Done | `0418e9a8` |
| **Tier 1: PushController** | ✅ Done | `7cd2a054` |
| **Tier 1: HistoryController** | ✅ Done | `f758371b` |
| **Tier 2: Updateable\<T\>** | ✅ Done | `9d31401b` |
| **Tier 2: RatesController** | ✅ Done | `f983b7a6` |
| **Tier 2: Simplify fixes** | ✅ Done | `5b9c618b` |
| **Tier 3: Session** | ✅ Done | `d22a0c8a` |
| **Tier 3: SessionAuthenticator** | ✅ Done | `f1b32892` |
| **Tier 4: NotificationController** | ✅ Done | `378da6ae` |
| **Tier 4: ViewModels (7 low-risk)** | ✅ Done | `616fc8a8` |
| **Tier 4: OnrampViewModel** | ⬜ Not started (medium risk) | — |
| **Tier 4: WithdrawViewModel** | ⬜ Not started (medium risk) | — |
| **Tier 4: CurrencySellViewModel** | ⬜ Not started | — |

### Lessons Learned in Tier 3
- `lazy var` is incompatible with `@Observable` — the macro transforms stored properties into computed, which conflicts with `lazy`. Use IUOs (`Type!`) initialized in `init` instead
- `@ObservationIgnored` on `Updateable` properties breaks the observation chain — computed properties like `balances` read through them, so they must remain tracked
- `@ObservedObject` → `let` for read-only injected `@Observable` objects (BalanceScreen, CurrencyInfoScreen); `@Bindable` only when `$` bindings are needed (ScanScreen)
- Session has a lot of UI state mixed with business logic — future opportunity to split into Session + SessionUIState

### Lessons Learned in Tier 2
- Updateable\<T\> has 3 consumers (Session, TransactionHistoryScreen, CurrencyInfoViewModel) — migrating the class itself was better than inlining
- Combine subscriptions can coexist with `@Observable` — mark `cancellables` as `@ObservationIgnored`, keep `import Combine`
- `@Environment(Type.self)` supports optional types (`Type?`) — used to replace Mirror hack in AccountSelectionScreen
- `Task.sleep(nanoseconds:)` → `Task.sleep(for: .milliseconds())` with `Duration` parameter type
- `try!` should be `try?` when return type is already optional

### Lessons Learned in Tier 1
- `@ObservationIgnored` is required on all property wrappers (`@Defaults`, `@SecureString`) inside `@Observable` classes
- `@objc` + `#selector` observers must be converted to closure-based `addObserver(forName:)` (PushController, will also apply to Updateable)
- No `@Entry` or custom `EnvironmentKey` needed — `@Environment(Type.self)` auto-synthesizes for `@Observable` types
- `@AppStorage` inside `@Observable` would NOT trigger view updates even with `@ObservationIgnored` — the current `@Defaults` pattern (separate persistence layer + tracked stored properties) is correct
- `DispatchQueue.main.async` should be replaced with `Task { @MainActor in }` when touching these files

---

## Original State

- **Session** (`Session.swift:19`): `@MainActor class Session: ObservableObject` with 9 `@Published` properties
- **15 remaining `ObservableObject` types** in the Flipcash target (down from 19)
- **CashOperator** is already `@Observable` — bridged into Session via `withObservationTracking` (lines 255–273)
- **Updateable\<T\>**: `ObservableObject` using `@objc` + `NSNotification`, manually triggers `objectWillChange.send()` — primary blocker
- **Swift version:** Flipcash target is Swift 5.0, no strict concurrency enabled
- **Concurrency:** Session is already `@MainActor`, migration doesn't change isolation boundaries

---

## Leaf Dependencies (No ObservableObject Children)

| Type | `@Published` | Consumers | Can Migrate Independently |
|------|:---:|---|:---:|
| BetaFlags | 2 | Container → all screens | ✅ |
| Preferences | 2 | Container → ScanScreen | ✅ |
| PushController | 1 | SessionContainer → env | ✅ |
| HistoryController | 0 | Session owns, env injection | ✅ |
| NotificationController | 6 | Container → badge counts | ✅ |
| RatesController | 4 | Session + env injection | ⚠️ Must before/with Session |
| Updateable\<T\> | 1 | Session (internal) | ⚠️ Blocker for Session |
| 9 ViewModels | varies | Screen-scoped each | ✅ |

## Interior Nodes (Own Other ObservableObject)

| Type | Children | Must Migrate After |
|---|---|---|
| Session | Updateable×2, RatesController, HistoryController, CashOperator | Updateable, RatesController |
| SessionAuthenticator | Session (creates it) | Session |

---

## Effort & Impact Tiers

### Tier 1 — Quick Wins (Low Effort, Low Risk)
- **BetaFlags** (~30 min) — 2 properties, global singleton, perfect first migration
- **Preferences** (~30 min) — 2 properties, same shape
- **PushController** (~20 min) — 1 property
- **HistoryController** (~15 min) — 0 `@Published`, just drop conformance

### Tier 2 — Unlocks Session (Medium Effort, Critical)
- **Updateable\<T\>** (~2 hours) — Must redesign: uses `@objc` (incompatible with `@Observable`). Replace with inline tracked properties on Session + closure-based NotificationCenter observer.
- **RatesController** (~1-2 hours) — 4 `@Published` properties, Session depends on them in computed properties

### Tier 3 — The Main Event (High Effort, Highest Impact)
- **Session** (~4-6 hours) — 9 `@Published` → plain properties, remove CashOperator bridge, update 11 consumer views
- **SessionAuthenticator** (~2 hours) — 4 `@Published`, 4 consumer views

### Tier 4 — Mop Up (Opportunistic)
- **NotificationController** (~1 hour) — 6 properties, self-contained
- **9 ViewModels** (~30 min each) — Screen-scoped, migrate as screens are touched

---

## Phase 1 — Validate the Pattern (1 day)

### Steps
1. Migrate **BetaFlags** → `@Observable`
   - Remove `: ObservableObject` and `@Published` annotations
   - Add `@Observable` macro
   - Update `Container.swift:51`: `.environmentObject(betaFlags)` → `.environment(betaFlags)`
   - Update all consumer views: `@EnvironmentObject var betaFlags: BetaFlags` → `@Environment(BetaFlags.self) var betaFlags`

2. Migrate **Preferences** → `@Observable` (same pattern)
   - Update `Container.swift:52` injection
   - Update consumer views

3. Migrate **PushController** → `@Observable`
   - Update `SessionAuthenticator.swift:380` injection
   - Update consumer views

4. Migrate **HistoryController** → `@Observable`
   - Drop `: ObservableObject` conformance, add `@Observable`
   - Update `SessionAuthenticator.swift:379` injection

5. Build + run tests

### Validation
- All 4 types inject via `.environment()` and are consumed via `@Environment(Type.self)`
- No regressions in UI updates

---

## Phase 2 — Unblock Session (1-2 days)

### Steps
1. **Redesign Updateable\<T\>** — Replace with inline tracked properties on Session:
   ```swift
   // Before (Updateable<T> as ObservableObject + @objc)
   private lazy var updateableBalances: Updateable<[StoredBalance]> = { ... }()

   // After (tracked property + closure-based observer)
   private(set) var balances: [StoredBalance] = []
   private var balancesObserver: Any?

   // In init:
   balancesObserver = NotificationCenter.default.addObserver(
       forName: .databaseDidChange, object: nil, queue: .main
   ) { [weak self] _ in
       self?.balances = (try? self?.database.getBalances()) ?? []
       self?.ensureValidTokenSelection()
       self?.updateStreamingMints()
   }
   ```
   - Remove `objectWillChange.send()` calls (lines 204, 214) — `@Observable` tracks automatically
   - Remove `import Combine` if no other Combine usage remains
   - Consider keeping `Updateable.swift` for potential other users, or delete if Session is the only consumer

2. **Migrate RatesController** → `@Observable`
   - 4 `@Published` properties → plain `var`
   - Update `SessionAuthenticator.swift:378` injection
   - Update consumer views using `@EnvironmentObject var ratesController`

3. Build + run tests

### Validation
- `balances` and `limits` still update when `.databaseDidChange` fires
- RatesController properties still drive UI updates in GiveScreen, EnterAmountView, etc.

---

## Phase 3 — Session Itself (1-2 days)

### Steps
1. Convert `Session` class declaration:
   ```swift
   // Before
   class Session: ObservableObject {

   // After
   @MainActor @Observable
   class Session {
   ```

2. Remove `@Published` from all 9 properties (lines 25–38) — they become plain `var`

3. **Keep CashOperator bridge as-is** (lines 255–273):
   - CashOperator is part of a separate PR (`cashoperator-phase1`) — do NOT modify
   - Keep `billState`, `presentationState`, `valuation` as stored properties
   - Keep `observeCashOperator()` and its `withObservationTracking` bridge
   - The `objectWillChange.send()` calls in the bridge are no longer needed with `@Observable` (mutations to stored properties are tracked automatically), but the bridge itself must stay until the CashOperator PR merges
   - **Follow-up:** After CashOperator PR merges, remove the bridge and replace with computed forwarding properties

4. Remove `import Combine` and `private var cancellables` (line 218)

5. Update `SessionAuthenticator.swift:377`: `.environmentObject(session)` → `.environment(session)`

6. Update 8 consumer views with `@EnvironmentObject var session`:
   - `GiveScreen.swift:25`
   - `EnterAmountView.swift:14`
   - `WithdrawAmountScreen.swift:14`
   - `WithdrawScreen.swift:16`
   - `DepositCurrencyListScreen.swift:14`
   - `SelectCurrencyScreen.swift:16`
   - `SwapProcessingScreen.swift:16`
   - `CurrencySellConfirmationScreen.swift:19`

   Change: `@EnvironmentObject private var session: Session` → `@Environment(Session.self) private var session`

7. Update 3 consumer views with `@ObservedObject var session`:
   - `ScanScreen.swift:18`
   - `CurrencyInfoScreen.swift:29`
   - `BalanceScreen.swift:20`

   Change: `@ObservedObject private var session: Session` → use `@Bindable` if writing bindings, or just pass as parameter

8. Build + run tests

### Validation
- CashOperator state changes still reflect in ScanScreen
- All 11 consumer views still react to Session property changes
- Toast, dialog, bill state all work correctly

---

## Phase 4 — SessionAuthenticator + Cleanup (1 day)

### Steps
1. Migrate **SessionAuthenticator** → `@Observable`
   - 4 `@Published` properties → plain `var`
   - Update `Container.swift:49`: `.environmentObject(sessionAuthenticator)` → `.environment(sessionAuthenticator)`
   - Update 4 consumer views:
     - `ContainerScreen.swift:13`
     - `ScanScreen.swift:14`
     - `LoginScreen.swift:15`
     - `IntroScreen.swift:14`

2. Migrate **NotificationController** → `@Observable`
   - Update `Container.swift:53` injection
   - Update consumer views

3. Verify zero `.environmentObject()` calls remain

4. Build + run full test suite

---

## Phase 5 — ViewModels (Opportunistic, No Deadline)

Migrate each ViewModel when its screen is touched for other work:
- GiveViewModel, ScanViewModel, OnboardingViewModel, OnrampViewModel
- WithdrawViewModel, CurrencySelectionViewModel, CurrencyInfoViewModel
- CurrencyBuyViewModel, CurrencySellViewModel, CurrencySellConfirmationViewModel

Pattern: Remove `: ObservableObject` + `@Published`, add `@Observable`. In consumer view, change `@StateObject` → `@State` or `@ObservedObject` → `@Bindable`.

---

## Key Technical Decisions

### Updateable\<T\> Redesign
**Chosen approach:** Inline as tracked properties on Session with closure-based NotificationCenter observer.
**Why:** `@Observable` can't use `@objc`. The async `notifications(named:)` sequence is an option but adds unnecessary complexity for a synchronous database read. Closure-based observer is the simplest.

### CashOperator Integration
This branch merges **before** the CashOperator PR (`cashoperator-phase1`). When that branch is rebased onto this one, CashOperator should adopt `@Observable` patterns directly — no `ObservableObject` bridge needed. Specifically:
- Session is now `@Observable`, so `withObservationTracking` bridging is unnecessary
- CashOperator's `billState`/`presentationState`/`valuation` can either remain on CashOperator (accessed via `session.cashOperator?.billState`) or be forwarded as computed properties on Session
- No `objectWillChange.send()` — `@Observable` tracks mutations automatically

### Concurrency Impact
- No isolation changes needed — Session is already `@MainActor`
- No `@unchecked Sendable` or `@preconcurrency` escape hatches required
- `@Observable` + `@MainActor` is the canonical Swift 6 pattern

---

## Risks

| Risk | Mitigation |
|---|---|
| Updateable redesign breaks database-driven updates | Test balance/limit updates after `.databaseDidChange` fires |
| CashOperator rebase onto this branch | CashOperator PR should adopt @Observable patterns directly — no bridge needed |
| `.environment()` injection fails silently (crash if type not in environment) | Build + test after each phase; `.environmentObject()` crashes too, so risk is equivalent |
| ViewModels with `@StateObject` lifetime semantics | `@State` with `@Observable` has same lifetime; verify per-ViewModel |

---

## Status: In Progress

**16 of 19 ObservableObject types migrated.** The migration is functional — Session and all core types are on `@Observable`. What remains is cleanup.

### Remaining Work

#### 3 ViewModels (medium risk, ~45 min total)
| ViewModel | Why medium risk | Notes |
|-----------|----------------|-------|
| **OnrampViewModel** | Shared across parent + child screens via `@ObservedObject` | Check all consumers for `$viewModel` bindings |
| **WithdrawViewModel** | Shared across WithdrawScreen + WithdrawAmountScreen | Same — check binding usage |
| **CurrencySellViewModel** | Used via `@State` in CurrencyInfoScreen | Already `@State`, just needs `ObservableObject` → `@Observable` |

#### 3 Container-level types (cannot migrate yet)
| Type | Blocker |
|------|---------|
| **Client** | Lives in `FlipcashCore` package — requires package-level changes |
| **FlipClient** | Lives in `FlipcashCore` package — same |
| **StoreController** | Inherits from `NSObject` (StoreKit delegate) — `@Observable` incompatible with `NSObject` subclasses |

These 3 remain as `.environmentObject()` in `Container.injectingEnvironment()`. They don't block Swift 6 migration — views consuming them via `@EnvironmentObject` will continue to work.

#### Future improvements (post-migration)
- **Session UI state extraction** — `billState`, `presentationState`, `valuation`, `toast`, `dialogItem`, `isShowingBillEditor`, `pendingCurrencyInfoMint`, `coinbaseOrder` could move to a dedicated `SessionUIState` type
- **Session init injection** — ScanScreen, BalanceScreen, CurrencyInfoScreen receive Session via init; could switch to `@Environment(Session.self)` for consistency
- **CashOperator PR rebase** — adopt `@Observable` patterns directly, no `ObservableObject` bridge needed
- **Swift 6.2 migration** — once all `ObservableObject` types are migrated, enable strict concurrency checking
