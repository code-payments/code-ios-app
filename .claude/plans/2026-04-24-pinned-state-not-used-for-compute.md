# Pinned VerifiedState Not Used for Amount Compute

**Date:** 2026-04-24
**Status:** Fixed
**Target incident:** Server rejected intents with `native amount and quark value mismatch` for buy/sell/withdraw after the pinning feature shipped (branch `fix/verified-state-pinning`).

---

## Symptom

A $1 CAD buy of Jeffy produced:

```
Submitting intent intentId=D2yS...LowY type=IntentFundSwap
Action Transfer destination=AKtb...FGxx index=0 quarks=730906
Intent submission error code=invalidIntent detailCount=1
Failed to fund buy swap error=invalidIntent(native amount and quark value mismatch)
```

The stateful-swap phase succeeded; the funding-intent phase was rejected because `(quarks=730906, nativeAmount=$1.00 CAD)` did not match the rate in `pinnedState.rateProto`.

---

## Root Cause

`VerifiedState` pinning was implemented at two layers:

1. ViewModels held a pinned `VerifiedState` (immutable, captured at screen open).
2. `Session.buy/sell/withdraw` passed `pinnedState.rateProto` / `pinnedState.reserveProto` into the submitted intent.

But the critical middle step was missing: the ViewModels' `enteredFiat` and `maxPossibleAmount` computations sourced **rate** and **supplyFromBonding** from the *live* `RatesController.cachedRates` and `StoredMintMetadata.supplyFromBonding`, not from the pinned proof. The stream continuously replaced those live values while the user typed, so:

- UI computed: `quarks = nativeAmount / live_fx × 10^6`
- Intent submitted: `(quarks, nativeAmount, pinned_rateProto)`
- Server validated: `nativeAmount ≈ quarks × pinned_rateProto.exchangeRate / 10^6`

Any drift between `live_fx` and `pinned_fx` (even 0.1%) produced a mismatch larger than the server tolerance → reject.

The existing `Regression_native_amount_mismatch.swift` asserted that `vm.pinnedState == pinnedState` after a stream update (reference preserved), but never asserted that `enteredFiat.onChainAmount.quarks` was computed from the pinned rate. That's why the regression suite was green while the real bug was wide open.

---

## Fix

### 1. `VerifiedState.rate` convenience

Non-optional `Rate` reconstructed from the signed proto:

```swift
public var rate: Rate {
    guard let currency = currencyCode else {
        preconditionFailure("VerifiedState.rate: rateProto.currencyCode is unparseable; VerifiedProtoService cache integrity violated")
    }
    return Rate(fx: Decimal(exchangeRate), currency: currency)
}
```

Non-optional because a `VerifiedState` can only originate from `VerifiedProtoService.getVerifiedState`, which keys its cache by an already-parsed `CurrencyCode`. If parsing ever fails here, the cache itself is corrupted and crashing loudly is preferable to silently submitting against `.usd`.

### 2. ViewModels source rate and supply from the pin

- **`CurrencyBuyViewModel`**: `enteredFiat` and `maxPossibleAmount` use `pinnedState.rate`. `ratesController` dependency removed (no longer read after the refactor).
- **`CurrencySellViewModel`**: restructured to require `pinnedState: VerifiedState` at init (previously fetched lazily on the Next tap, which contradicted the "hold a pin for the whole flow" rule). `enteredFiat` and `maxPossibleAmount` use `pinnedState.rate` and `pinnedState.supplyFromBonding`. `ratesController` dependency removed.
- **`WithdrawViewModel`**: `pinnedState` stays optional because the user selects a balance inside the sheet and the pin is fetched per-balance in `selectCurrency(_:)`. During the async fetch window, `enteredFiat` falls back to `ratesController.rateForEntryCurrency()` / `selectedBalance.stored.supplyFromBonding` for display only; submission is gated by `canCompleteWithdrawal` which requires a non-stale `pinnedState`.
- **`Session.sell` cap workaround**: the "on-chain amount exceeds balance" rewrite at `Session.swift:741` now uses `verifiedState.rate` instead of `ratesController.rateForEntryCurrency()`.

### 3. Navigation gates and observability

`RatesController.currentPinnedState(for:mint:)` is the single entry point for resolving a pin at flow open. When the cache has no fresh pin the function returns `nil`; per the zero-UX-changes rule the caller silently declines to open the flow. The stale branch logs once with `mint`, `currency`, `ageSeconds`; the cache-empty branch is already logged inside `VerifiedProtoService.getVerifiedState` (at `.debug` level, since `awaitVerifiedState` polls up to 25× on a cold cache and a warn would flood telemetry). Flow context ("which user action triggered this") comes from the AppRouter navigation trail, not from a per-call tag.

### 4. Verified-proto persistence cleanup

During the simplify pass:

- **Dropped `receivedAt`** from `StoredRateRow` / `StoredReserveRow`, the `VerifiedProtoStore` protocol's surface, the `verified_rate` / `verified_reserve` tables, and the `clock:` injection point on `VerifiedProtoService`. It was written on every stream tick but never read — `VerifiedState.serverTimestamp` derives from the signed proto's own timestamp.
- **Batched writes**: `VerifiedProtoStore.writeRate(_:)` / `writeReserve(_:)` were replaced with `writeRates(_:)` / `writeReserves(_:)` taking the whole stream tick. The `Database` implementation wraps the whole batch in one `transaction(silent: true)`, cutting ~200 per-row commits to one per tick. `silent: true` because nothing in the UI listens to `verified_rate` / `verified_reserve` — the service's publishers drive downstream updates.
- **Warm-load race fixed**: warm-load now skips keys already populated by a concurrent `saveRates`/`saveReserveStates` delivery from the stream, so the DB's older bytes can never clobber fresher in-memory state.
- **Test-only single-row reads** (`readVerifiedRate`, `readVerifiedReserve`) moved from `Database+VerifiedProtos.swift` into `FlipcashTests/TestSupport/Database+VerifiedProtosTestSupport.swift`.

### 5. Dead-code cleanup

- Removed `import Logging` + unused `private let logger = …` from `CurrencyBuyViewModel`, `CurrencySellViewModel`, `CurrencySellConfirmationViewModel`, and `WithdrawViewModel`.
- Removed the stored `ratesController` property and init parameter from `CurrencyBuyViewModel` and `CurrencySellViewModel` (both source rate from the pin now).
- Factored three identical ~15-line `Session(...)` construction blocks into `Session.makeMock(database:historyController:ratesController:)`. `Session.unverifiedMock` is now an alias for `Session.mock`; `SessionContainer.mock` calls the factory with its shared controllers.

---

## Tests

### Regression suite (`Regression_native_amount_mismatch.swift`)

Existing:
- A — stream update mid-flow does not replace `vm.pinnedState`.
- B — stale cached pin makes `currentPinnedState` return `nil`, blocking navigation.
- C — pin aging past `clientMaxAge` disables the submit button.

Added:
- D (buy) — pinned rate 1.35 / live cache 1.37 / `enteredAmount = "1"` → `enteredFiat.onChainAmount.quarks == 740_741`; the buggy live path produced `729_927`.
- D (withdraw) — same shape, asserts `enteredFiat.currencyRate.fx == Decimal(1.35)`.
- D (withdraw-nil-pin fallback) — with `pinnedState = nil`, `enteredFiat` falls back to live rate for display but `canCompleteWithdrawal == false` so submission is blocked.
- D (sell) — asserts `enteredFiat.currencyRate.fx == Decimal(1.35)` with live cache drifted to 1.37.

### Supporting test changes

- `VerifiedProtoServiceTests` — adjusted for the batch store API; added a warm-load-does-not-clobber-stream test that pre-seeds the store with an older proto and verifies the stream-delivered fresher proto wins.
- `Database+VerifiedProtosTests` — rewritten against `writeRates(_:)` / `writeReserves(_:)`; uses the test-only read helpers in the new `Database+VerifiedProtosTestSupport.swift`.
- `CurrencyBuyViewModelTests` — added `cadPinnedState` fixture matching the configured CAD live rate so assertions of `enteredFiat.currencyRate.currency == .cad` still hold after the VM started sourcing rate from the pin.

---

## Risk / Rollout

- No additional schema version bump needed — the branch already bumped `SQLiteVersion` when it introduced `verified_rate` / `verified_reserve`. Dropping `receivedAt` is part of the same rebuild-on-login cycle.
- No feature flag. The mismatch bug was live in production; a flagged rollout would mean half the users keep hitting it.
- Observability: `RatesController.currentPinnedState` logs stale-pin blocks with `operation`, `mint`, `currency`, `ageSeconds`. `Session.*` logs `verifiedStateStale` throws as defense-in-depth. Expect the "native amount and quark value mismatch" rate to drop to ~zero after this ships.

---

## Why the earlier test suite missed the bug

The tests verified the *plumbing* (pin reference preserved, submit gated on staleness) but not the *invariant* (compute reads from the pin). Every assertion passed whether or not the VMs actually consulted `pinnedState.rate`. The lesson: when a plan says "X is the source of truth," at least one test must be structurally impossible to pass unless X was actually consulted. "The reference didn't change" is not that test — hence Scenario D's pinned-vs-live divergence check.
