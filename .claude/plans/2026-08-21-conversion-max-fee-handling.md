# Auto-correct the entry to the fee-affordable maximum (iOS mirror of Android #1302)

## Problem
Amount entry is capped at the RAW balance, but the fee comes out of that same balance:
- **fee on top** (funding side is Dollars — no launchpad sale to skim): debit = entered × (1 + f)
- **fee grossed up** (every other currency): debit = entered / (1 − f)

So entering the maximum always overruns by exactly the fee, never more. Today that surfaces as
a "Buy Maximum Amount" modal (Buy) or a hard failure at submit (Convert-from-Dollars).

## Findings (iOS specifics)
- `ConvertAmountViewModel.canPerformAction` gates on the raw balance only; from-Dollars charges
  1% on top (`ConvertConfirmationViewModel.totalDebited = amount + fee`), so converting the FULL
  Dollars balance passes the gate and hard-fails at submit. **Confirmed.**
- Convert *from a token* has the fee taken out of the entry (`totalDebited == amount`) — it
  cannot overrun, so no correction there.
- iOS entry state is a plain `String` bound straight into `EnterAmountView`/`KeyPadView`; there is
  **no** "prefill types on top" trap like Android's `AmountEntryDelegate`. Assigning the string
  replaces the entry. It does need rendering back into the keypad's locale-separator form.
- The Buy confirmation is a *separate pushed VM*; it cannot reach back to the entry. So the
  correction belongs in the **amount** view models, before pricing/pushing.

## Layers
1. `FiatAmount.flooredToSmallestUnit()` — truncate to `currency.maximumFractionDigits` via the
   existing `Decimal.roundedDown(to:)`. Floors, never rounds: $10.11/1.01 = $10.0099 → rounding up
   to $10.01 puts the debit ($10.1101) back over the balance.
2. Inverses beside the existing helpers in `ExchangedFiat+LaunchpadSellFee.swift`:
   - `FiatAmount.spendableUnderGrossedUpSellFee(bps:)` = balance × (1 − f)
   - `FiatAmount.spendableUnderSellFeeOnTop(bps:)`     = balance / (1 + f)
   Left **unrounded**, like `grossingUpLaunchpadSellFee` — the floor is an *entry-precision*
   concern, not the fiat→quark boundary, so it is applied by the entry helper instead.
3. `entryAffordableAfterFee(entered:balance:feeBps:feeChargedOnTop:) -> FiatAmount?` — pure, in
   FlipcashCore; returns nil when the entry already fits.
4. `AmountValidator.string(from:fractionDigits:)` — inverse of `validate`, so the corrected value
   is written back in the keypad's own separator convention.

## Call sites
- `BuyAmountViewModel.primaryAction` — correct before `computePaymentAmount`. Needs the
  `collectsUSDFFee` beta flag (fee-on-top only applies to the new-UI USDF buy).
- `ConvertAmountViewModel.showConfirmation` — correct when `sourceBalance.mint == .usdf`.
- Delete `BuyConfirmationViewModel.buyMaximum` + `showInsufficientBalance`'s Buy Maximum action
  and the appear-time auto-prompt (`presentInsufficientBalanceIfNeeded` + the screen's 0.35s task);
  the submit-time gate stays, as a plain error dialog.

## Parity
Fee math is a cross-platform hotspot: the correction, including the flooring, must agree exactly
with Android's `entryAffordableAfterFee` / `Fiat.flooredToSmallestUnit`.

## Outcome (shipped)
All four layers landed as planned, TDD throughout (six red→green cycles, 29 new tests):

| Suite | New |
|---|---|
| `FlipcashCoreTests/FeeAffordableEntryTests` | 8 (mirrors Android's cases 1:1) |
| `FlipcashCoreTests/LaunchpadSellFeeTests` | 4 inverse/round-trip |
| `FlipcashCoreTests/FiatAmountTests` | 3 flooring (incl. zero-decimal JPY) |
| `FlipcashCoreTests/AmountValidatorTests` | 4 `string(from:)` round-trip |
| `FlipcashTests/BuyAmountViewModelTests` | 4 correction (both fee branches) |
| `FlipcashTests/ConvertAmountViewModelTests` | 4 correction (new file) |

Removed with the modal: `BuyConfirmationViewModel.buyMaximum`,
`presentInsufficientBalanceIfNeeded`, the screen's 0.35s auto-prompt task and the
`paymentAmount` animation (nothing mutates it in place any more — it is now a `let`).
The submit-time gate remains as a plain "Insufficient Balance" error, reachable only when the
balance moves under a quote.
