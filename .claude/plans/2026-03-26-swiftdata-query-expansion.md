# Plan: Expand @Query Usage Across Views

**Date:** 2026-03-26
**Prerequisite:** SwiftData migration complete (refactor-swift-data branch)
**Goal:** Push `@Query` into views that currently read data through Session/controllers, eliminating the manual `refreshBalances()` / `refreshLimits()` pattern.

---

## Motivation

The SwiftData migration replaced the storage layer but kept Session as the centralized data intermediary. Views read `session.balances` and `session.limits` — Session fetches from ModelContext via `refreshBalances()` after every write. This works but is the old pattern with new plumbing.

The modern SwiftData pattern: views declare what data they need via `@Query`, SwiftData handles reactivity automatically. No manual refresh calls, no intermediary.

---

## Candidates

### 1. BalanceScreen — `session.balances` → `@Query`

**Current:** BalanceScreen reads `session.balances(for: rate)` which calls `Session.balances` (populated by `refreshBalances()`).

**Target:** BalanceScreen uses `@Query` on `BalanceRecord` with prefetched mint relationship, converts to `ExchangedBalance` via `onChange`.

**Benefit:** Balances update reactively when DatabaseWriter saves — no `refreshBalances()` needed. Session can drop the `balances` property entirely.

**Complexity:** Medium — BalanceScreen also needs exchange rate computation, which comes from `RatesController`. The `@Query` gives raw records; the view still needs `ratesController` for display values.

### 2. CurrencyInfoViewModel — one-shot `ModelContext.fetch()` → `@Query` on CurrencyInfoScreen

**Current:** CurrencyInfoViewModel does `modelContext.fetch(FetchDescriptor<MintRecord>)` at init for the fast-path. Not reactive.

**Target:** CurrencyInfoScreen uses `@Query(filter:)` for the mint record. The VM receives the resolved `StoredMintMetadata` instead of fetching it.

**Benefit:** Mint metadata updates (e.g., live supply changes) reflect immediately without network refresh.

**Complexity:** Low — the view already has `@Environment` access. The VM just needs to accept metadata as a parameter instead of fetching it.

### 3. Session.limits — `refreshLimits()` → `@Query` or remove from Session

**Current:** Session stores `limits: Limits?`, refreshed after `databaseWriter.upsertLimits()`.

**Target:** The few views that check limits (give flow, send flow) read directly via `@Query` or `@Environment(\.modelContext)`.

**Benefit:** Removes the polling-and-refresh pattern for limits.

**Complexity:** Low — limits is a singleton record, trivial `@Query`.

### 4. TransactionHistoryScreen — already done

This is the only view currently using `@Query`. No further work needed.

---

## Order of Execution

1. CurrencyInfoViewModel (lowest risk, clearest improvement)
2. Session.limits (small scope, easy to verify)
3. BalanceScreen (largest change, most impactful)

Each can be done independently as a separate PR.
