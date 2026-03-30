# Swift 6.2 Strict Concurrency Migration

**Date:** 2026-03-17 (updated 2026-03-30)
**Status:** Phase 0 complete, Phase 1 baseline established
**Prerequisites:** `@Observable` migration **complete** — all 4 remaining types resolved (see Phase 0 below)

---

## Swift 6.2 Strategy: Approachable Concurrency

Swift 6.2 introduces two features that dramatically reduce migration effort:

### `defaultIsolation(MainActor.self)` (SE-466)
Sets `@MainActor` as the default isolation for the entire module. Since Flipcash is a UI app where most code already runs on main, this eliminates hundreds of manual `@MainActor` annotations. Code that needs to run off-main opts out explicitly with `nonisolated` or `@concurrent`.

### `NonisolatedNonsendingByDefault` (SE-461)
Nonisolated async functions inherit the caller's isolation instead of hopping to background. This eliminates the largest category of Sendable warnings — non-Sendable values crossing isolation boundaries just because an async function was called.

**Caution:** Enabling `NonisolatedNonsendingByDefault` changes runtime behavior. Async methods that previously ran on background threads will now run on the caller's actor. Any method that genuinely needs background execution must be marked `@concurrent`. **Before enabling, audit async methods that do heavy work to add `@concurrent`.**

### Recommended Approach (from Swift community)
1. Enable `defaultIsolation(MainActor.self)` — reduces false-positive warnings massively
2. Enable `NonisolatedNonsendingByDefault` — but first audit async methods for `@concurrent` needs
3. Move from `SWIFT_STRICT_CONCURRENCY = targeted` → `complete` incrementally

---

## Current State (verified 2026-03-30)

- **Flipcash target:** Swift 5.0 (all 4 build configs), `SWIFT_STRICT_CONCURRENCY = targeted` enabled
- **Test targets:** Swift 5.0 — need version bump first
- **Packages:** FlipcashCore/FlipcashAPI/FlipcashCoreAPI/FlipcashUI at swift-tools-version 6.1, but no `swiftSettings` for strict concurrency
- **Legacy packages:** CodeServices/CodeUI/CodeCurves/CodeAPI at 5.7, CodeScanner at 5.9 — only migrate if Flipcash depends on them
- **Generated protos:** FlipcashAPI + FlipcashCoreAPI have `@unchecked Sendable` and `nonisolated(unsafe)` in generated files — regenerate with updated protoc, don't hand-edit

### @Observable Blockers — RESOLVED

All 4 types resolved on `swift6-migration` branch:

| Type | Resolution |
|------|------------|
| `CountdownTimer` | Eliminated — replaced with `TimelineView` + `@State` date |
| `Poller` | Rewritten — `Task` + `Task.sleep` (serialized, `Sendable`) |
| `Client` | `@Observable` + `@Environment` (3 views updated) |
| `FlipClient` | `@Observable` + `@Environment` (injection site updated) |

### Concurrency Workaround Debt

| Workaround | Files | Notes |
|------------|:---:|---|
| `@unchecked Sendable` | 114 | Mostly generated protobuf — regenerate with updated protoc |
| `@MainActor` annotations | 151 | Most eliminated by `defaultIsolation(MainActor)` |
| `@preconcurrency` imports | 22 | External deps (BigDecimal, Accelerate, Firebase, Combine) |
| `nonisolated(unsafe)` | 20 | Mix of generated code and manual workarounds (1 removed: MarketCapController) |

### Phase 1 Baseline (targeted, 2026-03-30)

**Flipcash app target: 0 concurrency warnings** (all resolved)

Fixes applied:
- `RatesController.swift` — `@preconcurrency import Combine` (PassthroughSubject not yet Sendable)
- `NotificationController.swift` — `@MainActor @Sendable` on handler closure
- `MarketCapController.swift` — removed unnecessary `nonisolated(unsafe)` on `Sendable` constant

**FlipcashCore package: 5 concurrency warnings remain** (Phase 3 scope)

| File | Warning | Phase |
|------|---------|-------|
| `MessagingService.swift:113` | Non-Sendable `self` + `StreamReference` capture | Phase 3 |
| `SwapService.swift:238,325` | Non-Sendable completion closures | Phase 3 |
| `TransactionService.swift:459` | Non-Sendable type capture | Phase 3 |
| `UnaryCall+Extensions.swift:16` | ResponsePayload not Sendable | Phase 3 |

## The Client Problem

`Client` and `FlipClient` are the **biggest blockers** for strict concurrency:

- Both are `@MainActor class: ObservableObject` in `FlipcashCore`
- 54 files, ~5,900 lines across the Clients directory
- Every gRPC call goes through them — marking them `Sendable` would require every service, every request/response type, and every callback to be `Sendable`
- Without a split, you'd need **hundreds of annotations** across the library

### Proposed Split: Protocol-Based Client Boundaries

Instead of making the monolithic `Client`/`FlipClient` classes `Sendable`, extract **protocol interfaces** at the consumer boundary:

```
Before:
  Session → Client (concrete, @MainActor, 52 files)

After:
  Session → ScanCashClient (protocol, 3 methods)
  Session → SendCashClient (protocol, 3 methods)
  RatesController → RatesClient (protocol, 2 methods)
  HistoryController → HistoryClient (protocol, 2 methods)
  PushController → PushClient (protocol, 2 methods)
  ...etc
```

Each protocol is tiny and `Sendable`-conformable. The concrete `Client` conforms to all of them but doesn't need to be `Sendable` itself — it stays `@MainActor` and passes protocol-typed references to consumers.

This also enables testability. The `cashoperator-phase1` plan proposed `ScanCashClient` and `SendCashClient` protocols but **neither has been implemented yet** — this work is still ahead.

---

## Migration Order (by effort)

### Phase 0 — Finish @Observable Prerequisites (half day)

1. **Migrate `CountdownTimer` to `@Observable`** in `FlipcashUI/Sources/FlipcashUI/Controllers/CountdownTimer.swift`
   - Update `ConfirmPhoneScreen` and `ConfirmEmailScreen`: `@StateObject` → `@State`

2. **Migrate `Poller` to `@Observable`** in `FlipcashCore/Sources/FlipcashCore/Utilities/Poller.swift`
   - Simple class with no `@Published` — straightforward

3. **Migrate `Client` to `@Observable`** in `FlipcashCore/Sources/FlipcashCore/Clients/Payments API/Client.swift`
   - Update `LoginScreen`, `AccountSelectionScreen`, `SwapProcessingScreen`: `@EnvironmentObject` → `@Environment`
   - Update injection site to use `.environment(client)` instead of `.environmentObject(client)`

4. **Migrate `FlipClient` to `@Observable`** in `FlipcashCore/Sources/FlipcashCore/Clients/Flip API/FlipClient.swift`
   - Update any remaining `@EnvironmentObject` references
   - Update injection site similarly

> **Note:** Client and FlipClient are the riskiest — they're core dependency-injection types. Test thoroughly after migration.

### Phase 1 — Baseline (1 day)

1. **Enable `SWIFT_STRICT_CONCURRENCY = targeted` on Flipcash target**
   - Shows warnings without breaking the build
   - Reveals the true scope of work
   - Record the warning count as a baseline

2. **Enable `defaultIsolation(MainActor.self)` on Flipcash target**
   - Eliminates most `@MainActor` annotation noise
   - Most Flipcash code already runs on `@MainActor` — this makes it the default
   - Rebuild and compare warning count — should drop significantly

3. **Audit async methods for `@concurrent`**
   - Before enabling `NonisolatedNonsendingByDefault`, identify async methods that genuinely need background execution (heavy computation, file I/O)
   - Mark those `@concurrent` proactively
   - gRPC calls go through NIO which handles its own threading — likely fine without `@concurrent`

4. **Enable `NonisolatedNonsendingByDefault`**
   - Async functions now inherit caller isolation — eliminates Sendable crossing warnings
   - Rebuild and verify no performance regressions (nothing accidentally running on main that shouldn't be)

5. **Bump test targets from Swift 5.0 → 6.0**
   - FlipcashTests, FlipcashUITests
   - Fix any compile errors (likely minimal — already use Swift Testing)

6. **Enable strict concurrency on FlipcashTests**
   - Fix test-side warnings first (lowest risk, fast iteration)

### Phase 2 — Leaf Packages (2-3 days)

Bottom-up, starting with packages that have no internal dependencies:

| Package | Files | Blockers | Effort |
|---------|:---:|---|:---:|
| **FlipcashUI** | ~114 | None — SwiftUI views, mostly `@MainActor` | ~3 hours |
| **FlipcashAPI** | ~10 | Regenerate protos with updated protoc | ~1 hour |
| **FlipcashCoreAPI** | ~27 | Same | ~1 hour |

For each package:
1. Add `.swiftLanguageMode(.v6)` to the target in Package.swift
2. Fix errors
3. Build clean before moving on

### Phase 3 — FlipcashCore (3-5 days)

The critical package. Contains `Client`, `FlipClient`, all models, and all service layers.

**Step 1: Models (~1 day)**
- Make value types `Sendable` where they aren't already
- `ExchangedFiat`, `Quarks`, `Rate`, `CurrencyCode`, `StoredBalance`, etc.
- Most are structs/enums — should be straightforward

**Step 2: Client protocol extraction (~2 days)**
- Extract per-consumer protocols from `Client` and `FlipClient`
- Each protocol declares only the methods its consumer needs
- Keep `Client`/`FlipClient` as `@MainActor` concrete classes conforming to all protocols
- Consumers receive protocol-typed dependencies instead of concrete `Client`

**Step 3: Service layer (`~1-2 days)**
- gRPC service wrappers (`AccountInfoService`, `TransactionService`, etc.)
- These hold `ClientConnection` and `DispatchQueue` — need `@unchecked Sendable` with documented safety (gRPC handles thread safety internally)
- Or convert to actors if feasible

**External dependency mitigations:**
| Library | Files | Strategy |
|---------|:---:|---|
| BigDecimal | 3 | Wrap in `@unchecked Sendable` with documented invariant |
| PhoneNumberKit | 2 | Same — value is only used on `@MainActor` |
| SQLite.swift | 4 | Database access is already serialized — document and wrap |
| Firebase | 2 | Keep `@preconcurrency import` — Firebase team is working on Swift 6 support |
| Combine | 2 | `@preconcurrency import Combine` is standard — Apple hasn't fully migrated it |

### Phase 4 — Flipcash App Target (2-3 days)

With packages clean, enable strict concurrency on the app target:

1. **Switch from `targeted` to `complete`**
2. Fix remaining warnings — mostly:
   - Closures capturing `self` across actor boundaries
   - `@EnvironmentObject` types (`Client`, `FlipClient`, `StoreController`) — these stay as-is with `@preconcurrency` if needed
   - Any remaining `Task { }` patterns that need `@Sendable` closures

### Phase 5 — Migrate Combine publishers in actors to AsyncStream

`VerifiedProtoService` uses `PassthroughSubject` inside an `actor`. Combine's `sink` closures are non-`@Sendable`, so Swift 6 infers caller isolation on them (SE-0423). When `send()` fires from the actor's executor, the runtime assertion fails because the sink was created in a `@MainActor` context.

**Current workaround:** subscribers must use `.receive(on: DispatchQueue.main)` before `.sink`. This is fragile — any subscriber that forgets will crash at runtime with `_dispatch_assert_queue_fail`.

**Proper fix:** replace `PassthroughSubject` with `AsyncStream` via `makeStream(of:)`. This is the actor-native approach — no Combine threading mismatch, no runtime assertions.

| Publisher | Location | Subscribers |
|-----------|----------|-------------|
| `ratesPublisher` | `VerifiedProtoService:37` | `RatesController:109` |
| `reserveStatesPublisher` | `VerifiedProtoService:40` | `RatesController:117` |

### Phase 6 — Cleanup & Polish (1 day)

1. Remove all `@preconcurrency` imports that are no longer needed (after library updates)
2. Remove `@unchecked Sendable` where proper Sendable conformance is now possible
3. Final audit of `nonisolated` and `@MainActor` annotations
4. Update CLAUDE.md with new concurrency conventions

---

## External Dependency Swift 6 Status (pinned versions as of 2026-03-30)

Check these before starting Phase 3:

| Library | Pinned Version | Swift 6 Ready? | Notes |
|---------|---------------|:-:|---|
| Firebase iOS SDK | 10.29.0 | Partial | Use `@preconcurrency import` |
| SQLite.swift | `master` branch (custom fork: dbart01) | Unknown | Not on a versioned release — check fork status |
| BigDecimal | 3.0.2 | Unknown | Wrap in `@unchecked Sendable` if needed |
| PhoneNumberKit | 4.2.2 | Unknown | Value only used on `@MainActor` — wrap if needed |
| grpc-swift | 1.27.4 | Likely | gRPC team tracks Swift evolution closely |
| swift-nio | 2.92.0 | Yes | Already Swift 6 compatible |
| swift-protobuf | 1.33.3 | Yes | Already Swift 6 compatible |

---

## Estimated Total Effort

| Phase | Effort | Dependencies |
|-------|:---:|---|
| Phase 0: Finish @Observable | half day | None |
| Phase 1: Baseline | 1 day | Phase 0 complete |
| Phase 2: Leaf packages | 2-3 days | None (parallel with Phase 1) |
| Phase 3: FlipcashCore | 3-5 days | Library compatibility checks |
| Phase 4: Flipcash target | 2-3 days | Phases 2-3 complete |
| Phase 5: Cleanup | 1 day | Phase 4 complete |
| **Total** | **~2-3 weeks** | |

## Risks

| Risk | Mitigation |
|------|------------|
| External library not Swift 6 ready | `@preconcurrency import` + `@unchecked Sendable` wrappers with documented safety invariants |
| Client protocol split is too large | Start with operations (ScanCashClient, SendCashClient) from cashoperator-phase1, expand incrementally |
| Generated proto files produce warnings | Regenerate with latest protoc-gen-grpc-swift; suppress warnings on generated targets if needed |
| Cascade of Sendable requirements | Fix bottom-up (models → services → clients → app). Don't try to fix everything at once |
