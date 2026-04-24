# Migrate iOS to the Android "pin-at-compute" pattern

**Date:** 2026-04-24
**Status:** Planned — execute in a fresh session
**Supersedes (partially):** `2026-04-24-pinned-state-not-used-for-compute.md` (keep for the server-error history; the core native/quark invariant still holds, only the *moment* we pin changes)

---

## Why this change

The current iOS implementation pins a `VerifiedState` at **flow open** and threads it through the amount-entry ViewModel for the flow's lifetime. That works, but it forces us to solve a cluster of problems Android side-steps entirely:

| Problem | iOS today | After pin-at-compute |
|---|---|---|
| Pin goes stale while user types | Subtitle flips to "Rate expired"; submit disables | Impossible — pin is fetched at Next/Submit |
| User changes entry currency mid-flow | `.onChange` re-pin dance in the screen | Non-issue — pin fetched with whatever `entryCurrency` is at submit |
| Navigation gate: no pin available at open | `currentPinnedState` returns nil, silent decline | Non-issue — user opens the screen freely |
| Currency selector disables rows without a pin | Unsolved (flagged as #6) | Non-issue — same as above |

The Android dev (Brandon) is shipping the pin-at-compute pattern. "I don't trigger any computation effort until they confirm. Matches the balance-check we do when they hit Next in the give flow."

Cross-platform parity on a correctness-adjacent flow is worth the churn.

---

## Target architecture

1. **No `pinnedState` on the amount-entry ViewModels while the user types.**
2. **ViewModels read live rate** (`ratesController.rateForEntryCurrency()`) for display-only math (subtitle, max, preview). This preview may drift by a cent or two from the intent's actual values; that's fine because the preview is never submitted.
3. **At the user's "commit" moment** (Next for sell/withdraw; Buy button for buy), the VM:
   - `await`s `ratesController.currentPinnedState(for: currency, mint: mint)`
   - If nil, shows an error dialog ("Couldn't get a fresh rate. Please try again.") and bails
   - Otherwise computes `ExchangedFiat` against the freshly-fetched pin
   - Passes that `ExchangedFiat` + the pin to `Session.buy/sell/withdraw`
4. **`Session.buy/sell/withdraw` signatures stay the same.** They still take `verifiedState: VerifiedState` and `assertFresh` is still called as defense-in-depth — the server round-trip is quick enough that fresh-at-compute stays fresh at submit.

---

## Current state snapshot (what exists on this branch right now)

So a fresh session can tell what's there to remove.

### ViewModels (pin-at-open)

- `CurrencyBuyViewModel`: `var pinnedState: VerifiedState` (observed, no `@ObservationIgnored`), `subtitle` computed property that flips to `.errorMessage` on stale, `enteredFiat`/`maxPossibleAmount` read `pinnedState.rate`.
- `CurrencySellViewModel`: same shape, requires pinnedState at init, also has `subtitle`.
- `WithdrawViewModel`: `var pinnedState: VerifiedState?` (optional — fetched per-balance in `selectCurrency`), has `rePinForEntryCurrency()`, `refreshPin(for:)`, and `pinFetchTask` lifecycle. Subtitle flips on stale-pin present.

### Screens

- `CurrencyBuyAmountScreen` / `CurrencySellAmountScreen`: have `.onChange(of: ratesController.entryCurrency)` that fetches a new pin and assigns it to the VM.
- `WithdrawAmountScreen`: has `.onChange` calling `viewModel.rePinForEntryCurrency()`.
- `CurrencyInfoScreen.onSell` / `onSelectReserves`: async pre-fetch via `currentPinnedState` before constructing the VM; silent decline on nil.
- `CurrencySellConfirmationScreen`: takes `pinnedState: VerifiedState`, passes it to `CurrencySellConfirmationViewModel`.

### Shared UI

- `EnterAmountView.Subtitle` has a `.errorMessage(String)` case added for the stale-pin UX.

### Tests (regression suite)

- Scenario A: pin reference unchanged across stream deliveries
- Scenario B: stale cached protos → `currentPinnedState` returns nil
- Scenario C: pin aged mid-flow → `canPerformAction` = false
- Scenario D: `enteredFiat.onChainAmount.quarks` uses pinned rate (buy/sell/withdraw + nil-pin fallback variant)
- Scenario E: swapping `pinnedState` re-renders VM (buy/sell)
- Scenario F: stale pin flips `subtitle` to `.errorMessage` (buy/sell/withdraw + nil-pin variant)

---

## File-by-file migration plan

### Commit 1 — Buy flow pin-at-compute

**`CurrencyBuyViewModel.swift`:**
- Delete `var pinnedState: VerifiedState` stored property.
- Delete `subtitle` computed property.
- Re-introduce `@ObservationIgnored private let ratesController: RatesController` (needed for live rate reads and submit-time pin fetch).
- `enteredFiat` reads `ratesController.rateForEntryCurrency()` instead of `pinnedState.rate`. It's now a display-only computation.
- `maxPossibleAmount` same.
- `canPerformAction`: drop the staleness check; keep amount-positive + within-display-limit.
- `performBuy`: async fetch `pinned = await ratesController.currentPinnedState(for: entryCurrency, mint: .usdf)`. On nil, show an error dialog ("Couldn't get a fresh rate. Please try again."). On success, recompute `amount` as `ExchangedFiat(nativeAmount:, rate:)` using `Rate(pinned.rateProto)` — this is the same shape as today's `enteredFiat` logic — then call `session.buy(amount:verifiedState:of:)`.
- Remove `pinnedState` from init. Signature becomes `init(currencyPublicKey:currencyName:session:ratesController:)`.

**`CurrencyBuyAmountScreen.swift`:**
- Remove the `.onChange(of: ratesController.entryCurrency)` re-pin block.
- `subtitle:` goes back to `.balanceWithLimit(viewModel.maxPossibleAmount)`.

**`CurrencyInfoScreen.swift` — `onSelectReserves`:**
- Delete the async Task wrapping + `currentPinnedState` pre-fetch. Directly construct `CurrencyBuyViewModel` and show the sheet.

### Commit 2 — Sell flow pin-at-compute

Same pattern as buy, but pin fetches at **Next** (before the confirmation screen), not the final Sell button:

**`CurrencySellViewModel.swift`:**
- Delete `var pinnedState: VerifiedState` and `subtitle`.
- Re-add `ratesController`. Same `enteredFiat`/`maxPossibleAmount` live-rate treatment.
- `showConfirmationScreen`: async fetch pin; on success, compute `ExchangedFiat` against the pin and append `.confirmation(amount:, pinnedState:)` to the path (path case needs the pin). On nil pin, show error dialog.
- Change `CurrencySellPath.confirmation` from a case-without-payload to `case confirmation(amount: ExchangedFiat, pinnedState: VerifiedState)`. The current path lets the screen reach back into the VM for `enteredFiat` and `pinnedState`; now both are resolved at the commit moment and carried forward.

**`CurrencySellAmountScreen.swift`:**
- Switch destination case accordingly.
- Remove `.onChange` re-pin.
- `subtitle:` goes back to `.balanceWithLimit`.

**`CurrencySellConfirmationViewModel.swift` / `CurrencySellConfirmationScreen.swift`:**
- Mostly unchanged — they already receive `amount + pinnedState`. Make sure the init wiring matches the new path case.

**`CurrencyInfoScreen.swift` — `onSell`:**
- Delete the async pre-fetch. Directly construct `CurrencySellViewModel` and show the sheet.

### Commit 3 — Withdraw flow pin-at-compute

Withdraw is the gnarliest because it has a per-balance pin fetch today. Pin-at-compute simplifies it significantly.

**`WithdrawViewModel.swift`:**
- Delete `var pinnedState: VerifiedState?`, `pinFetchTask`, `refreshPin(for:)`, `rePinForEntryCurrency()`, `subtitle`.
- `selectCurrency(_:)` becomes: set `selectedBalance`, clear amount/address/destination, push the enter-amount screen. That's it — no pin fetch.
- `canCompleteWithdrawal`: drop the `pinnedState != nil && !isStale` guard. Keep amount + destination + sufficient-funds checks.
- Submit path: async fetch pin at the point `completeWithdrawal` (or equivalent) runs. Compute `ExchangedFiat` against it. Call `Session.withdraw`.
- `enteredFiat` / `maxWithdrawLimit` / `exchangedFee` all read `ratesController.rateForEntryCurrency()` unconditionally. `supplyFromBonding` reads from `selectedBalance.stored.supplyFromBonding` (the live cache) since there's no pin during typing.

**`WithdrawAmountScreen.swift`:**
- Remove `.onChange(of: ratesController.entryCurrency)` calling `rePinForEntryCurrency`.
- `subtitle:` stays `.balanceWithLimit(viewModel.maxWithdrawLimit)`.

### Commit 4 — Shared UI and test-support cleanup

**`EnterAmountView.swift`:**
- Remove `Subtitle.errorMessage(String)` case.
- Revert `subtitleColor` to `isExceedingLimit ? .textError : .textSecondary`.
- Remove the body arm that renders `.errorMessage`.

**`FlipcashTests/TestSupport/WithdrawViewModel+TestSupport.swift`:**
- Remove `pinnedState` parameter from `createViewModel`.

### Commit 5 — Regression tests restructure

The existing suite tests invariants that no longer apply. Replace with a smaller suite that matches the pin-at-compute contract.

**Delete:**
- Scenario A (pin immutable across deliveries) — no pin in VM to check.
- Scenario B (stale cached protos block flow-open) — no flow-open gate.
- Scenario C (stale mid-flow disables submit) — impossible by construction.
- Scenario D (withdraw nil-pin fallback) — nil pin is now the normal case.
- Scenario E (pin-swap re-renders) — no pin to swap.
- Scenario F (all four) — no subtitle error state.

**Keep and rework:**
- Scenario D (buy/sell/withdraw — the actual mismatch invariant): change to "when `Session.buy/sell/withdraw` is called, the `amount.onChainAmount.quarks` was computed against `verifiedState.rateProto`'s fx." This is more of a unit-test assertion on the VM's submit path — after calling `performBuy()` on a VM with a known-fresh pin available in `currentPinnedState`, assert the `Session.buy` mock received matching (quarks, nativeAmount, rateProto) values. Might require a test seam (Session protocol or a capturing mock).

**Alternative simpler regression coverage:** one test per flow that asserts the submit path fetches a pin and hands it unchanged to `Session.*`. A capturing mock of `Session.buy/sell/withdraw` is probably worth adding in TestSupport.

### Commit 6 — Plan doc cleanup

Update or delete `.claude/plans/2026-04-24-pinned-state-not-used-for-compute.md` (the previous plan) so readers don't get confused about the pinning semantics. One sentence at the top saying "superseded by pin-at-compute" is enough; the history of the fix is still valuable.

Delete this plan doc after merging unless you want to keep it as an "architectural decision" record.

---

## Gotchas a fresh session needs to know

1. **`SessionContainer.mock`, `Session.mock`, `Database.mock` etc. live in `FlipcashTests/TestSupport/Mocks.swift`** — not in production. Don't add more mocks to production; preview-only mocks like `Container.mock` and `SessionAuthenticator.mock` stay in production because `#Preview` blocks reference them.

2. **`VerifiedProtoService` is an `actor`.** `currentPinnedState` / `getVerifiedState` are `async`. The pin fetch in performBuy/Next will need a Task.

3. **Batch persistence:** `VerifiedProtoStore.writeRates([StoredRateRow])` / `writeReserves([StoredReserveRow])` take arrays, wrapped in one transaction by the `Database` impl. Don't revert to per-row writes.

4. **Warm-load race:** `VerifiedProtoService.warmLoadFromStore` skips keys already populated by a concurrent stream delivery. Don't undo this.

5. **Phone redactor fix:** `PatternRedactor` now requires a non-digit character to apply phone redaction, so quark values don't render as `***-***-1234`. Unrelated to the refactor but in the same branch.

6. **CLAUDE.md rules to re-read before touching code:**
   - Log message is a constant; variables go in `metadata`.
   - Test-support extensions live in the test target, not production.
   - No `print()` logging.
   - Use Swift Testing (`import Testing`), not XCTest.

7. **The PR is already open** (code-payments/code-ios-app#195). Updating it with pin-at-compute will need a new description. The current description mentions pinning through the flow — rewrite it to say the pin is fetched at compute-time.

8. **Session.assertFresh stays.** Even though fresh-at-compute is fresh by construction, `assertFresh` is defense-in-depth: the client's clock can drift or the server round-trip could take longer than expected. Leave it.

9. **`Session.Error.verifiedStateStale` (now payload-free) stays.** Same reason. Tests that catch it still work.

10. **No schema bump needed.** The schema changes on this branch already landed; pin-at-compute doesn't change the stored proto tables.

---

## Starting-point commit

At the time this plan was written, HEAD is `8c2522b6`:

```
8c2522b6 feat(ui): surface stale-pin reason in the amount-entry subtitle
d1598e2c refactor: drop two dead symbols found in post-branch sweep
33d995da test: tighten regression suite per swift-testing review
37f66787 fix(ui): re-pin on entry-currency change so amount-entry screens react
b1781982 fix(logging): stop treating integer amounts as phone numbers
0ebd7056 fix(rates): pinned state drives amount compute; simplify verified-proto plumbing
(… earlier commits on the branch)
```

Commits `37f66787` and `8c2522b6` are the re-pin + errorMessage work that pin-at-compute makes obsolete. Expect to revert most of those two commits as part of the migration — keep the subtitle plumbing if some other flow wants `.errorMessage` later, but delete if no caller needs it.

Don't rebase. New commits on top. The history is the history.
