# ExchangedFiat — type split plan (v3: match the proto)

**Branch:** `fix/exchanged-fiat-underlying-decimals`
**Paired investigation:** `2026-04-20-android-underlying-investigation.md`
**Supersedes:** v1 (decimals tweak — wrong) and v2 (keep `Quarks`, add `TokenAmount` — incomplete). The proto shows us the right model; we match it.

## Thesis

The server's `ExchangeData` proto already tells us how these values should be modeled:

```proto
message ExchangeData {
    bytes   mint        = ...;   // token identity
    uint64  quarks      = ...;   // mint-native on-chain integer
    double  nativeAmount = ...;  // fiat decimal value
    string  currency    = ...;   // fiat currency code
    double  exchangeRate = ...;  // FX rate
}
```

Two independent concerns:
- `(mint, quarks)` — on-chain amount. Raw integer paired with a token identity. No currency code. Mint provides decimals.
- `(nativeAmount, currency, exchangeRate)` — fiat amount with FX context. Decimal value. No "quarks" concept.

Our `Quarks` type conflates both. `Quarks.currencyCode` holds `.usd` as a placeholder when the value is actually mint-native. `Quarks.decimals` varies to accommodate bonded tokens even though fiat values don't need it. Every symptom (display mislabels, dimensional math errors, `rate.fx` shape-shift, cross-decimal comparison bugs) is a downstream effect of this conflation.

**Fix:** stop carrying a 7-year-old single-type model forward. Mirror the proto with two types. Delete `Quarks`.

## Invariants

1. Any value that goes on-chain or to `proto.quarks` has type `TokenAmount`. Not a fiat type. No currency code.
2. Any fiat value has type `FiatAmount`. No `decimals` field. Scaling is the type's internal concern, not the caller's.
3. `ExchangedFiat.currencyRate.fx` is always native-per-USD. No shape-shifting.
4. Arithmetic uses Swift operators (`+`, `-`, `<`, etc.). Mismatched currency / mint is a programmer error → `precondition`. Insufficient-funds checks happen at the call site before subtraction, not inside it.

## Non-goals

- Not changing the server wire format. Proto stays as-is.
- Not fixing Android. Same bug there, different PR.
- Not introducing a shared `Amount` protocol. Two concrete types is clearer.

---

## Phase 1 — New types

### 1.1 `TokenAmount` (mirrors proto `(mint, quarks)`)

Location: `FlipcashCore/Sources/FlipcashCore/Models/TokenAmount.swift`

```swift
import Foundation

/// On-chain token amount. Mirrors the proto `(mint, quarks)` pair.
///
/// No currency code — the mint is the identity. Decimals come from the mint.
/// Cannot represent a fiat value; that's what `FiatAmount` is for.
public struct TokenAmount: Equatable, Hashable, Codable, Sendable {

    public let quarks: UInt64
    public let mint: PublicKey

    public var decimalValue: Decimal { quarks.scaleDown(mint.mintDecimals) }
    public var decimals: Int         { mint.mintDecimals }

    public init(quarks: UInt64, mint: PublicKey) {
        self.quarks = quarks
        self.mint = mint
    }

    public init(wholeTokens: Decimal, mint: PublicKey) {
        self.init(
            quarks: wholeTokens.scaleUpInt(mint.mintDecimals),
            mint: mint,
        )
    }

    public static func zero(mint: PublicKey) -> TokenAmount {
        TokenAmount(quarks: 0, mint: mint)
    }
}

// MARK: - Arithmetic

extension TokenAmount {
    public static func + (lhs: TokenAmount, rhs: TokenAmount) -> TokenAmount {
        precondition(lhs.mint == rhs.mint, "Cannot add TokenAmounts with different mints")
        return TokenAmount(quarks: lhs.quarks + rhs.quarks, mint: lhs.mint)
    }

    public static func - (lhs: TokenAmount, rhs: TokenAmount) -> TokenAmount {
        precondition(lhs.mint == rhs.mint, "Cannot subtract TokenAmounts with different mints")
        precondition(lhs.quarks >= rhs.quarks, "TokenAmount subtraction underflow — check sufficient funds before subtracting")
        return TokenAmount(quarks: lhs.quarks - rhs.quarks, mint: lhs.mint)
    }

    public static func += (lhs: inout TokenAmount, rhs: TokenAmount) { lhs = lhs + rhs }
    public static func -= (lhs: inout TokenAmount, rhs: TokenAmount) { lhs = lhs - rhs }
}

// MARK: - Comparable

extension TokenAmount: Comparable {
    public static func < (lhs: TokenAmount, rhs: TokenAmount) -> Bool {
        precondition(lhs.mint == rhs.mint, "Cannot compare TokenAmounts with different mints")
        return lhs.quarks < rhs.quarks
    }
}
```

**Android mirror:** Android conflates token + fiat into `Fiat`. We diverge for type-safety; proto wire format is unchanged.

### 1.2 `FiatAmount` (mirrors proto `(currency, nativeAmount)`)

Location: `FlipcashCore/Sources/FlipcashCore/Models/FiatAmount.swift`

```swift
import Foundation

/// Fiat value. Mirrors proto `(currency, nativeAmount)`.
///
/// No decimals field — scaling is not a fiat concern.
public struct FiatAmount: Equatable, Hashable, Codable, Sendable {

    public let value: Decimal
    public let currency: CurrencyCode

    public init(value: Decimal, currency: CurrencyCode) {
        self.value = value
        self.currency = currency
    }

    public static func zero(in currency: CurrencyCode) -> FiatAmount {
        FiatAmount(value: 0, currency: currency)
    }

    /// Convenience for USD values.
    public static func usd(_ value: Decimal) -> FiatAmount {
        FiatAmount(value: value, currency: .usd)
    }

    public var doubleValue: Double { value.doubleValue }
}

// MARK: - Arithmetic

extension FiatAmount {
    public static func + (lhs: FiatAmount, rhs: FiatAmount) -> FiatAmount {
        precondition(lhs.currency == rhs.currency, "Cannot add FiatAmounts with different currencies")
        return FiatAmount(value: lhs.value + rhs.value, currency: lhs.currency)
    }

    public static func - (lhs: FiatAmount, rhs: FiatAmount) -> FiatAmount {
        precondition(lhs.currency == rhs.currency, "Cannot subtract FiatAmounts with different currencies")
        return FiatAmount(value: lhs.value - rhs.value, currency: lhs.currency)
    }

    public static func += (lhs: inout FiatAmount, rhs: FiatAmount) { lhs = lhs + rhs }
    public static func -= (lhs: inout FiatAmount, rhs: FiatAmount) { lhs = lhs - rhs }

    public static func * (lhs: FiatAmount, rhs: Decimal) -> FiatAmount {
        FiatAmount(value: lhs.value * rhs, currency: lhs.currency)
    }
}

// MARK: - Comparable

extension FiatAmount: Comparable {
    public static func < (lhs: FiatAmount, rhs: FiatAmount) -> Bool {
        precondition(lhs.currency == rhs.currency, "Cannot compare FiatAmounts with different currencies")
        return lhs.value < rhs.value
    }
}

// MARK: - Currency Conversion

extension FiatAmount {
    /// Convert this fiat to another currency using the given rate.
    /// Precondition: `rate.currency != self.currency` (non-trivial conversion).
    /// Semantics: if self is USD and rate is native-per-USD, result is native;
    /// if self is native and rate is native-per-USD, use `convertingToUSD(rate:)`.
    public func converting(to rate: Rate) -> FiatAmount {
        precondition(currency == .usd, "converting(to:) assumes self is USD; use convertingToUSD for the inverse")
        return FiatAmount(value: value * rate.fx, currency: rate.currency)
    }

    public func convertingToUSD(rate: Rate) -> FiatAmount {
        precondition(currency == rate.currency, "rate.currency must match self.currency")
        return FiatAmount(value: value / rate.fx, currency: .usd)
    }
}

// MARK: - Formatting

extension FiatAmount {
    public func formatted(suffix: String? = nil) -> String {
        NumberFormatter.fiat(
            currency: currency,
            minimumFractionDigits: currency.maximumFractionDigits,
            maximumFractionDigits: currency.maximumFractionDigits,
            truncated: false,
            suffix: suffix,
        ).string(from: value as NSDecimalNumber)!
    }
}

// MARK: - Display Threshold

extension FiatAmount {
    /// The smallest fractional value this currency can display as non-zero.
    /// Example: USD with 2 fraction digits → 0.01.
    public var minimumDisplayableValue: Decimal {
        Decimal(sign: .plus, exponent: -currency.maximumFractionDigits, significand: 1)
    }

    public var hasDisplayableValue: Bool { value >= minimumDisplayableValue }

    public var isApproximatelyZero: Bool { value > 0 && !hasDisplayableValue }
}

// MARK: - Expressible by Literal

extension FiatAmount: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self.init(value: Decimal(value), currency: .usd)
    }
}

extension FiatAmount: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self.init(value: Decimal(value), currency: .usd)
    }
}
```

**Android mirror:** Android's `Fiat` stores a `quarks: Long` with fixed `MULTIPLIER = 1_000_000.0` scaling. That internal `quarks` field is a legacy vestige of the same "everything is quarks" assumption — Android hasn't done this split yet. Our `FiatAmount.value: Decimal` is what `Fiat.decimalValue` already returns on Android; we just don't pretend it's stored as quarks.

### 1.3 `Quarks` — DELETED

The file `FlipcashCore/Sources/FlipcashCore/Models/Quarks.swift` is removed. Every former `Quarks` usage becomes:
- `TokenAmount` if the value was mint-native / on-chain
- `FiatAmount` if the value was a fiat figure

There is no in-between. The compiler surfaces every site that needs a decision.

---

## Phase 2 — `ExchangedFiat`

New shape:

```swift
public struct ExchangedFiat: Equatable, Hashable, Codable, Sendable {

    /// The on-chain amount. Goes into the SPL token transfer and `proto.quarks`.
    public let onChainAmount: TokenAmount

    /// USD value of `onChainAmount`. `FiatAmount` with `currency == .usd`.
    /// For USDF mints numerically equals `onChainAmount.decimalValue`.
    /// For bonded mints: `bondingCurve.sell(onChainAmount).netUSDF` at construction.
    public let usdfValue: FiatAmount

    /// User's native fiat amount.
    public let nativeAmount: FiatAmount

    /// Currency FX rate: native-per-USD. Always. No per-token variant.
    public let currencyRate: Rate

    public var mint: PublicKey { onChainAmount.mint }

    /// Per-whole-token USD price for bonded mints (computed, display-only).
    public var tokenPriceInUSD: Decimal? {
        guard mint != .usdf, onChainAmount.decimalValue > 0 else { return nil }
        return usdfValue.value / onChainAmount.decimalValue
    }
}
```

### 2.1 Principal initializer

```swift
public init(
    onChainAmount: TokenAmount,
    usdfValue: FiatAmount,
    nativeAmount: FiatAmount,
    currencyRate: Rate,
) {
    precondition(usdfValue.currency == .usd)
    precondition(nativeAmount.currency == currencyRate.currency)
    self.onChainAmount = onChainAmount
    self.usdfValue = usdfValue
    self.nativeAmount = nativeAmount
    self.currencyRate = currencyRate
}
```

No assertion on the numeric relationship — rounding and curve resolution can introduce small discrepancies.

### 2.2 Factories

```swift
extension ExchangedFiat {
    /// USDF-only convenience.
    public init(nativeAmount: FiatAmount, rate: Rate) {
        precondition(nativeAmount.currency == rate.currency)
        let usdfValue = nativeAmount.convertingToUSD(rate: rate)
        let onChain = TokenAmount(
            wholeTokens: usdfValue.value,
            mint: .usdf,
        )
        self.init(
            onChainAmount: onChain,
            usdfValue: usdfValue,
            nativeAmount: nativeAmount,
            currencyRate: rate,
        )
    }

    /// From an on-chain amount. Resolves USDF via bonding curve for bonded mints.
    public static func compute(
        onChainAmount: TokenAmount,
        rate: Rate,
        supplyQuarks: UInt64?,
    ) -> ExchangedFiat {
        let mint = onChainAmount.mint

        if mint == .usdf {
            let usdfValue = FiatAmount.usd(onChainAmount.decimalValue)
            return ExchangedFiat(
                onChainAmount: onChainAmount,
                usdfValue: usdfValue,
                nativeAmount: usdfValue.converting(to: rate),
                currencyRate: rate,
            )
        }

        // Bonded: resolve USDF via curve sell.
        let quarksToSell = onChainAmount.quarks == 0 ? 1 : onChainAmount.quarks
        guard let valuation = bondingCurve.sell(
            tokenQuarks: Int(quarksToSell),
            feeBps: 0,
            supplyQuarks: Int(supplyQuarks ?? 0),
        ) else {
            return safeZero(mint: mint, rate: rate)
        }

        let usdDecimal = onChainAmount.quarks == 0 ? .zero : valuation.netUSDF.asDecimal()
        let usdfValue = FiatAmount.usd(usdDecimal)

        return ExchangedFiat(
            onChainAmount: onChainAmount,
            usdfValue: usdfValue,
            nativeAmount: usdfValue.converting(to: rate),
            currencyRate: rate,
        )
    }

    /// From a user-entered fiat amount.
    public static func compute(
        fromEntered amount: FiatAmount,
        rate: Rate,
        mint: PublicKey,
        supplyQuarks: UInt64,
        balance: FiatAmount? = nil,
        tokenBalanceQuarks: UInt64? = nil,
    ) -> ExchangedFiat? {
        guard amount.value > 0 else { return nil }
        precondition(amount.currency == rate.currency)
        if let balance { precondition(balance.currency == .usd) }

        // Cap to balance (USDF-terms) if provided.
        let usdRequested = amount.convertingToUSD(rate: rate)
        let cappedUSD: FiatAmount = {
            guard let balance else { return usdRequested }
            return usdRequested.value > balance.value ? balance : usdRequested
        }()

        // USDF-only path is trivial.
        if mint == .usdf {
            let onChain = TokenAmount(wholeTokens: cappedUSD.value, mint: .usdf)
            return ExchangedFiat(
                onChainAmount: onChain,
                usdfValue: cappedUSD,
                nativeAmount: cappedUSD.converting(to: rate),
                currencyRate: rate,
            )
        }

        // Bonded: resolve via curve.
        guard let valuation = bondingCurve.tokensForValueExchange(
            fiat: BigDecimal(cappedUSD.value * rate.fx),
            fiatRate: BigDecimal(rate.fx),
            supplyQuarks: Int(supplyQuarks),
        ) else { return nil }

        let tokenQuarks = valuation.tokens.asDecimal().scaleUpInt(mint.mintDecimals)

        // Cap to on-chain balance if provided (sell flow).
        if let tokenBalanceQuarks, tokenQuarks > tokenBalanceQuarks {
            return compute(
                onChainAmount: TokenAmount(quarks: tokenBalanceQuarks, mint: mint),
                rate: rate,
                supplyQuarks: supplyQuarks,
            )
        }

        // Round-trip through `compute(onChainAmount:)` so the fiat side matches
        // the server's intent validation (tokens → fiat via curve sell).
        return compute(
            onChainAmount: TokenAmount(quarks: tokenQuarks, mint: mint),
            rate: rate,
            supplyQuarks: supplyQuarks,
        )
    }

    private static func safeZero(mint: PublicKey, rate: Rate) -> ExchangedFiat {
        ExchangedFiat(
            onChainAmount: .zero(mint: mint),
            usdfValue: .zero(in: .usd),
            nativeAmount: .zero(in: rate.currency),
            currencyRate: rate,
        )
    }
}
```

### 2.3 Proto init

```swift
extension ExchangedFiat {
    init(_ proto: Ocp_Transaction_V1_ExchangeData, supplyQuarks: UInt64?) throws {
        let currency = try CurrencyCode(currencyCode: proto.currency)
        let mint     = try PublicKey(proto.mint.value)

        let onChain = TokenAmount(quarks: proto.quarks, mint: mint)
        let rate = Rate(fx: Decimal(proto.exchangeRate), currency: currency)

        self = ExchangedFiat.compute(
            onChainAmount: onChain,
            rate: rate,
            supplyQuarks: supplyQuarks,
        )
    }

    init(_ proto: Flipcash_Common_V1_CryptoPaymentAmount, supplyQuarks: UInt64?) throws {
        // Same shape.
        ...
    }
}
```

Supply is required to resolve the USDF equivalent for bonded mints. Call sites that don't have supply at decode time (e.g. `Database+Activities`, `AccountInfo`) either:
1. Carry supply separately in the storage layer and pass it in at decode, or
2. Defer the USDF resolution — make `usdfValue` `Optional<FiatAmount>` and fill in lazily when a supply snapshot is available.

Decision in §4.

### 2.4 Arithmetic on `ExchangedFiat`

With operators on the component types, `ExchangedFiat` operations read cleanly. But `ExchangedFiat` itself doesn't get `+` / `-` operators — the split between on-chain and fiat sides means combining two `ExchangedFiat`s has non-obvious semantics (do you recompute USDF from the summed on-chain amounts through the curve? or sum the USDF values directly?).

Instead:

```swift
extension ExchangedFiat {
    /// Subtract a fee from this ExchangedFiat, returning a new ExchangedFiat for the
    /// remaining on-chain amount. USDF and native values are recomputed via
    /// `compute(onChainAmount:rate:supplyQuarks:)` so the fiat side stays accurate.
    public func subtractingFee(_ fee: TokenAmount, supplyQuarks: UInt64?) -> ExchangedFiat {
        let remaining = onChainAmount - fee
        return .compute(
            onChainAmount: remaining,
            rate: currencyRate,
            supplyQuarks: supplyQuarks,
        )
    }

    public func convert(to newRate: Rate) -> ExchangedFiat {
        ExchangedFiat(
            onChainAmount: onChainAmount,
            usdfValue: usdfValue,
            nativeAmount: usdfValue.converting(to: newRate),
            currencyRate: newRate,
        )
    }
}
```

`Collection<ExchangedFiat>.total(rate:)` sums `usdfValue` and `nativeAmount` directly (both via `+`), uses `.usdf` as the portfolio mint for `onChainAmount`.

---

## Phase 3 — Consumer migration

Every `Quarks`-typed declaration in the codebase flips to `TokenAmount` or `FiatAmount`. The compiler is the guide.

### 3.1 Chain / wire sites

Pattern: `.underlying` / `.underlying.quarks` → `.onChainAmount` / `.onChainAmount.quarks`. No semantic change; these sites always wanted mint-native.

| File | Line | Change |
|---|---|---|
| `FlipcashCore/.../Intents/IntentTransfer.swift` | 33 | `ActionTransfer(amount: exchangedFiat.underlying, …)` → `amount: exchangedFiat.onChainAmount` |
| `FlipcashCore/.../Intents/IntentTransfer.swift` | 56 | `$0.quarks = exchangedFiat.underlying.quarks` → `$0.quarks = exchangedFiat.onChainAmount.quarks` |
| `FlipcashCore/.../Intents/IntentTransfer.swift` | 57 | `$0.nativeAmount = exchangedFiat.converted.doubleValue` → `$0.nativeAmount = exchangedFiat.nativeAmount.doubleValue` |
| `FlipcashCore/.../Intents/IntentWithdraw.swift` | 41, 58 | `amount: amountToWithdraw.underlying` / `exchangedFiat.underlying` → `.onChainAmount` |
| `FlipcashCore/.../Intents/IntentWithdraw.swift` | 83, 84 | proto `quarks` + `nativeAmount` — same rename |
| `FlipcashCore/.../Intents/IntentWithdraw.swift` | 17, 49 | `fee: Quarks` → `fee: TokenAmount` (on-chain fee) |
| `FlipcashCore/.../Intents/IntentWithdraw.swift` | 38 | `try exchangedFiat.subtracting(fee: fee)` → `exchangedFiat.subtractingFee(fee, supplyQuarks: …)` |
| `FlipcashCore/.../Intents/IntentSendCashLink.swift` | 39, 47 | `amount: exchangedFiat.underlying` → `.onChainAmount` |
| `FlipcashCore/.../Intents/IntentSendCashLink.swift` | 74, 75 | proto rename |
| `FlipcashCore/.../Intents/IntentFundSwap.swift` | 50 | `amount: amount.underlying` → `.onChainAmount` |
| `FlipcashCore/.../Intents/IntentFundSwap.swift` | 74, 75 | proto rename |
| `FlipcashCore/.../Services/MessagingService.swift` | 230 | `$0.quarks = exchangedFiat.underlying.quarks` → `.onChainAmount.quarks` |
| `FlipcashCore/.../Intents/Actions/ActionTransfer.swift` | — | parameter `amount: Quarks` → `amount: TokenAmount`; body unchanged (`$0.amount = amount.quarks`) |
| `FlipcashCore/.../Intents/Actions/ActionWithdraw.swift` | — | same |
| `FlipcashCore/.../Intents/Actions/ActionFeeTransfer.swift` | — | same |
| `FlipcashCore/.../Services/SwapService.swift` | 166, 229 | `amount: Quarks` → `amount: TokenAmount` |
| `FlipcashCore/.../Solana/TransactionBuilder.swift` | 74-84 | same |
| `FlipcashCore/.../Services/TransactionService.swift` | 371 | `swapService.swap(…, amount: amount.underlying, …)` → `.onChainAmount` |

**Android mirror:** `IntentTransfer.create` passes `amount.underlyingTokenAmount` to `ActionPublicTransfer.newInstance`, and writes `underlyingTokenAmount.quarks` to `clientExchangeData.quarks`. Same pattern; our rename makes intent explicit.

### 3.2 USD / fiat sites

Pattern: today's `.underlying` that was SUPPOSED to be USD (but wasn't, for bonded) → `.usdfValue`. Today's `.converted` → `.nativeAmount`.

| File | Line | Change |
|---|---|---|
| `Flipcash/Core/Screens/Main/TransactionDetailsModal.swift` | 50 | `.underlying.formatted()` → `.usdfValue.formatted()` (now shows real USD for bonded) |
| `Flipcash/Core/Screens/Main/TransactionDetailsModal.swift` | 42 | `.rate.fx.formatted()` → `.currencyRate.fx.formatted()` (now truly currency FX, not per-token) |
| `FlipcashCore/.../Services/TransactionService.swift` | 112 | `.underlying.formatted(suffix: " USDF")` → `.usdfValue.formatted(suffix: " USDF")` |
| `FlipcashCore/.../Models/ExchangedFiat.swift` | `descriptionDictionary` | `"usdc"` key → `"usdf"` (from `usdfValue`), add `"onChain"` (from `onChainAmount`) |
| `Flipcash/Core/Session/Session.swift` | 137 | `collection.total(rate:)` — summation uses `.usdfValue` and `.nativeAmount` |
| `Flipcash/Core/Session/Session.swift` | 372 | `.underlying.quarks > 0` → `.onChainAmount.quarks > 0` (works at any scale) |
| `Flipcash/Core/Session/Session.swift` | 740 | `amount.underlying.quarks > balance.quarks` → `amount.usdfValue > balance.usdf` (both USD; fixes the silent-always-false bug) |
| `Flipcash/Utilities/Events.swift` | 127, 129, 148, 150, 244, 254, 268 | analytics — `.underlying.quarks` / `.underlying.doubleValue` → `.usdfValue.value.doubleValue` etc. |
| `Flipcash/Core/Controllers/Onramp/OnrampCoordinator.swift` | 668, 677 | `.underlying.quarks` / `.underlying.decimalValue` → `.usdfValue.…` (USDF-only in practice; now type-safe) |
| `Flipcash/Core/Controllers/StoredBalance.swift` | 94 | `.underlying` → `.usdfValue` |
| `Flipcash/Core/Screens/Main/Currency Swap/CurrencySellConfirmationViewModel.swift` | 26-28 | fee math — `amount.underlying.quarks * bps / 10_000` → use `onChainAmount` for token-native fee |
| `Flipcash/Core/Screens/Main/Currency Swap/CurrencySellConfirmationViewModel.swift` | 84, 86 | log metadata → `.usdfValue` |
| `Flipcash/Core/Screens/Main/Currency Swap/CurrencyBuyViewModel.swift` | 50, 151 | cap + log → `.usdfValue` |
| `Flipcash/Core/Screens/Main/Currency Swap/SwapProcessingViewModel.swift` | 164 | error metadata → `.usdfValue` |
| `Flipcash/Core/Screens/Settings/WithdrawViewModel.swift` | 279 | error metadata → `.usdfValue` |

### 3.3 `.converted` → `.nativeAmount` and `.rate` → `.currencyRate`

Pure rename. Grep + replace. ~20 sites across view models, screens, tests.

### 3.4 Other `Quarks`-typed sites

Every remaining `Quarks` declaration is either a USDF balance, a fee, a limit, or a local-currency amount. Classify case-by-case:

| Context | Old type | New type |
|---|---|---|
| USDF wallet balance (`StoredBalance.usdf`) | `Quarks(.usd, 6)` | `FiatAmount(currency: .usd)` if display-only; `TokenAmount(mint: .usdf)` if used for on-chain fee arithmetic |
| On-chain fee (`ActionFeeTransfer.amount`, withdraw fee) | `Quarks(.usd, 6)` | `TokenAmount(mint: .usdf)` |
| Limits (`SendLimit`, etc.) | `Quarks(currency: *, decimals: 6)` | `FiatAmount(currency: *)` |
| `RatesController` cached rates storage | `Quarks` | Depends — usually `FiatAmount` |
| Onramp Coinbase order value | `Quarks(.usd, 6)` | `FiatAmount(.usd)` |

Each migration is mechanical once the component types are in place.

### 3.5 Quarks `ExpressibleBy…Literal` → FiatAmount

Tests and convenience constructors that do `let amount: Quarks = 5.0` flip to `FiatAmount = 5.0` (USD default, matches old behavior).

---

## Phase 4 — Persistence

### 4.1 Activities schema

Today the `activities` row holds a single `quarks: Int` column (mint-native). After the split we need both the on-chain amount and the USDF equivalent.

**Option A — store both on write.** New column `usdf_quarks: Int`. On write, persist `onChainAmount.quarks` and `usdfValue.value.scaleUpInt(6)`. On read, build `TokenAmount(quarks: row[quarks], mint:)` + `FiatAmount(value: row[usdf_quarks].scaleDown(6), currency: .usd)`.

**Option B — compute USDF at read via curve + supply snapshot.** Add `supply_quarks_at_time: Int?` column. On read, run `bondingCurve.sell(…)` to resolve USDF.

Recommend **A**. Storing the USDF value once is cheap and eliminates the "what if supply changed" question. Curve outputs are deterministic given supply; storing the resolved value means we never re-resolve with a different supply than what was live at transaction time.

### 4.2 Migration

- Bump `SQLiteVersion` in `Info.plist`.
- `SessionAuthenticator.initializeDatabase` rebuilds on next login (standard path).
- For already-logged-in users not triggering a relogin: add a post-update one-shot that wipes the `activities` table and marks a `NSUserDefaults` flag. Activities refetch from server on next open.

### 4.3 Database code sites

- `Flipcash/Core/Controllers/Database/Schema.swift` — column addition + version bump.
- `Flipcash/Core/Controllers/Database/Database+Activities.swift:97-108` — read path builds `ExchangedFiat` from both columns.
- `Flipcash/Core/Controllers/Database/Database+Activities.swift:149` — write path stores both.
- `FlipcashCore/.../Models/AccountInfo.swift:251` — proto→ExchangedFiat. Need supply at construction; either plumb in, or make `usdfValue` optional with lazy enrichment.
- `FlipcashCore/.../Models/IntentMetadata.swift:40, 48` — same.

If plumbing supply through is too invasive, use lazy enrichment: `usdfValue: FiatAmount?` with a nonisolated method `enriched(withSupply:) -> ExchangedFiat` that callers run once supply is known.

---

## Phase 5 — Tests

### 5.1 Fixture updates

- `FlipcashCore/Tests/FlipcashCoreTests/ExchangedFiatTests.swift` — every `Quarks(…)` fixture → `TokenAmount` or `FiatAmount`. Every `.underlying` assertion remapped.
- Tests that currently assert `underlying.quarks == token_quark_count` for bonded mints (`testComputingValueFromSmallQuarks`, `testComputingValueFromLargeQuarks`, `testQuarksToBalanceConversion`): assertion target changes to `onChainAmount.quarks == token_quark_count` AND new assertion `usdfValue.value ≈ valuation.netUSDF`.
- `testAmountsToSend` — rewrite. Was checking "underlying decreases as supply increases" (a consequence of the bug). New assertion: `usdfValue` ≈ constant across supply levels (the bonding curve invariant).
- `testSimpleSubstraction` — uses the new `-` operator on `TokenAmount` or `FiatAmount`. No more `Quarks.subtracting`.

### 5.2 New tests

- For every public factory, assert `usdfValue.currency == .usd`, `nativeAmount.currency == currencyRate.currency`, `onChainAmount.mint == mint`.
- Jeffy docstring regression: compute `$5 CAD of Jeffy`, assert `usdfValue.value ≈ $3.57`, `nativeAmount.value ≈ 5`, `onChainAmount.quarks` matches the curve.
- Proto round-trip: decode with a bonded mint + supply, assert correctness.
- Operator tests: `TokenAmount + TokenAmount` same mint, `TokenAmount < TokenAmount`, `FiatAmount` arithmetic. `precondition` violations verified via `@Test(arguments:)` where feasible (or skip — precondition traps aren't cleanly testable in Swift Testing).
- Collection `total` across mixed mints — assert USDF sum is the sum of per-element `usdfValue`.

### 5.3 Regression test move

`FlipcashTests/Regressions/Regression_698ef3b.swift` (Quarks cross-decimal overflow) — delete. The bug class it guards against becomes structurally impossible (`FiatAmount` has no decimals field; `TokenAmount` comparison across different mints precondition-fails not overflows).

---

## Phase 6 — Landing order

Single large commit or a tight sequence — this is a typesystem refactor; there's no value in landing half of it.

1. Add `TokenAmount.swift` and `FiatAmount.swift`.
2. Rewrite `ExchangedFiat.swift` against the new types.
3. Delete `Quarks.swift`.
4. Fix the entire downstream cascade until it compiles.
5. Update tests.
6. Persistence: schema + migration.
7. Manual on-device pass: bonded-mint Give / Scan / Withdraw / Buy / Sell / activity list / transaction detail subtitle / total balance / onramp. All should show correct USD and transfer correct on-chain amounts.
8. Push with explicit `-u origin fix/exchanged-fiat-underlying-decimals` (see §7).

No partial push before manual testing confirms bonded-mint transfers land on-chain correctly. Structural correctness from the compiler is necessary but not sufficient.

---

## Phase 7 — Branch / upstream safety

Branch `fix/exchanged-fiat-underlying-decimals` created with `--no-track`:
- `branch.fix/exchanged-fiat-underlying-decimals.merge` — unset
- `branch.fix/exchanged-fiat-underlying-decimals.remote` — unset

First push must be `git push -u origin fix/exchanged-fiat-underlying-decimals`. **Do not use `git push` without the explicit target on the first push.** Several branches in this repo have `merge = refs/heads/main` set locally (e.g. `claude/gallant-montalcini`, `sharp-tu`, `amazing-edison`, `fix/currency-wizard-summary-keyboard-bounce`) — that's what caused the earlier `fix/onramp-*` incident. This branch is clean. Before every subsequent push, verify `git config --get branch.fix/exchanged-fiat-underlying-decimals.merge` returns `refs/heads/fix/exchanged-fiat-underlying-decimals`.

---

## Appendix — Per-change Android validation

| Change | Android state | Validation |
|---|---|---|
| `TokenAmount` type | No equivalent; Android conflates token + fiat into `Fiat` | We lead; server protocol unchanged |
| `FiatAmount` type (no decimals field) | Android's `Fiat` has `MULTIPLIER = 1_000_000.0` hardcoded, effectively making it a 6-decimal-fiat-only type | Matches Android's implicit contract, just makes it explicit |
| `Quarks` deleted | Android still has `quarks: Long` on `Fiat` — legacy | We lead |
| `ExchangedFiat.onChainAmount: TokenAmount` | `LocalFiat.underlyingTokenAmount: Fiat` (mint-native in practice) | Same semantics, type-safe wrapper |
| `ExchangedFiat.usdfValue: FiatAmount` (cached) | Not stored on Android — recomputed via `Fiat.tokenBalance` on demand | We cache; Android's display sites re-run the curve |
| `ExchangedFiat.nativeAmount: FiatAmount` | `LocalFiat.nativeAmount: Fiat` | Exact match; just no "quarks" baggage |
| `currencyRate: Rate` always currency-FX | Android's `rate` is mostly currency-FX (with a local `valueExchangeIn` bug) | Match Android intent; make it structural |
| `compute(onChainAmount:rate:supplyQuarks:)` using `valuation.netUSDF` | Android's `valueExchangeIn` stuffs token quarks into the USD slot (bug) | We lead; Android can follow |
| Proto ingress `proto.quarks → TokenAmount` | `LocalFiat(ExchangeData.WithRate)` loads `quarks` into `underlyingTokenAmount` as mint-native | Match — server sends mint-native, we keep it that way |
| Proto egress `onChainAmount.quarks → proto.quarks` | `LocalFiat.asExchangeData` writes `underlyingTokenAmount.quarks` | Match |
| Arithmetic via `+` / `-` operators | Android has `operator fun Fiat.plus/minus` + `operator fun LocalFiat.plus/minus` | Kotlin and Swift idiom parity |
