# Delete `Quarks`

**Branch:** `refactor/delete-quarks` (chained off `fix/exchanged-fiat-underlying-decimals`)
**Goal:** remove `Quarks` from the active codebase. Every consumer migrates to `FiatAmount` (fiat values) or `TokenAmount` (on-chain integers). Type-safe by construction; no behavior change.

## Why

`Quarks` is a legacy single type that conflated two roles — a fiat-denominated decimal scaled to a per-currency quark integer, AND an on-chain token integer. The earlier type-split (`fix/exchanged-fiat-underlying-decimals`) introduced `FiatAmount` and `TokenAmount` for those two roles separately. ~30 active consumers still use `Quarks`. Each maps cleanly to one of the new types. Keeping `Quarks` around long-term invites accidental re-conflation; deleting it locks in the type-safe split.

## Audit

39 files reference `Quarks` outside the type definition. Categorized:

### → `FiatAmount` (server-provided fiat / display values)

| File | Symbol | Migration |
|---|---|---|
| `FlipcashCore/.../Models/Limits.swift` | `SendLimit.{nextTransaction,maxPerTransaction,maxPerDay}: Quarks` | `FiatAmount` |
| `Flipcash/Core/Controllers/Database/Models/StoredBalance.swift` | `usdf: Quarks` | `FiatAmount` (`currency: .usd`) |
| `Flipcash/UI/EnterAmountCalculator.swift` | `maxTransactionAmount: Quarks?`, `isWithinDisplayLimit(max: Quarks)` | `FiatAmount` |
| `Flipcash/Core/Screens/Settings/WithdrawViewModel.swift` | `displayFee: Quarks?`, `negativeWithdrawableAmount: Quarks?` | `FiatAmount?` |
| `Flipcash/Core/Screens/Settings/WithdrawSummaryScreen.swift` | display | `FiatAmount` |
| `Flipcash/Core/Screens/Main/Bill/Toast.swift` | `amount: Quarks` | `FiatAmount` |
| `Flipcash/Core/Screens/Main/SelectCurrencyScreen.swift` | `amount: Quarks?` (display) | `FiatAmount?` |
| `Flipcash/Core/Screens/Main/Modals/ModalCashReceived.swift` | `fiat: Quarks` (display) | `FiatAmount` |
| `Flipcash/Core/Screens/Main/BalanceScreen.swift` | display | `FiatAmount` |
| `Flipcash/Core/Screens/Main/Currency Info/CurrencyInfoViewModel.swift` | `balance: Quarks`, `marketCap: Quarks`, `appreciation` tuple | `FiatAmount` |
| `Flipcash/Core/Screens/Main/Currency Info/CurrencyInfoHeaderSection.swift` | `balance: Quarks` | `FiatAmount` |
| `Flipcash/Core/Screens/Main/Currency Info/CurrencyInfoMarketCapSection.swift` | `marketCap: Quarks` | `FiatAmount` |
| `Flipcash/Core/Screens/Main/Currency Creation/CurrencyCreationWizardScreen.swift` | `previewFiat: Quarks` | `FiatAmount` |
| `Flipcash/Core/Screens/Main/Currency Creation/CurrencyLaunchProcessingViewModel.swift` | check on touch | likely `FiatAmount` |
| `Flipcash/Core/Controllers/RatesController.swift` | `exchangedFiat(for amount: Quarks)` | `FiatAmount` |
| `Flipcash/Core/Controllers/Deep Links/Wallet/EnterWalletAmountScreen.swift` | private state | `FiatAmount?` |
| `Flipcash/Core/Controllers/Onramp/OnrampCoordinator.swift` | check on touch | likely `FiatAmount` |
| `Flipcash/Utilities/Events.swift` | 4 analytics fns: `transfer`, `onrampInvokePayment`, `onrampCompleted`, `walletRequestAmount` | `FiatAmount`/`FiatAmount?` |
| `Flipcash/Utilities/ErrorReporting.swift` | `breadcrumb(fiat:)`, `capturePayment(fiat:)` | `FiatAmount`/`FiatAmount?` |
| `FlipcashUI/.../ValueAppreciation.swift` | `amount: Quarks` (display) | `FiatAmount` |
| `FlipcashUI/.../Bill/BillView.swift` | `fiat: Quarks` (display) | `FiatAmount` |

### → `TokenAmount` (on-chain integers)

| File | Symbol | Migration |
|---|---|---|
| `FlipcashCore/.../Models/UserFlags.swift` | `newCurrencyPurchaseAmount: Quarks` | `TokenAmount` (mint = `.usdf`) |
| `Flipcash/Core/Controllers/Deep Links/Wallet/WalletConnection.swift` | `requestSwap(usdc: Quarks, …)` | `TokenAmount` (mint = `.usdf`) |
| `FlipcashCore/.../Services/TransactionService.swift:713` | `PoolDistribution.amount: Quarks` | `TokenAmount` (pools deprecated; check whether the type is even used) |

### Special cases

| File | Note |
|---|---|
| `Flipcash/Core/Screens/Main/Bill/CashCode.Payload.swift` + `…+Encoding.swift` | Wire-binary encoder. The on-the-wire `fiat` field is a fixed 6-decimal quark integer regardless of `currency.maximumFractionDigits`. After Quarks deletion we cannot use `FiatAmount.asQuarks` (which scales by `currency.maximumFractionDigits`, e.g. 2 for USD). Convert at the encoder boundary using `Decimal.scaleUpInt(6)` directly. Add a `static let wireDecimals = 6` constant in `CashCode.Payload`. Stored in-memory as `FiatAmount`. |
| `FlipcashCore/.../Utilities/CompactMessage.swift` | `mutating func append(fiat: Quarks)` is the legacy method; `append(amount: TokenAmount)` already exists from the prior commit. **Delete `append(fiat:)`** — no remaining callers. |
| `FlipcashCore/.../Models/FiatAmount.swift` | `asQuarks` extension: **delete**. The bridge is no longer needed once consumers move off `Quarks`. |
| `FlipcashCore/.../Models/DiscreteBondingCurve.swift` | Only mentions "quarks" in docstrings (parameter naming, comments). Leave docstrings as-is — the word "quarks" is meaningful (token-quark integers). |
| `FlipcashCore/.../Services/AccountInfoService.swift`, `Client+Account.swift` | `fetchLinkedAccountBalance` returns `Quarks`. Per the simplify reuse agent, no callers in the active codebase. **Delete the dead method** if confirmed (do this as part of the migration; if anyone calls it, switch to `TokenAmount` since balances are mint-native). |
| `FlipcashTests/QuarksDisplayTests.swift` | Rename / rewrite as `FiatAmountDisplayTests.swift`. |
| `FlipcashTests/FiatTests.swift` | Currently tests `Quarks`. Rewrite as `FiatAmountTests.swift` covering the same surface (formatting, currency decimal places). |
| `FlipcashTests/UInt64OperationsTests.swift` | Tests `UInt64.scaleDown/scaleUp`. Both still used by `TokenAmount` and the wire encoder. **Keep.** |
| `FlipcashTests/CashCodeEncodingTests.swift` | Round-trip test — migrate fixture from `Quarks` to `FiatAmount`. |
| `FlipcashTests/SessionTests.swift`, `EnterAmountCalculatorTests.swift`, `CurrencyInfoScreenTests.swift`, `Regression_sell_jpy_red_limit.swift` | Test fixtures using `Quarks` — mechanical migration to `FiatAmount`. |

## Strategy

Bottom-up: types and producers first (Limits, StoredBalance, RatesController, BillView/ModalCashReceived/Toast public APIs), then view models and screens, then analytics/error reporting, then tests, then delete `Quarks.swift`. The compiler walks us through each step.

After each substantial change: build to surface errors. Don't batch unrelated migrations into one edit.

### Order

1. **Producers in FlipcashCore** — `Limits.swift`, `RatesController.swift` (lives in app, but is the producer of cached rates → fiat), `StoredBalance.swift`. These are the data source side.
2. **`UserFlags.swift`** + `WalletConnection.swift` `requestSwap(usdc:)` — `TokenAmount` migrations.
3. **Public UI API surfaces** in FlipcashUI: `BillView`, `ValueAppreciation`. These ripple into many screens.
4. **`ModalCashReceived`, `Toast`, `SelectCurrencyScreen`** — display sites in Flipcash.
5. **View models** — `WithdrawViewModel`, `CurrencyInfoViewModel`, `CurrencyCreationWizardScreen`, `EnterAmountCalculator`, etc.
6. **Analytics + error reporting** — `Events.swift`, `ErrorReporting.swift`. These are leaf functions; many call sites.
7. **`CashCode.Payload`** — wire format. Convert encoder to `FiatAmount` + explicit 6-decimal scaling.
8. **`CompactMessage.append(fiat:)`** — delete the legacy method.
9. **Tests** — migrate fixtures. Rename `QuarksDisplayTests` → `FiatAmountDisplayTests`. Rewrite `FiatTests` → `FiatAmountTests`.
10. **`FiatAmount.asQuarks`** — delete.
11. **`Quarks.swift`** — delete.

## `formatted()` parity check

`Quarks.formatted(suffix:)` calls `NumberFormatter.fiat(currency:minimumFractionDigits:maximumFractionDigits:truncated:suffix:)` with `currencyCode.maximumFractionDigits` and feeds `decimalValue` (a `Decimal`).

`FiatAmount.formatted(suffix:)` calls the same `NumberFormatter.fiat(...)` with the same `currency.maximumFractionDigits` and feeds `value` (a `Decimal`).

Same code path, same parameters. Output is identical.

The one place `Quarks` could differ from `FiatAmount` is when a `Quarks` instance has `decimals > maximumFractionDigits`: `decimalValue` would carry more precision than the formatter actually displays. But the formatter rounds at `maximumFractionDigits` regardless, so the displayed string is the same. No parity test needed.

## CashCode wire format

Current: `Quarks.quarks` (a UInt64 at 6-decimal scale, regardless of `currencyCode`) encoded as 7 bytes. Decode reads the UInt64 + currency byte, reconstructs `Quarks(quarks:, currencyCode:, decimals: 6)`.

After: `FiatAmount` stored. Encode does `let quarks = fiat.value.scaleUpInt(CashCode.Payload.wireDecimals)`. Decode does `FiatAmount(value: UInt64(quarks).scaleDown(CashCode.Payload.wireDecimals), currency: …)`. Uses the same `Decimal+Operations.scaleUpInt` / `UInt64+Operations.scaleDown` extensions that `Quarks` itself used.

`wireDecimals = 6` becomes a named constant on `CashCode.Payload`, replacing the magic number in the decoder.

## Success criteria

1. `xcodebuild build -scheme Flipcash -destination 'generic/platform=iOS'` → `BUILD SUCCEEDED`.
2. `xcodebuild build-for-testing -scheme Flipcash -destination 'platform=iOS Simulator,name=iPhone 17'` → `TEST BUILD SUCCEEDED`.
3. `grep -rn "\\bQuarks\\b" Flipcash FlipcashCore FlipcashUI FlipcashTests --include="*.swift"` returns nothing.
4. `Quarks.swift` deleted.
5. `FiatAmount.asQuarks` deleted.
6. `CompactMessage.append(fiat:)` deleted.
7. Manual smoke test on bonded-mint flows still passes (no display regression).

## Branch / upstream safety

`refactor/delete-quarks` chained off `fix/exchanged-fiat-underlying-decimals`. Both unset at creation:
- `branch.refactor/delete-quarks.merge` — unset
- `branch.refactor/delete-quarks.remote` — unset

First push: `git push -u origin refactor/delete-quarks`. **Not** a bare `git push`. Same risk profile as the parent branch (several locally-misconfigured branches in this repo with `merge = refs/heads/main`).

Once the parent branch merges, this branch rebases onto main cleanly (the parent has nothing to do with `Quarks` removal beyond the prior cleanup).

## Out of scope

- Performance optimizations (`Session.balances` caching, view model memoization) — separate.
- `Quarks` consumers in `Code/`, `Flipchat/`, `CodeServices/`, `FlipchatServices/` — those are legacy packages with their own `Quarks`, untouched.
- Behavior changes — this is a pure type-system refactor.
- Adding `screenshot` or visual snapshot tests — no infra in this codebase, out of scope.
