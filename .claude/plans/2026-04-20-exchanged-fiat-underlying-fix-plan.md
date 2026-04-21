# ExchangedFiat — type split (landed)

**Branch:** `fix/exchanged-fiat-underlying-decimals`
**Status:** landed in commit `1f55406b` plus follow-up cleanup. Both app build and test build green. Manual on-device testing of bonded-mint flows still required before push.
**Paired investigation:** `2026-04-20-android-underlying-investigation.md`

This plan documents the *as-shipped* state. It is a durable reference, not a forward-looking proposal — earlier drafts (V1 "tweak the decimals", V2 "add a TokenAmount but keep Quarks", V3 "stored usdfValue + supply plumbing") were superseded by the simpler design below. Conversations that produced the change are recorded in the git history of this file and the original investigation doc.

---

## Why this exists

`ExchangedFiat.underlying: Quarks` was used for two different things:

1. The mint-native on-chain integer (Solana SPL transfer amount, `proto.quarks`).
2. A USD-equivalent value (`underlying.formatted()` shown as "USDC", analytics `usdc` properties, balance comparisons in USD).

For USDF mints both interpretations coincide (USDF has 6 decimals). For bonded currency mints (10 decimals), `underlying.quarks` carried token-native quarks but `underlying.currencyCode == .usd` claimed USD. Display, analytics, totals, and balance compares were silently wrong for bonded mints by 10⁴ or were measuring tokens-as-dollars.

The wire format and on-chain semantics were already correct — server and chain expected mint-native quarks, and that is what was being sent. Only the *client-side* dual-meaning of `underlying` was broken. Android (`code-android-app`) carries the same bug in its `LocalFiat.underlyingTokenAmount`.

## Design — mirror the proto

The server's `ExchangeData` proto already separates the two concerns:

```proto
message ExchangeData {
    bytes  mint;
    uint64 quarks;        // mint-native integer
    double nativeAmount;  // fiat decimal value
    string currency;      // fiat currency code
    double exchangeRate;  // native-per-USD
}
```

The client now mirrors this with two concrete types and a restructured `ExchangedFiat`:

```swift
public struct TokenAmount: Equatable, Hashable, Codable, Sendable {
    public let quarks: UInt64
    public let mint: PublicKey
    public var decimalValue: Decimal { quarks.scaleDown(mint.mintDecimals) }
    public var decimals: Int { mint.mintDecimals }
    // No currencyCode — the mint is the identity.
    // Operators: `-`, `<` (Comparable). Same-mint precondition.
    // Factories: .init(quarks:mint:), .init(wholeTokens:mint:), .zero(mint:).
}

public struct FiatAmount: Equatable, Hashable, Codable, Sendable {
    public let value: Decimal
    public let currency: CurrencyCode
    // No `decimals` field — scaling is not a fiat concern.
    // Operators: `+`, `-`, `*` (by Decimal), `<`. Same-currency precondition.
    // Conversion: .converting(to: Rate) (self USD), .convertingToUSD(rate:) (self native).
    // Factories: .init(value:currency:), .zero(in:), .usd(_:).
    // Helpers: .formatted(suffix:), .hasDisplayableValue, .isApproximatelyZero.
    // Bridge: .asQuarks (Quarks at currency.maximumFractionDigits, never throws).
}

public struct ExchangedFiat: Equatable, Hashable, Codable, Sendable {
    public let onChainAmount: TokenAmount   // → SPL transfer + proto.quarks
    public let nativeAmount:  FiatAmount    // → user's fiat
    public let currencyRate:  Rate          // always native-per-USD

    public var mint: PublicKey { onChainAmount.mint }

    /// USD-denominated equivalent — derived, not stored.
    public var usdfValue: FiatAmount {
        nativeAmount.convertingToUSD(rate: currencyRate)
    }
}
```

`Quarks` is preserved as a fiat-only legacy type for the call sites that haven't been migrated yet (limits, balances, fee proto fields, view model display caps). It no longer carries the mint-native meaning that started this whole bug.

### What `usdfValue` being computed buys us

- No supply plumbing into the view layer. No `subtractingFee(_, supplyQuarks:)`. No `usdfQuarks` SQLite column. No "compute returned safeZero because supply was nil" trap.
- `subtractingFee(_ fee: TokenAmount)` is one parameter — proportional scaling of `nativeAmount` by `(remaining/total)`. For bonded fees this is an O(bps) approximation of the curve; deviation is below display rounding.
- Proto round-trips don't need supply: `Ocp_Transaction_V1_ExchangeData` has `exchangeRate`, so the client builds `(onChainAmount, nativeAmount, currencyRate)` directly from proto fields.

### What `currencyRate` being native-per-USD buys us

The earlier `computeFromQuarks` for bonded mints synthesized a per-token rate (`netUSDF / wholeTokens × inputRate.fx` = CAD-per-token) and stored it in `rate.fx`. Display sites that read `.rate.fx` got per-token values for bonded activities, currency-FX values for USDF — silently shape-shifting. The new model never produces that synthesis. Per-token price is an explicit derivation when needed (no current consumer; the helper was removed as orphan).

## Constraints honored

- **Wire format unchanged.** `proto.quarks` still carries mint-native integers. Server, chain, and Android client see the same bytes as before.
- **Android parity preserved on the wire.** Android still has the same client-side display bug we just fixed; we lead, they can follow.
- **`SQLiteVersion` bumped to 10.** Activity rows rebuild on next login (per `SessionAuthenticator.initializeDatabase`). Schema columns unchanged from pre-refactor: `quarks + nativeAmount + currency + mint`. FX is synthesized on read from `nativeAmount / onChainAmount.decimalValue` — for USDF that's the correct currency FX; for bonded it's a per-token rate (pre-existing behavior, only affects the `.rate.fx` display surface).
- **No new abstractions for hypothetical future needs.** Operators added on demand only: `TokenAmount` has `-` and `<`; `FiatAmount` has `+`, `-`, `*`, `<`. Speculative `+=`/`-=`, `/`, integer/float literal conformances, and `TokenAmount + ` were removed during cleanup as unused.

## Migration scope (as shipped)

- ~80 files modified in the main commit.
- Net delta after cleanup: ~+200 lines new types / docs, ~−500 lines removed dead Quarks API and `(try? Quarks(...)) ?? Quarks.zero(...)` bridge boilerplate (replaced by `.asQuarks` helper).
- 1 deleted regression test (`Regression_698ef3b65e6cc4bb5554e13d`) — guarded against a Quarks cross-decimal overflow that is structurally impossible now.

### Bridge helper

`extension FiatAmount { var asQuarks: Quarks }` lives in `FiatAmount.swift`. Returns a `Quarks` at `currency.maximumFractionDigits`. Used wherever the legacy `Quarks` type is still required as input (toast amounts, payload encoder, fiat display in `EnterAmountCalculator`, view model display caps). The 11 sites that previously used the `try?/?? zero` 6-line pattern are now one-liners.

## Known issues NOT addressed in this branch

These were flagged by the cleanup-pass review and are deliberately left for follow-up PRs (out of scope for "fix the load-bearing bug"):

| Issue | Where | Why deferred |
|---|---|---|
| `bps: 100` hardcoded sell fee | `CurrencySellConfirmationViewModel.swift:25` | Pre-existing. `MintMetadata.sellFeeBps` exists; should read from there. Not introduced by this refactor. |
| `print(...)` calls | `Session.swift:402, 838` | Pre-existing (Nov 2025, Dima). User memory says no print logging. |
| `Quarks` could be removed entirely | Codebase-wide | Real opportunity — every remaining `Quarks` consumer maps cleanly to `FiatAmount` (limits, balances, display) or `TokenAmount` (fees, payload encoder). Roughly 25 sites. Worth a dedicated PR. |
| `Session.balances` re-sorts on every read | `Session.swift:140-170` | Performance, unrelated to type split. Caching `[PublicKey: StoredBalance]` would remove repeated O(N log N) per view eval. |
| View model computed properties run bonding-curve calls per body eval | `CurrencyInfoViewModel`, `CurrencySellViewModel`, `CurrencyBuyViewModel` | Performance. Consider materializing into stored properties invalidated on input change. |
| Activity bonded display shows per-token rate | `Database+Activities.swift` read path | Pre-existing. Schema lacks `exchangeRate` column. To fix, add a column to mirror the proto. |
| `StoredBalance.usdf: Quarks` could be `FiatAmount` (computed from quarks + supply) | `Flipcash/Core/Controllers/Database/Models/StoredBalance.swift` | The DB read path silently swallows the throw at construction. Worth fixing alongside the broader Quarks elimination. |
| `Session.hasSufficientFunds` shortfall passes `supplyQuarks: nil` for bonded | `Session.swift:405-409` | For bonded mints the shortfall's `nativeAmount` will be `0`. Functional but wrong on display. Fix when caching balances (the supply is already on `StoredBalance`). |

## Branch upstream safety

Branch `fix/exchanged-fiat-underlying-decimals` was created with `--no-track`. Verified at creation:

- `branch.fix/exchanged-fiat-underlying-decimals.merge` — unset
- `branch.fix/exchanged-fiat-underlying-decimals.remote` — unset

First push **must** be `git push -u origin fix/exchanged-fiat-underlying-decimals`. Repo has several locally-misconfigured branches with `merge = refs/heads/main` (e.g. `claude/gallant-montalcini`, `sharp-tu`, `amazing-edison`, `fix/currency-wizard-summary-keyboard-bounce`) — that's what caused the prior `fix/onramp-*` push to land on main. This branch is clean.

Before each subsequent push, verify `git config --get branch.fix/exchanged-fiat-underlying-decimals.merge` returns `refs/heads/fix/exchanged-fiat-underlying-decimals`.

## Verification status

- ✅ `xcodebuild build -scheme Flipcash -destination 'generic/platform=iOS'` — succeeds.
- ✅ `xcodebuild build-for-testing -scheme Flipcash -destination 'platform=iOS Simulator,name=iPhone 17'` — succeeds.
- ✅ Concurrency: new types are pure-value `Sendable`. View models retain `@MainActor` isolation. No new concurrency surface.
- ✅ SwiftUI: no deprecated APIs introduced, no new `@Published`/`ObservableObject`. Pre-existing `@ViewBuilder func` patterns left in place (out of scope).
- ✅ Tests: Swift Testing throughout. `Regression_698ef3b65e6cc4bb5554e13d` deleted (guarded a now-impossible bug class).
- ⏳ Manual on-device verification of bonded-mint Give / Scan / Withdraw / Buy / Sell / activity list / transaction detail subtitle / total balance / onramp before push. Required.

## Per-change Android validation

| Change | Android equivalent | Wire-compat |
|---|---|---|
| `TokenAmount` separate type | None — Android conflates in `Fiat` | Same `proto.quarks` semantics |
| `FiatAmount` separate type | None — Android's `Fiat` carries the same role with a 10⁶ multiplier | Same `proto.nativeAmount` semantics |
| `ExchangedFiat.onChainAmount` (mint-native) | `LocalFiat.underlyingTokenAmount` | Identical wire bytes |
| `ExchangedFiat.usdfValue` (computed) | Computed via `Fiat.tokenBalance(quarks, token)` per call | iOS computes from stored fields; Android recomputes via curve. Net result identical for USDF; for bonded our derivation goes through the rate, not the curve — which is the *honest* derivation given we already have native + FX. |
| `ExchangedFiat.nativeAmount` (FiatAmount) | `LocalFiat.nativeAmount: Fiat` | Same |
| `currencyRate` always currency-FX | `LocalFiat.rate` mostly currency-FX (with same `valueExchangeIn` bug we just fixed) | Match Android intent; we removed the synthesis |
| Proto ingress `Ocp_…ExchangeData` | `LocalFiat(ExchangeData.WithRate)` | Match |
| Proto egress `onChainAmount.quarks → proto.quarks` | `LocalFiat.asExchangeData()` writes `underlyingTokenAmount.quarks` | Match |
