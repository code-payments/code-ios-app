# Give & Cash Link: pin-at-compute migration

**Date:** 2026-04-28
**Status:** Plan, awaiting approval
**Incident:** `invalidIntent(native amount does not match expected sell value)` from Bugsnag, 1.5.0
**Prior context:** PR #195 (`1674e6ef`) shipped pin-at-compute for Buy / Sell / Withdraw. Give was not migrated.

---

## What the report tells us

```
Resolved verified state currency=usd hasReserveProof=true mint=4muA…pxz6 rate=1.0 rateAgeSec=23.5 reserveAgeSec=3.5 source=cache-hit
Sending request to give bill mint=4muA…pxz6 rendezvous=4NsX…478r
Sending cash link amount=$5.00 USDF giftCardVault=GKsn…aN4z
Submitting intent intentId=4NsX…478r type=IntentSendCashLink
Action Transfer destination=GKsn…aN4z index=1 quarks=332711934725
Intent submission error code=invalidIntent detailCount=1 intentId=4NsX…478r type=IntentSendCashLink
Failed to send cash link error=invalidIntent(native amount does not match expected sell value)
```

- The bill is for a **launchpad currency** (`hasReserveProof=true`). Bonding-curve math means quarks ↔ native depends on **both** rate and supply.
- Sub-second between bill display and cash-link submission, but **the live mint stream emits supply updates continuously**. Any stream tick between amount entry and `createCashLink` flips the supply that gets paired with quarks computed against an older one.
- 332,711,934,725 quarks ≈ 33.27 tokens — only meaningful through the curve.

## Root cause: `createCashLink` re-fetches a fresh proof and pairs it with stale quarks

Source data path on `main`:

1. `GiveScreen.nextAction` (`GiveScreen.swift:128`) → `GiveViewModel.giveAction` (`GiveViewModel.swift:134`).
2. `enteredFiat` is built from **live** `ratesController.rateForEntryCurrency()` + **live** `selectedBalance.stored.supplyFromBonding` (`GiveViewModel.swift:35-89`).
3. `Session.showCashBill(.init(kind: .cash, exchangedFiat: amountToSend, received: false))` — `verifiedState: nil` for outgoing bills (`GiveViewModel.swift:159-165`).
4. User taps "Send as a Link" → `primaryAction` closure (`Session.swift:935`) calls `createCashLink(payload:exchangedFiat:)`.
5. **`Session.createCashLink` re-fetches a *new* proof** via `ratesController.awaitVerifiedState(...)` (`Session.swift:1181-1186`) and submits it alongside the older-rate `exchangedFiat.onChainAmount.quarks`.
6. Server validates `bondingCurve.sell(quarks, supply=reserveProto.supply) × rateProto.exchangeRate ≈ exchangedFiat.nativeAmount`. (live rate × live supply at step 2) ≠ (rate × supply at step 5) → reject.

The fix from PR #195 lives in `prepareSubmission()` on Buy/Sell/Withdraw view models — it pins **once**, derives quarks against the pinned rate (and supply, for bonded), and hands both to `Session.*`. CLAUDE.md documents this as the **pin-at-compute invariant**:

> Fetching twice or pinning at flow-open reintroduces the "native amount and quark value mismatch" reject.

`createCashLink` is exactly the second fetch.

## The face-to-face Give path has the same defect (but a smaller blast radius)

Even without "Send as a Link", `SendCashOperation.run` (`SendCashOperation.swift:143`) calls `resolveAndLogVerifiedState`, which falls back to `ratesController.getVerifiedState` when `providedVerifiedState == nil`. Since outgoing bills currently pass `nil`, the same drift exists for face-to-face transfer. We don't have a Bugsnag for this path because the time window between bill-show and someone scanning is usually long enough for the stream to deliver a fresh proof and `Pin-at-compute` failures may have been masked or chalked up to "user retried." Once `BillDescription.verifiedState` carries the pin, `SendCashOperation.providedVerifiedState` is set and the rest of `SendCashOperation` already uses it correctly — no other change needed there.

## Fix plan

Mirror the Buy / Sell / Withdraw shape exactly. One pin, computed against, carried through.

### 1. `GiveViewModel.prepareSubmission()` (new)

Pins `(entryCurrency, mint)` and computes the bill amount against `pin.rate` + `pin.supplyFromBonding`. Returns `nil` when no fresh pin is cached — caller surfaces `DialogItem.staleRate` exactly like the Buy/Sell/Withdraw flows.

```swift
func prepareSubmission() async -> (amount: ExchangedFiat, pinnedState: VerifiedState)? {
    guard let selectedBalance else { return nil }
    let mint = selectedBalance.stored.mint

    guard let pin = await ratesController.currentPinnedState(
        for: ratesController.entryCurrency,
        mint: mint
    ) else { return nil }

    guard !enteredAmount.isEmpty,
          let entered = NumberFormatter.decimal(from: enteredAmount),
          entered > 0 else { return nil }

    // Give already filters .usdf out in `refreshSelectedBalance`, so reaching
    // this point implies bonded → supplyFromBonding must be present.
    guard let pinnedSupply = pin.supplyFromBonding else { return nil }

    let nativeEntered = FiatAmount(value: entered, currency: pin.rate.currency)
    let balance = session.balance(for: mint)

    guard let amount = ExchangedFiat.compute(
        fromEntered: nativeEntered,
        rate: pin.rate,
        mint: mint,
        supplyQuarks: pinnedSupply,
        balance: balance.map(\.usdf),
        tokenBalanceQuarks: balance?.quarks
    ) else { return nil }

    return (amount, pin)
}
```

`enteredFiat` (the live preview / `canGive` / `hasSufficientFunds` input) stays as-is.

### 2. `GiveViewModel.giveAction()` calls prepareSubmission at commit

The live `hasSufficientFunds` check stays — it's the user-visible balance gate, and `enteredFiat` is what's on screen. After it returns `.sufficient`, prepare a pinned amount and present the bill with the pin attached.

```swift
func giveAction() {
    guard let exchangedFiat = enteredFiat else { return }

    switch session.hasSufficientFunds(for: exchangedFiat) {
    case .sufficient:
        Task {
            guard let (amountToSend, pinnedState) = await prepareSubmission() else {
                dialogItem = .staleRate
                return
            }

            let sendLimit = session.sendLimitFor(currency: amountToSend.nativeAmount.currency) ?? .zero
            guard amountToSend.nativeAmount.value <= sendLimit.nextTransaction.value else {
                logger.info("Give rejected: amount exceeds limit", metadata: [
                    "amount": "\(amountToSend.nativeAmount.formatted())",
                    "next_tx": "\(sendLimit.nextTransaction.value)",
                    "currency": "\(amountToSend.nativeAmount.currency)",
                ])
                showLimitsError()
                return
            }

            isPresented = false
            try await Task.delay(milliseconds: 50)

            session.showCashBill(.init(
                kind: .cash,
                exchangedFiat: amountToSend,
                received: false,
                verifiedState: pinnedState
            ))
        }

    case .insufficient(let shortfall):
        if let shortfall { showYoureShortError(amount: shortfall) }
        else { showInsufficientBalanceError() }
    }
}
```

A side effect of this restructure: the existing live max-send tolerance branch in `Session.hasSufficientFunds` (which returned `exchangedBalance` recomputed at live rate) goes away for Give. The pinned `compute` already has `balance:` and `tokenBalanceQuarks:` caps that do the same job in pinned space, like `CurrencySellViewModel`. Behaviour is the same — "max send" still works — but capped to the pin instead of the live rate.

### 3. `Session.createCashLink` accepts and uses the pin (no re-fetch)

```swift
private func createCashLink(
    payload: CashCode.Payload,
    exchangedFiat: ExchangedFiat,
    verifiedState: VerifiedState
) async throws -> GiftCardCluster {
    do {
        var vmAuthority = PublicKey.usdcAuthority
        var owner = owner

        if owner.timelock.mint != exchangedFiat.mint {
            guard let authority = try? database.getVMAuthority(mint: exchangedFiat.mint) else {
                throw Error.vmMetadataMissing
            }
            vmAuthority = authority
            owner = owner.use(mint: exchangedFiat.mint, timeAuthority: authority)
        }

        let giftCard = GiftCardCluster(mint: exchangedFiat.mint, timeAuthority: vmAuthority)

        try await client.sendCashLink(
            exchangedFiat: exchangedFiat,
            verifiedState: verifiedState,
            ownerCluster: owner,
            giftCard: giftCard,
            rendezvous: payload.rendezvous.publicKey
        )

        Analytics.transfer(event: .sendCashLink, exchangedFiat: exchangedFiat, grabTime: nil, successful: true, error: nil)
        return giftCard
    } catch {
        ErrorReporting.captureError(error)
        Analytics.transfer(event: .sendCashLink, exchangedFiat: exchangedFiat, grabTime: nil, successful: false, error: error)
        throw error
    }
}
```

The `awaitVerifiedState` polling block is gone — by construction, GiveViewModel pinned a fresh state at submit-time. The earlier polling existed only because the bill could be tapped before the cold-launch warm-load delivered any rates; pin-at-commit makes that impossible (no pin → `.staleRate` dialog at amount entry, never reaches the bill).

### 4. `Session.showCashBill` primaryAction passes the pin through

```swift
let giftCard = try await self.createCashLink(
    payload: payload,
    exchangedFiat: exchangedFiat,
    verifiedState: billDescription.verifiedState ?? <pin from operation provider>
)
```

`BillDescription.verifiedState` is currently optional. Two ways to handle the optionality:

- **Option A — Tighten the type.** Make `BillDescription.verifiedState` non-optional. Force every caller (`GiveViewModel`, `receiveCash`, `receiveCashLink`, `CurrencyLaunchProcessingViewModel.prepareBillHandoff`) to provide one. Cleanest, but `receiveCashLink` only has access to it after a poll that may time out — making it required means we'd have to delay or fail the receive flow on cache miss.

- **Option B — Make it required only on the outgoing path.** Keep `BillDescription.verifiedState` optional, but assert non-nil inside the `primaryAction` closure (which only runs for outgoing bills — `received` bills set `primaryAction = nil` at `Session.swift:1005`). If somehow nil, log + fail the action with a generic error rather than re-fetching.

Option B is the lower-risk fix; receive-path behaviour stays unchanged. If we later want to tighten, we can introduce a sub-type (`BillDescription.OutgoingVariant` with required `verifiedState`).

### 5. Tests

Extend `Regression_native_amount_mismatch.swift` (the suite is named after the exact server error) with **Scenario G (give)**:

1. *Pinned rate + pinned supply produce different quarks than live cache* — same shape as the existing Sell scenario, asserting `submission.amount.currencyRate.fx == pinnedRate` and `submission.pinnedState.supplyFromBonding == pinnedSupply`.
2. *No pin → `prepareSubmission` returns nil* — same shape as the existing Scenario E (sell).

No new `Session.createCashLink` test — its path is just plumbing once the pin is required. (Optional: a small unit asserting that `createCashLink` does not call `ratesController.awaitVerifiedState`, but that's overspecified.)

### What stays untouched

- `SendCashOperation` — already uses `providedVerifiedState` if non-nil. Once `BillDescription.verifiedState` is set for outgoing bills, the face-to-face transfer path uses the pin with no code change there.
- `receiveCash` / `receiveCashLink` — already pass `verifiedState` through. No drift.
- The `CurrencyLaunchProcessingViewModel.prepareBillHandoff → showCashBill` path — already passes a pin if available (need to spot-check the current implementation, but it's outside the scope of this report's stack trace).

## Sequencing

1. Branch `fix/give-pin-at-compute` from `main`.
2. Add `GiveViewModel.prepareSubmission` + `.staleRate` dialog wiring.
3. Update `GiveViewModel.giveAction` to call `prepareSubmission` and pass pin in `BillDescription`.
4. Update `Session.createCashLink` signature; remove the inner `awaitVerifiedState`.
5. Update `Session.showCashBill` primaryAction to forward `billDescription.verifiedState`.
6. Add Scenario G tests to `Regression_native_amount_mismatch.swift`.
7. Run targeted suites (`FlipcashTests/Regressions/Regression_native_amount_mismatch`, `GiveViewModelTests` if present, `SessionTests` for the cash-link path).
8. Build the app to verify no warnings introduced.

User runs `AllTargets` before approving the commit.
