# 2026-03-02 — SendCashOperation verified state not reused for new currencies

## What happened

After adding `verifiedState` to the give/grab flow, passing bills with **newly created currencies** broke. The giver's bill would instantly disappear, and the grabber saw "something went wrong."

## Root cause

`SendCashOperation.start()` has two async paths:

- **Path 1** (fire-and-forget Task): Resolves `verifiedState` via `providedVerifiedState` or `getVerifiedState()`, then sends `requestToGiveBill` to the server.
- **Path 2** (stream callback → Task): When the grab request arrives, calls `transfer()` — but it called `getVerifiedState()` from the cache **again** instead of reusing what Path 1 already resolved.

For newly created currencies, the `VerifiedProtoService` cache (`exchangeRates` dictionary) doesn't have the rate yet. Path 1 worked because it used `providedVerifiedState`. Path 2 ignored it and went to the empty cache → `nil` → `missingVerifiedState` → bill instantly dismissed.

Secondary issue: `ScanCashOperation.listenForMint()` had only 3 retries × 500ms (1s window). Since Path 1 is fire-and-forget and must resolve `getVerifiedState()` before sending, the message delivery is delayed. The scanner's window was too tight.

## Fix

1. `SendCashOperation`: Store the resolved verified state from Path 1 in `resolvedVerifiedState`. Path 2 checks `resolvedVerifiedState ?? getVerifiedState()`.
2. `ScanCashOperation`: Increased to 10 retries × 300ms (~3s window).

## Lesson

When adding a new dependency to an async flow, trace **all paths** that need it — not just the first one. The two Tasks in `SendCashOperation` shared the same need but resolved it independently. Fire-and-forget Tasks that silently prepare state for later paths are especially dangerous because the later path has no guarantee the earlier one succeeded.
