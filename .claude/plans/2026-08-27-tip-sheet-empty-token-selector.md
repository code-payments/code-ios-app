# Send a Tip: empty token selector and a swipe that bounces back

Reported from a production screen recording: opening a tip card from a
`flipcash.com/<handle>` deep link showed the Send a Tip sheet with an empty
currency pill (bare chevron, no icon, no token name), and Swipe to Tip animated
to the end and reset without sending or showing an error.

## Root cause

`SendAmountViewModel.selectedBalance` was nil and never re-resolved.

`SendAmountViewModel.init` called `RatesController.resolveInitialBalance(mint:session:)`
once and stored the result. Only `selectCurrencyAction(exchangedBalance:)` ever
reassigned it, so a resolve that came up empty stayed empty for the life of the
view model.

`TipFlow.present(_:)` builds that view model at the earliest, coldest instant of
the deep-link flow — before `ensureStreamConnected()` has delivered a rate and
before the 750 ms the flow itself waits out before deciding whether to show the
sheet. `resolveInitialBalance` snapshots `session.balances` at that instant, and
on a cold launch that list can still be empty.

Four observations from the recording line up with that:

1. The pill renders `CurrencyLabel(imageURL: selectedBalance?.stored.imageURL, name: selectedBalance?.stored.name ?? "")` — no icon and no name means the balance is nil, not that the icon failed to load.
2. The swipe bounced with no dialog. `SwipeControl.commit` catches and resets on any throw; `TipFlow.swipeToTip` throws `TipDismissed` on `.failed`; and the `selectedBalance` guard was the only `.failed` in `submit(entered:)` that set no `session.dialogItem`.
3. The preset chips still rendered, because they come from `session.userFlags?.tipPresets(for:)` and never touch `selectedBalance`.
4. The sheet appeared at all, so `giveCashGate` returned `.proceed` at t+750 ms. `giveable().isEmpty` is set-equivalent to `!session.hasGiveableBalance(for:)`, so balances were usable 750 ms after the view model had already frozen at nil.

A $1 custom amount was also accepted against $5/$10/$20 presets. That is
consistent with `enforceTipMinimum` taking its `selectedBalance == nil`
early-return, but it is not proof — `TipPresets.minimum` is a separate field from
the three tiers and may legitimately be at or below $1.

### What makes an empty snapshot realistic in the wild

- `Session.updateableBalances` is an `Updateable` cache, re-queried only on `.databaseDidChange`.
- `Database.getBalances()` maps rows with `try statement.map { try StoredBalance(...) }`, so one throwing row aborts the whole query; `(try? database.getBalances()) ?? []` then collapses that to an empty list app-wide until the next database change. `StoredBalance.init` throws `missingStoredCoreMintForNonReserveToken` when a `LEFT JOIN mint` miss leaves `supplyFromBonding` nil on a non-USDF symbol.
- A bonded mint with nil or zero `supplyFromBonding` computes to `safeZero` and is filtered out of `Session.balances(for:)`.

## Fix

`Flipcash/Core/Screens/Send/SendAmountViewModel.swift`:

- When the initial resolve returns nil, arm a re-arming `withObservationTracking`
  loop over `session.balances` and `ratesController.rateForBalanceCurrency()` and
  re-run `resolveInitialBalance` on each change until it lands. It stops once a
  balance resolves or the user picks one, so an explicit pick is never
  overwritten. This mirrors `Session.observeBalanceCurrencyChanges()`.
- The `selectedBalance` / `enteredFiat` guard in `submit(entered:)` now reports
  through `ErrorReporting.captureError` and sets a `session.dialogItem` instead
  of returning `.failed` silently. That branch involves no RPC and no thrown
  error, so it was invisible to both the user and Bugsnag — which is why this
  reached production.

Tests in `FlipcashTests/SendAmountViewModelTests.swift`, both observed failing
against the unfixed code:

- `testInit_NoBalancesYet_ResolvesWhenBalancesArrive` — builds the view model
  against an empty database, inserts a launchpad balance, posts
  `.databaseDidChange`, and expects `selectedBalance` to resolve.
- `submit_noSelectedBalance_surfacesDialog` — expects the dialog rather than a
  silent `.failed`.
- `testInit_ExplicitPick_SurvivesLateBalanceArrival` guards the stop condition.

## Not changed

`GiveViewModel` (`Flipcash/Core/Screens/Main/GiveViewModel.swift:56`) resolves its
balance the same one-shot way. The Give flow is entered from an already-warm
wallet screen rather than from a cold deep link, so it is far less exposed, but
the pattern is identical and worth revisiting.
