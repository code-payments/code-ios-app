# Pin `VerifiedState` for Amount-Entry Flows

**Date:** 2026-04-23
**Status:** Design (pending user review)
**Target incident:** Server rejects payment intents with "native amount does not match sell amount."

---

## Summary

Amount-entry screens currently compute their UI math against one snapshot of `(exchangeRate, supplyFromBonding)` — derived fields cached in SQLite — while the intent submitted seconds later carries a different snapshot that came from the `VerifiedState` in-memory cache. The server validates `native_amount` against the `VerifiedState` it receives in the intent, so any drift between the two snapshots produces the rejection.

This plan makes the proof the single source of truth: **one `VerifiedState` is pinned when the amount-entry screen opens, stays pinned for the lifetime of that flow (the stream may deliver fresher proofs — we ignore them), every calculation runs against that pinned proof, and the same proof is passed straight to `Session.buy/sell/withdraw()`.** To survive cold starts and keep the pin available immediately, `VerifiedState` protos are persisted to new SQLite tables, written by the existing `VerifiedProtoService` as the stream delivers them. A client-side staleness check (2-minute safety buffer below the server's 15-minute window, measured against the proof's own server-signed timestamp) gates both **entering** the flow (the navigation handler only opens the screen when a non-stale pin exists) and **submitting** from it (the existing submit button disables when the pin ages out mid-flow). There are **zero visible UX changes** on the amount-entry screens — no loading views, no refresh prompts, no new error states.

---

## Problem (with code references)

Today's flow (buy/sell/withdraw):

1. User opens amount-entry screen.
2. `GiveViewModel` / `WithdrawViewModel` / `CurrencySellViewModel` reads
   `selectedBalance.stored.supplyFromBonding` (from the `balance` SQLite table, populated
   earlier by `database.updateLiveSupply(updates:date:)` inside `RatesController:142-153`)
   and `RatesController.cachedRates[currency]`.
3. `ExchangedFiat.compute(fromEntered:rate:mint:supplyQuarks:)` runs the bonding-curve
   math against those two values.
4. User taps submit.
5. `Session.buy() / sell() / withdraw()` calls
   `RatesController.getVerifiedState(for:mint:)`, which reads the in-memory
   `VerifiedProtoService` dictionaries. This is a **second, independent** snapshot of rate
   + reserve proofs. The proto is then attached to the intent.
6. Server validates the intent's `native_amount` against the `VerifiedState` it received.
   If the supply or rate in the intent's proof differs from what the client used in step 2,
   the server rejects with "native amount does not match sell amount."

Two specific mechanisms cause the drift:

- `LiveMintDataStreamer` pushes rate updates and reserve-state updates in separate
  messages. Between the stream's write to `balance.supplyFromBonding` (via
  `VerifiedProtoService.reserveStatesPublisher`) and the UI's next read of
  `getVerifiedState()`, a newer proof can arrive.
- `VerifiedProtoService` holds proofs only in memory, so after a relaunch the UI has
  `balance.supplyFromBonding` from the last session while `getVerifiedState()` returns
  `nil` until the stream reconnects. Current callers handle this via `awaitVerifiedState`
  polling, but the UI already displayed numbers computed from the stale cached supply.

Only `SendCashOperation` handles this correctly today — it takes a single `VerifiedState`,
pins it for the lifetime of the operation, and enforces a 15-minute `maxReserveAge`
before submission (`SendCashOperation.swift:55, 197-200`). We're extending that pattern
to every amount-entry path.

---

## Design

### 1. Persistence layer

New SQLite tables (additions to `Flipcash/Core/Controllers/Database/Schema.swift`):

```swift
// Verified exchange rate proofs, keyed by fiat currency.
// Stores the serialized VerifiedCoreMintFiatExchangeRate proto plus the moment we
// received it from the server (used for staleness checks).
CREATE TABLE verified_rate (
    currency TEXT PRIMARY KEY NOT NULL,
    rate_proto BLOB NOT NULL,
    received_at INTEGER NOT NULL  // unix seconds
);

// Verified reserve-state proofs, keyed by mint address.
// Stores the serialized VerifiedLaunchpadCurrencyReserveState proto plus
// received_at.
CREATE TABLE verified_reserve (
    mint TEXT PRIMARY KEY NOT NULL,
    reserve_proto BLOB NOT NULL,
    received_at INTEGER NOT NULL
);
```

We keep them as two tables (not one `verified_state` table) because:
- Rates are keyed by fiat currency; reserves are keyed by mint. The grain differs.
- They arrive in separate stream messages; writing them as two independent rows avoids
  a read-modify-write whenever only one updates.
- `VerifiedProtoService` already holds them in two separate dictionaries — the schema
  mirrors that.

**Bump `SQLiteVersion` in `Info.plist`.** Per the existing convention, the app rebuilds
the DB from server data on next login; no migration code. The server replays all mint
metadata, balances, rates, and (via the stream) reserve states, so no data is
genuinely lost.

`Database` gets a small helper layer:
- `readVerifiedRate(currency:) -> (Ocp_Currency_V1_VerifiedCoreMintFiatExchangeRate, Date)?`
- `readVerifiedReserve(mint:) -> (Ocp_Currency_V1_VerifiedLaunchpadCurrencyReserveState, Date)?`
- `writeVerifiedRate(_:receivedAt:)`
- `writeVerifiedReserve(_:receivedAt:)`
- `readAllVerifiedRates()`, `readAllVerifiedReserves()` for warm start.

Proto blob encoding: `try proto.serializedData()` on write, `try Proto(serializedBytes: blob)` on read. Both throw — failures are logged and the row is treated as absent (forces a fresh fetch from the stream).

### 2. Writer: `VerifiedProtoService` becomes the single source of truth

Today `VerifiedProtoService` is a pure in-memory cache that publishes changes. We keep that
role but add a DB-persistence side-effect:

- Inject `Database` (or a narrow protocol covering just the four read/write helpers)
  into `VerifiedProtoService`.
- On `saveRates(_:)` and `saveReserveStates(_:)`, schedule a background write to the
  corresponding table. Failures log a warning via the FlipcashCore logger (metadata:
  `currency`, `mint`, `error`) but do not surface to the caller — the in-memory cache
  still reflects the new value, so the UI is unaffected.
- On init, warm-load from the DB: read all rows, populate the in-memory dictionaries
  with the stored protos and their `received_at` timestamps, then emit them on the
  publishers so downstream consumers see them immediately.

`VerifiedState` grows one computed property:

```swift
public struct VerifiedState: Equatable, Sendable {
    public let rateProto: Ocp_Currency_V1_VerifiedCoreMintFiatExchangeRate
    public let reserveProto: Ocp_Currency_V1_VerifiedLaunchpadCurrencyReserveState?

    // NEW: oldest server-signed proof timestamp. Computed from the protos themselves,
    // not stored — the server-signed timestamp lives inside the signed proof and
    // doesn't need duplication.
    public var serverTimestamp: Date { ... }

    // existing computed properties unchanged
}
```

`serverTimestamp` is the **server-signed** timestamp carried inside the proofs (not our
client receive time), because that's the clock the server measures against when it
decides whether to accept a proof. When both protos are present it's the minimum (oldest)
of the two — that's the deadline we're actually racing against. When only the rate is
present (non-bonded currencies like USDF), it's the rate proof's timestamp.

Non-bonded amount-entry flows (USDF withdraw) are immune to the supply-mismatch class of
bug — there is no reserve proof to mis-correlate with. They still go through the same
pinning machinery so we have one code path.

### 3. Pinning contract

Every amount-entry flow follows this pattern:

```
┌─────────────────────────────────────────────────────────────────────┐
│  Navigation handler (on the screen that launches Give/Withdraw/     │
│  Sell — typically a Button's action closure)                        │
│                                                                     │
│  1. ratesController.currentPinnedState(for:mint:)                   │
│       • returns a non-stale VerifiedState from cache, or nil        │
│  2. If nil:                                                         │
│       • silent no-op. Do not navigate. Do not show anything.        │
│       • log a warning for observability.                            │
│  3. If non-nil: construct the ViewModel with that pinned state and  │
│     perform the normal navigation / sheet presentation.             │
└─────────────────────────────────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│  ViewModel (e.g., GiveViewModel)                                    │
│                                                                     │
│  • Holds pinnedState: VerifiedState as immutable state for the      │
│    entire flow. **It is never auto-replaced by newer stream data.** │
│  • All ExchangedFiat.compute calls use                              │
│    supplyQuarks: pinnedState.supplyFromBonding                      │
│    rate: Rate(pinnedState.rateProto)                                │
│  • Fresher proofs delivered by LiveMintDataStreamer land in         │
│    VerifiedProtoService cache for the NEXT flow; they do not touch  │
│    this flow's pinnedState.                                         │
│  • canSubmit = amountValid && !pinnedState.isStale. The existing    │
│    submit button is wired to canSubmit so it goes disabled (using   │
│    its existing disabled styling) when the pin ages out mid-flow.   │
│  • On submit: pass pinnedState through to Session.buy/sell/withdraw.│
└─────────────────────────────────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Session.buy/sell/withdraw                                          │
│                                                                     │
│  • Accepts verifiedState: VerifiedState as a required parameter.    │
│  • No internal call to RatesController.getVerifiedState().          │
│  • Removes Error.missingVerifiedState branch.                       │
│  • Re-checks staleness (defense-in-depth); if stale, throws         │
│    Error.verifiedStateStale. The VM catches it silently (no toast,  │
│    no new UX) — this is a belt-and-suspenders guard for the         │
│    canSubmit race window, which canSubmit itself should prevent.    │
└─────────────────────────────────────────────────────────────────────┘
```

**Why "no auto-replace":** If the ViewModel swapped `pinnedState` from A to B while the
user was typing, the numbers on screen (computed against A) would then be submitted in
an intent that carries B — exactly the bug we're fixing. The server gives us a generous
15-minute window precisely so the client can hold one proof for an entire entry session.
We consume that budget rather than chase freshness.

**Why "zero visible UX":** Showing a loading view or a refresh prompt while the stream
delivers a new proof is exactly the pattern that would make the screens feel different
from today. A dropped pin is not an error the user needs to act on — the navigation
handler catches it upstream, the `canSubmit` guard catches it during typing, and the
existing disabled styling on the submit button is the user-visible signal. In the happy
path (which is the path ~100% of users see, because the stream keeps the cache hot),
the flow is indistinguishable from the pre-fix experience.

`Rate` construction from `rateProto`: we already do this conversion in multiple places
(grep for `Rate(`) — the ViewModel uses the same helper so the `rate` it passes to
`ExchangedFiat.compute` is byte-identical to what the server will validate against.

### 4. Staleness handling

Single source constant:

```swift
// FlipcashCore/Sources/FlipcashCore/Models/VerifiedState.swift
public extension VerifiedState {
    /// Client-side freshness ceiling. The server accepts proofs up to 15 minutes
    /// old (measured against its own signing clock), so this is 13 minutes —
    /// leaving a 2-minute safety buffer for network RTT and clock skew. If a
    /// pinned state ages past this point, amount-entry screens require an
    /// explicit user refresh before allowing submission.
    static let clientMaxAge: TimeInterval = 13 * 60

    var age: TimeInterval { Date().timeIntervalSince(serverTimestamp) }
    var isStale: Bool { age >= Self.clientMaxAge }
}
```

Three enforcement points — and **notably no "auto re-pin while typing" hook, no loading
view, no refresh prompt**:

- **At navigation time (before the screen opens).** The handler calls
  `currentPinnedState(for:mint:)`, which returns `nil` if nothing suitable is cached
  (empty or stale). If nil, the navigation silently doesn't happen — no alert, no
  loading spinner, no new screen state. In practice this never fires because the
  stream + DB warm-load keep the cache hot.
- **On the submit button, throughout the flow.** `canSubmit` on the VM includes
  `!pinnedState.isStale`; the existing submit button's enabled state is wired to
  it. If the user lingers past 13 minutes, the button goes into its existing
  disabled styling. No new UI elements, no text changes.
- **At submit inside `Session.*`** as defense-in-depth. If somehow a submit makes it
  through with a stale pin (e.g., a millisecond race between `canSubmit` and the
  button action), `Session` throws `verifiedStateStale` and the VM silently logs it.

We do **not** silently re-pin during a live flow. A stream-delivered fresher proof
sits in `VerifiedProtoService`'s cache and is picked up by the *next* flow. This is
the whole point of the redesign: the numbers the user looks at and the numbers the
server validates must come from the same proof.

The 13-minute ceiling means a flow started with a cold-start pin that's already
~10 minutes old still has ~3 minutes of runway before the submit button disables.
If that proves too tight in practice, the navigation handler can be tightened
(e.g., "only use a <5-minute-old proof"). Ship simple first, measure the
"Tried to open … without a pinnedState" warning rate from the telemetry in the
Observability section, then decide.

### 5. What does not change

Following Karpathy's "surgical changes" rule, we do not touch:

- `StoredMintMetadata.supplyFromBonding` and `StoredBalance.supplyFromBonding`. These
  fields still back list and market-cap UI that does not submit intents. Removing them
  would force those views through a proof requirement they don't need.
- `SendCashOperation`. It already does the right thing with its own 15-minute guard.
- `CurrencyLaunchProcessingViewModel`. USD-only, no bonded supply math, no bug.
- `LiveMintDataStreamer`. It still handles its own stream lifecycle, keepalive, and
  reconnect. All we add is DB persistence at the consumer (`VerifiedProtoService`).
- The existing `rate` table (separate from the new `verified_rate` table). That table
  stores plain `Rate` objects used for cold-start display in places that don't need
  proofs (e.g., amount formatting in activity history). It stays. `verified_rate` is
  strictly for intent-bearing flows.

---

## Affected flows

| Flow | Screen / ViewModel | `Session` entry point | Changes |
|---|---|---|---|
| Give → Send (via `Send`) | `GiveViewModel` | `Session.buy(...)` → `Session.sendCash(...)` | ViewModel accepts `pinnedState`; `Session.buy` takes `verifiedState`; `ExchangedFiat.compute` uses pinned supply + rate. |
| Give → Send Link | `GiveViewModel` → `SendCashOperation` (existing) | Already pins | No change beyond making `GiveViewModel` itself pinned so its UI math matches what `SendCashOperation` ends up sending. |
| Withdraw (USDF → external) | `WithdrawViewModel` | `Session.withdraw(...)` | ViewModel accepts `pinnedState`; `Session.withdraw` takes `verifiedState`; removes internal `getVerifiedState()` call. Non-bonded path: `pinnedState.reserveProto` is `nil`, only the rate matters. |
| Sell (bonded currency → USDF) | `CurrencySellViewModel` | `Session.sell(...)` | ViewModel accepts `pinnedState`; `Session.sell` takes `verifiedState`; remove internal `getVerifiedState()`. Re-verify whether the "on-chain amount exceeds balance" workaround at `Session.swift:747-757` becomes obsolete — it likely does once UI + intent share supply, but confirm during implementation. |
| Buy (bonded currency) | Call sites of `Session.buy` with `amount` | `Session.buy(...)` | Same signature change; callers pin and pass. |
| Onramp (Coinbase buy with card) | `OnrampAmountScreen` / `OnrampCoordinator` | Coinbase flow, not a Flipcash intent | Out of scope — Coinbase doesn't use `VerifiedState`. Verify during implementation that no Flipcash intent is fired mid-flow. |
| Send Cash (in-person scan) | `SendCashOperation` | Directly via `submitIntent` | Already pinned. No change except consumers of the pin chain (e.g., `ScanCashOperation` after receive) now carry the same `VerifiedState`. |

The coordinator step (fetch pinned state → build ViewModel) is the thin new surface. It
can live as a small helper on `RatesController` — e.g. `awaitPinnedState(for:mint:)` —
returning `VerifiedState` or throwing a timeout error the UI can translate to "Can't
reach the server right now, try again."

---

## Testing strategy

All tests are Swift Testing (`import Testing`), colocated in `FlipcashTests/`.

### Unit tests

- `VerifiedStateTests`: `age`, `isStale` boundary at `clientMaxAge`, serialization round-trip.
- `VerifiedProtoServiceTests`:
  - Cold-start warm load emits cached protos on publishers.
  - Write failures (corrupt blob) don't prevent in-memory updates.
  - Stream-delivered updates replace older DB rows.
- `GiveViewModelTests`, `WithdrawViewModelTests`, `CurrencySellViewModelTests`:
  - With a pinned state, all computed amounts use the pinned supply and rate.
  - When `RatesController` emits a fresher state, the ViewModel re-pins and recomputes
    the displayed amount.
  - Submit path passes the pinned state through unchanged to `Session.*`.
- `SessionTests`:
  - `Session.buy/sell/withdraw` accept a stale `VerifiedState` and throw
    `Error.verifiedStateStale`.
  - `Session.sell`'s former "missing supply" branch is gone; verify via coverage or
    explicit absence test.

### Regression tests

Keep the focus tight — one test file per server error surface that drove this change:

- `FlipcashTests/Regressions/Regression_native_amount_mismatch.swift`:
  - **Scenario A:** UI computes with supply S1, then stream delivers S2 before submit. Old code would have shipped the intent with `native_amount` from S1 but proof with S2. New code keeps S1 pinned and throws if staleness exceeds `clientMaxAge`, otherwise ships consistent (S1, S1).
  - **Scenario B:** Cold start with a stored-but-stale reserve proof. Amount-entry screen blocks until a fresh one arrives.

### Integration / UI

- Extend existing `GiveScreen` / `WithdrawScreen` UI tests to cover the "updating
  prices" loading state when no fresh proof is available. Use XCUITest-friendly
  accessibility identifiers on the loading view (never `simctl` or `Process` — CI-safe).

### What we don't test

- The server's own validation — that's verified implicitly by the absence of the
  error in production.
- `LiveMintDataStreamer` wire protocol — already covered by existing tests.

---

## Rollout and risk

- **Schema version bump:** on next login after this ships, users rebuild their DB from
  server data. This is the established pattern (see `SessionAuthenticator.initializeDatabase`)
  and has no user-visible cost beyond a longer first-login sync.
- **No feature flag.** The mismatch bug is already happening in production; a flagged
  rollout would mean half our users keep hitting the error. We ship behind the normal
  release QA.
- **Observability:**
  - `VerifiedProtoService` logs DB write failures (warning, metadata: `currency`,
    `mint`, `error`).
  - `Session.*` logs `verifiedStateStale` throws (info, metadata: `currency`, `mint`,
    `ageSeconds`, `clientMaxAge`). This gives us a signal if the "submit-time
    re-check fires often" — would indicate the ViewModel's re-pin logic has a gap.
  - Existing Bugsnag capture at the intent-submit catch-sites picks up any residual
    server errors; expect the "native amount does not match" rate to drop to ~zero.
- **Manual test pass before merge:**
  - Give, Withdraw, Sell on both a freshly launched currency and USDC.
  - Cold start with no network → wait for stream → submit (exercises warm-load and
    stale-guard).
  - Background app for 20 minutes on an amount-entry screen → bring forward → submit
    (exercises re-pin + submit-time stale guard).

---

## Decided during review

- **Age source.** `VerifiedState.serverTimestamp` is the server-signed timestamp
  carried inside the proofs, not the client's receive time. This matches the clock
  the server uses to accept/reject proofs and aligns with `SendCashOperation`'s
  existing `reserveTimestamp` check.
- **Buffer.** Server window is 15 minutes; client cutoff is 13 minutes (2-minute safety
  buffer for RTT and clock skew).
- **No mid-flow re-pin.** A pin set at screen open is immutable for the flow's duration.
  Newer proofs arriving via the stream land in `VerifiedProtoService` cache for the
  next flow. If the current pin ages out, the user sees an explicit "refresh" action
  and re-pins on their own terms.

## Open implementation questions (decide during `writing-plans`)

1. **Where does the coordinator live?** Options: method on `RatesController`, a free
   function, a small `VerifiedStateProvider` type. Pick the one that requires the fewest
   ViewModel changes.
2. **`awaitVerifiedState` signature.** The existing variant (used by
   `CurrencyLaunchProcessingViewModel`) polls without a freshness filter. We add a
   `maxAge:` parameter, or we introduce a second method. Prefer extending the existing
   one to avoid two near-duplicates.
3. **Exposing `serverTimestamp` from the proto.** The verified protos carry signed
   fields the client can't alter; we need to locate the timestamp field(s) on
   `Ocp_Currency_V1_VerifiedCoreMintFiatExchangeRate` and
   `Ocp_Currency_V1_VerifiedLaunchpadCurrencyReserveState` and decode them into
   `Date`. `SendCashOperation` already pulls `reserveTimestamp` from somewhere — use
   the same source/decoder to keep one truth.
4. **Re-pin UX for Give with a live bill.** If the user has advertised a bill and the
   underlying `VerifiedState` updates, do we re-advertise or keep the original?
   `SendCashOperation` already owns this decision; confirm it still holds post-pin.

---

## Non-goals

- Removing `supplyFromBonding` from `StoredMintMetadata` / `StoredBalance`.
- Refactoring `RatesController` into actor isolation or similar.
- Introducing a shared base ViewModel for the three amount-entry flows.
- Changing the streaming protocol or the set of things `LiveMintDataStreamer`
  subscribes to.

These are all out of scope. If any become necessary during implementation, raise them
then.
