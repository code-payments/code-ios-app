# Android Parity Check: `underlying` / `underlyingTokenAmount` semantics

**Repo:** [code-payments/code-android-app](https://github.com/code-payments/code-android-app)
**Paired audit:** `2026-04-20-exchanged-fiat-underlying-fix-plan.md`

## Why this exists

iOS `ExchangedFiat.underlying` is documented as "always denominated in USD for USDC" (6-decimal USDF) but every constructor uses `decimals: mint.mintDecimals`, which is **10** for bonded/custom mints. That drift produces either 10,000× wrong values or the wrong unit entirely (token quarks where USD is expected).

Before changing iOS, we confirmed the doc intent against Android's equivalent types (`Fiat` ≈ `Quarks`, `LocalFiat` ≈ `ExchangedFiat`).

## TL;DR

- Android's `Fiat` is **architecturally 6-decimal-fixed** (no mint-aware scaling). This is the key point of parity iOS is missing.
- Android's `LocalFiat` has the **same docstring** as iOS `ExchangedFiat` (same source text, same Jeffy/CAD example), which confirms "`underlying` is USD-denominated" is the intended design across both platforms.
- Android's canonical construction path (`LocalFiat.fromNativeAmount`) correctly stores underlying in USD.
- Android's proto boundary (`LocalFiat.asExchangeData` and `ExchangeData.Verified`→proto) uses `underlyingTokenAmount.quarks` as a USD-quark value on the wire.
- One Android path (`LocalFiat.Companion.valueExchangeIn` for non-USDF mints) stuffs token-scaled quarks into a 6-decimal `Fiat` labeled USD. This is a bug on Android too, but it is NOT a reference we want iOS to copy. Flag separately if we care about upstreaming the fix.

## Type layout

### `Fiat` — Android's `Quarks`

File: `services/opencode/src/main/kotlin/com/getcode/opencode/model/financial/Fiat.kt`

```kotlin
@Serializable
@Parcelize
data class Fiat(
    val quarks: Long,
    val currencyCode: CurrencyCode = CurrencyCode.USD,
) : Comparable<Fiat>, Parcelable {

    val decimalValue: Double
        get() = quarks.toDouble() / MULTIPLIER   // <-- fixed 10^6

    companion object {
        const val MULTIPLIER: Double = 1_000_000.0
    }
}
```

Key differences from iOS `Quarks`:

| | iOS `Quarks` | Android `Fiat` |
|-|-|-|
| Decimals | Stored per instance (`decimals: Int`) | Hardcoded to `MULTIPLIER = 1_000_000.0` (10⁶) |
| Can represent a 10-decimal token amount? | Yes (`decimals: 10`) | No — always 6 |
| `subtracting` cross-decimal check | Throws `decimalMismatch` | N/A (single scale) |

Android's `Fiat` **cannot** represent a 10-decimal value at all. That single decision removes the entire class of drift we are fixing on iOS. There is no constructor that lets a caller say "this Long is a 10-decimal token quark." If the codebase ever tries to stuff a 10-decimal value into a `Fiat`, its `decimalValue` comes back wrong by 10⁴, but the TYPE remains a USD-quark (6-decimal) container.

### `LocalFiat` — Android's `ExchangedFiat`

File: `services/opencode/src/main/kotlin/com/getcode/opencode/model/financial/LocalFiat.kt`

```kotlin
@Serializable
@Parcelize
@Immutable
data class LocalFiat(
    val underlyingTokenAmount: Fiat,   // CurrencyCode.USD in every constructor
    val nativeAmount: Fiat,
    val rate: Rate,
    val mint: Mint,
) : Parcelable
```

### Docstring — identical to iOS

```
 * This class maps the relationship between the blockchain reality (USD value for the core mint)
 * and the user's perception (Local Fiat value or non-USDC token value).
 *
 * @property underlyingTokenAmount The raw amount of the core mint token
 *   (always denominated in USD for USDF). This represents the actual on-chain value involved.
 * @property nativeAmount The converted value of the specific token in the user's selected currency
 *   (e.g., EUR, GBP, CAD).
 * @property rate The exchange rate used to convert between [underlyingTokenAmount] and [nativeAmount].
 * @property mint The Mint address of the token being represented.
 *
 * If the user wants to send, for example, $5 CAD of Jeffy, this will look like:
 *
 *   underlyingTokenAmount: (USD value amount for $5 CAD worth of Jeffy in USDC)
 *   nativeAmount: (5 CAD in Jeffy)
 *   rate: (fx determined by bonding curve for $5 CAD of Jeffy)
 *   mint: (Mint address for Jeffy)
```

This confirms the **intent**: `underlying` is a USD (USDF-equivalent) value, even when the `mint` is a bonded currency. The Jeffy example is unambiguous — `underlying` is the USD-in-USDC value, `nativeAmount` is the Jeffy amount.

## Construction paths on Android

### 1. `LocalFiat.fromNativeAmount` — canonical, USD-correct

```kotlin
fun fromNativeAmount(
    nativeAmount: Fiat,
    rate: Rate,
    mint: Mint,
): LocalFiat {
    val usd = nativeAmount.decimalValue / rate.fx
    return LocalFiat(
        underlyingTokenAmount = Fiat(usd, CurrencyCode.USD),   // USD value → 10^6 quarks
        nativeAmount = nativeAmount,
        mint = mint,
        rate = rate
    )
}
```

`Fiat(Double, USD)` internally multiplies by `MULTIPLIER = 10^6`, so `underlyingTokenAmount.quarks = usdValue × 10⁶`. **Matches the doc.**

This is the analogue of iOS `ExchangedFiat(converted:rate:mint:)`. iOS does the same math (`equivalentUSD = converted.decimalValue / rate.fx`) but then constructs `Quarks(fiatDecimal: equivalentUSD, currencyCode: .usd, decimals: mint.mintDecimals)` — it's the `mint.mintDecimals` argument that silently breaks the invariant. Android cannot make this mistake because `Fiat` has no `decimals` parameter.

### 2. Proto-ingress: `LocalFiat(exchangeData: ExchangeData.WithRate)`

```kotlin
constructor(exchangeData: ExchangeData.WithRate) : this(
    underlyingTokenAmount = Fiat(exchangeData.quarks, CurrencyCode.USD),
    nativeAmount = Fiat(fiat = exchangeData.nativeAmount, ...),
    ...
)
```

Server delivers `quarks: Long` (from `ExchangeData.WithRate`) and Android wraps it directly as a `Fiat` in USD. Since `Fiat` is always 10⁶-scaled, this asserts the wire value is **USDF-equivalent quarks**. That tells us what the server side produces: USD-quark-scaled, not mint-native.

### 3. Proto-egress: `LocalFiat.asExchangeData()`

```kotlin
internal fun LocalFiat.asExchangeData(): TransactionService.ExchangeData =
    TransactionService.ExchangeData.newBuilder()
        .setQuarks(underlyingTokenAmount.quarks)       // 10^6-scaled USD quarks
        .setCurrency(rate.currency.name.lowercase())
        .setExchangeRate(rate.fx)
        .setNativeAmount(nativeAmount.decimalValue)
        .build()
```

Matches ingress. The `quarks` proto field is USDF-6-decimal quarks.

Similar pattern in `LocalToProtobuf.kt` for `ExchangeData.Verified.asProtobufExchangeData()` and for `SendPublicPaymentMetadata.setClientExchangeData(...)` — always `underlyingTokenAmount.quarks` → proto `quarks`.

### 4. `LocalFiat.Companion.valueExchangeIn` — bonded compute path (has a bug of its own)

```kotlin
val valuation = Estimator.valueExchangeAsQuarks(
    valueInQuarks = cappedValue.quarks,
    currentSupplyInQuarks = supply,
    mintDecimals = 6,                         // USDF decimals for input
).getOrThrow()

val (quarks, _) = valuation
val underlyingTokenAmount = Fiat(quarks = quarks.toLong(), currencyCode = CurrencyCode.USD)
```

`Estimator.valueExchangeAsQuarks` (file: `libs/currency-math/src/main/kotlin/com/flipcash/libs/currency/math/Estimator.kt`):

```kotlin
val tokenScale = BigDecimal.TEN.pow(DefaultMintDecimals, mc)    // 10^10
val unscaledTokens = valuation.tokens.multiply(tokenScale, mc)  // tokens × 10^10
Valuation.Quarks(quarks = unscaledTokens, fx = fx)
```

`DefaultMintDecimals` (`libs/currency-math/.../internal/Constants.kt`) = **10**. So `valuation.quarks` is **token quarks at 10-decimal scale**, not USD-equivalent quarks.

Shoving a 10-decimal token-quark `Long` into a 6-decimal USD `Fiat` means `decimalValue = tokens × 10⁴` — the resulting `underlyingTokenAmount` does not match the doc. The proto field sent on the wire is also off.

**This is Android's equivalent of iOS's `ExchangedFiat.computeFromQuarks(mint != .usdf)` bug.** Both platforms diverge from the doc in the same place and the same direction. Android does not serve as a reference for fixing this particular path — it has the same issue.

### 5. `Fiat.tokenBalance` — the CORRECT bonded-token→USD conversion

```kotlin
fun tokenBalance(quarks: Long, token: Token): Fiat {
    if (token.address == Mint.usdf) return Fiat(quarks, CurrencyCode.USD)
    return Fiat(
        estimation = {
            Estimator.sell(
                amountInQuarks = quarks,
                marketState = MarketState.FromSupply(
                    token.launchpadMetadata?.currentCirculatingSupplyQuarks ?: 0,
                ),
                mintDecimals = token.decimals,
                outputDecimals = 6,                         // <-- USDF 6 decimals out
                feeBps = 0,
            ).getOrThrow().netAmountToReceive
        },
        tokenMintDecimals = token.decimals
    )
}
```

This is how Android converts a bonded-token quark amount to USDF-equivalent `Fiat` when it matters (e.g., balances). The `outputDecimals = 6` pin is exactly what we need on iOS: the USD representation of bonded-token holdings must be in USDF 6-decimal scale, not mint-native.

## Summary of reference signal for the iOS fix

| Android element | What it tells us |
|-|-|
| `Fiat.MULTIPLIER = 1_000_000.0` (fixed) | `underlying` should always live at 6-decimal USDF scale on iOS too. No per-instance `decimals`. |
| `LocalFiat` docstring (identical to iOS) | `underlying` is USD-denominated by design; Jeffy example makes this explicit. |
| `LocalFiat.fromNativeAmount` | Canonical construction — USD = native / fx, stored directly as USD `Fiat`. Matches iOS `ExchangedFiat(converted:rate:mint:)` intent; the broken part on iOS is only the `decimals: mint.mintDecimals` argument. |
| `LocalFiat(exchangeData:...)` ingress | Server sends USDF-quark `quarks` — confirms server semantics. iOS `ExchangedFiat(_ proto:)` should interpret `proto.quarks` as USDF 6-decimal regardless of mint. |
| `LocalFiat.asExchangeData` / proto egress | `underlying.quarks → proto.quarks` is correct **if** underlying is USDF-scaled. iOS sends it the same way; fix follows if we fix the constructors. |
| `Fiat.tokenBalance(quarks, token)` | Correct template for converting a bonded-token quark count to a USD value — sell via curve, `outputDecimals = 6`. |
| `valueExchangeIn` bonded branch | Has the SAME bug as iOS `computeFromQuarks`. Not a reference; flag for the Android team separately if/when needed. |

## What this greenlights for iOS

1. Keep the docstring: `underlying` is USD-denominated (USDF quarks, 6 decimals) for every mint.
2. Drop `decimals: mint.mintDecimals` in every `ExchangedFiat` constructor that builds `underlying` — replace with `decimals: PublicKey.usdf.mintDecimals`.
3. Strengthen `init(underlying:converted:rate:mint:)` assertion to also check `underlying.decimals == PublicKey.usdf.mintDecimals` — would have caught this at first call.
4. `computeFromQuarks(mint != .usdf)` must compute the USDF-equivalent value from `valuation.netUSDF` and store **that** as `underlying` — not the token quarks passed in.
5. Proto init (`init(_ proto:)`) should interpret `proto.quarks` as USDF 6-decimal regardless of `proto.mint` — matches what Android's `LocalFiat(ExchangeData.WithRate)` assumes.

The paired file `2026-04-20-exchanged-fiat-underlying-fix-plan.md` enumerates the concrete iOS call-site changes.

## What is explicitly out of scope

- No renaming. `underlying` stays `underlying`. `Quarks` stays `Quarks`.
- No changes to `Quarks` itself — leave the `decimals: Int` field as-is. Only `ExchangedFiat`'s use of it is wrong.
- No attempt to upstream the `valueExchangeIn` fix to Android.
