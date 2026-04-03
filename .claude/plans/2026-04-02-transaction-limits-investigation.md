# Transaction Limits Investigation

**Date:** 2026-04-02  
**Branch:** `investigate-transaction-limits` (off `refactor-new-server`)

## Product Expectations

| Flow | Per-Transaction Limit | Daily Limit | Limit Source from Server |
|------|----------------------|-------------|--------------------------|
| **Give** | ~$250 | ~$1000/day, per currency | `SendLimit.maxPerTransaction` for per-tx; `SendLimit.nextTransaction` for remaining daily |
| **Buy** | ~$1000 | None | `SendLimit.maxPerDay` used as per-tx cap |
| **WalletConnect** | ~$1000 (same as Buy) | None | `SendLimit.maxPerDay` used as per-tx cap |
| **Sell** | None | None | — |
| **Withdraw** | None | None | — |
| **Deposit** | None | None | — |

### Key Insight: Reusing SendLimit Fields for Buy

The Flipcash server only provides `sendLimitsByCurrency` (no buy-specific limits). Per server team clarification, the **buy per-transaction limit** should use `SendLimit.maxPerDay` (~$1000), not `SendLimit.maxPerTransaction` (~$250). Buy has no daily cap.

---

## Server Model

```
SendLimit (per currency, from GetLimitsResponse.sendLimitsByCurrency)
├── nextTransaction    — remaining allowance for next give tx (daily rolling)
├── maxPerTransaction  — per-tx cap for give (~$250)
└── maxPerDay          — daily cap for give (~$1000), reused as per-tx cap for buy
```

**File:** `FlipcashCore/Sources/FlipcashCore/Models/Limits.swift:40-58`  
**Proto:** `FlipcashAPI/.../transaction_v1_transaction_service.pb.swift:497-543`

---

## Issues & Fixes

### Issue 1: Give Subtitle Mismatch

**Problem:** Subtitle shows `min(balance, maxPerTransaction)` but submit guard checks `nextTransaction`. If daily is partially used, user sees "Enter up to $250" but gets rejected at a lower amount.

**Root cause:** `EnterAmountCalculator.maxTransactionAmount` (line 40) calls `transactionLimitProvider` → `session.singleTransactionLimitFor()` → returns `maxPerTransaction`. But `session.hasLimitToSendFunds()` checks `nextTransaction`.

**Fix:** The calculator's `transactionLimitProvider` should return `min(maxPerTransaction, nextTransaction)` for give flows so the subtitle reflects the actual effective limit.

**Files:**
- `Flipcash/Core/Session/Session.swift` — limit accessor methods (lines 107-141)
- `Flipcash/UI/EnterAmountCalculator.swift` — needs flow-aware limit logic

### Issue 2: Buy Has No Pre-Submit Guard

**Problem:** `CurrencyBuyViewModel.performBuy()` at line 112 calls `session.buy()` with no limit check. Compare with `GiveViewModel.giveAction()` at lines 123-129 which calls both `hasSufficientFunds()` and `hasLimitToSendFunds()`.

**Fix:** Add pre-submit limit check using `maxPerDay` as the per-tx cap. Show "Transaction Limit Reached" dialog on failure.

**Files:**
- `Flipcash/Core/Screens/Main/Currency Swap/CurrencyBuyViewModel.swift`
- `Flipcash/Core/Session/Session.swift` — needs buy-specific limit accessor

### Issue 3: WalletConnect Has Zero Enforcement

**Problem:** `EnterWalletAmountScreen` displays a limit subtitle but `actionEnabled` (line 54) only checks `fiat != nil && quarks > 0`. User can enter any amount and proceed to Phantom.

**Fix:** Enforce `maxPerDay` as per-tx cap in `actionEnabled`. Same limit source as Buy.

**Files:**
- `Flipcash/Core/Controllers/Deep Links/Wallet/EnterWalletAmountScreen.swift`

---

## Implementation Plan (TDD)

### Step 1: Expand EnterAmountCalculator with flow-aware limits

The calculator currently has a single `transactionLimitProvider` that always returns `maxPerTransaction`. It needs to return different limits based on the flow:

- **Give flows** (`.currency`): `min(maxPerTransaction, nextTransaction)` — effective give limit
- **Buy flows** (`.buy`, `.phantomDeposit`, `.walletDeposit`): `maxPerDay` — buy per-tx cap

This means the calculator needs two providers, or Session needs to expose flow-specific limit methods.

**Tests first:** Add tests to `EnterAmountCalculatorTests` for:
- Give mode returns `min(maxPerTransaction, nextTransaction)`
- Buy mode returns `maxPerDay`
- Give mode with partially exhausted daily limit shows lower cap
- WalletConnect/phantom mode uses buy limits

### Step 2: Add buy limit accessor to Session

Add `buyTransactionLimit(currency:)` that returns `maxPerDay` for the given currency. Add `hasLimitToBuyFunds(for:)` that validates against this limit.

### Step 3: Wire up Buy flow enforcement

Add pre-submit guard in `CurrencyBuyViewModel.performBuy()` using `hasLimitToBuyFunds()`.

### Step 4: Wire up WalletConnect enforcement

Fix `EnterWalletAmountScreen.actionEnabled` to validate against the buy limit. Use `maxPerDay` as per-tx cap.

### Step 5: Fix Give subtitle to use effective limit

Wire the calculator to use `min(maxPerTransaction, nextTransaction)` for give flows via the updated provider.
