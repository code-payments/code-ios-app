# Supply-Drift invalidIntent — Flip-Flopping Across Theories Before Reading the Code

**Date:** 2026-04-20

## The Bug / Task

Launchpad currency give/withdraw/cash-link flows intermittently failed with server-side `invalidIntent(native amount does not match expected sell value)`. Task was to find the root cause and ship a fix.

## Root Cause

Asymmetric read shapes between two values that both feed intent-submission math:

- `ratesController.rateForEntryCurrency()` reads rate *live* from an `@Observable` main-actor dict (`cachedRates`). Every read hits the current value; stream updates propagate.
- `selectedBalance.stored.supplyFromBonding` reads supply from a captured `StoredBalance` struct, loaded from SQLite at `refreshSelectedBalance()` time. The struct does not update when a later stream tick rewrites the SQLite row — it's frozen.

At submit time, `SendCashOperation.getVerifiedState()` fetches the proof from the `VerifiedProtoService` actor cache — always fresh. So client computes `(quarks, nativeAmount)` from the stale supply snapshot, attaches a proof with the fresh supply, and the server's re-computation `sell(quarks, proof.supply) × proof.rate` doesn't match. Rejection.

Fix: mirror reserve supply into a new `@Observable` dict on `RatesController` (`cachedReserveSupply`) from the same `reserveStatesPublisher` sink that was already writing to SQLite, and read supply via `ratesController.supplyFromBonding(for: mint)` at entry time. Three-line production change in `RatesController.swift` plus a one-line swap in `GiveViewModel.swift` and two in `WithdrawViewModel.swift`.

## What Went Wrong

### Attempt 1: Bind proof to fiat at every submit site (shipped as initial PR)

Added ~78 lines across three call sites (`GiveViewModel.giveAction`, `Session.withdraw`, `Session.createCashLink`), each repeating the sequence `getVerifiedState → guard rate → read supply → computeFromEntered → pass both through`. Also added a new error-dialog method and a `VerifiedState.rate` accessor. Opened PR #181, tested in prod, validated it worked.

Why it seemed reasonable: it forces consistency between fiat and proof by construction at submit time. Why it was overkill: it worked around the symptom without diagnosing the specific asymmetry — it added ceremony at every caller instead of fixing the one read that was shaped wrong.

### Attempt 2: Pivoting to "remove the DB persistence" after Android comparison

When the user said the fix felt like overkill and asked what was actually stale, I dispatched four sub-agents against the Android repo, found that Android has only one source for reserve state (in-memory `VerifiedProtoManager`), and confidently framed this as "iOS has two caches, Android has one — the fix is to remove the SQLite column." This was a leap from one finding ("Android doesn't persist reserves") to a sweeping prescription ("iOS should remove persistence").

Why it seemed reasonable: Android parity is a useful anchor; the two-cache architecture was a real tension. Why it was wrong: persistence isn't the bug. The SQLite column exists for good reasons (cold-launch display). The actual bug was one specific read shape — a captured struct snapshot where a live read was needed.

### Attempt 3: Confident theory churn

Each time the user pushed back, I pivoted to a new theory and pitched it with the same confidence as the last: "streaming drift between entry and submit" → "two caches drift" → "remove persistence" → "bind proof to fiat in the type." Every pivot was pattern-matching on the user's pushback rather than re-reading the code.

The user called this out directly: *"everything you speak with confidence, and I ask something you completely change your mind and speak confidently again... this is making things even worse."* That was the moment the process finally changed — I stopped theorizing and actually verified claims against code.

## Lessons

1. **Diagnose before prescribing.** Before proposing a fix, isolate the exact lines where the two divergent values come from. In this case, a 30-second read of `GiveViewModel.enteredFiat` and `RatesController.sink` would have exposed the read-shape asymmetry (live vs. snapshot) — no four-agent investigation needed.

2. **When pushed back, don't pivot — verify.** A new confident theory without new evidence is pattern-matching, not engineering. If the old theory is wrong, the honest move is "I was wrong; here's what I'd need to check before claiming a new one." Alternatives-menus ("Direction A/B/C") are a hedge, not analysis.

3. **Ceremony at call sites is a smell.** If a fix means "at every submit site, do this dance to stay consistent," the invariant is living in discipline instead of in a type or a read path. Look one level deeper — there's usually a single asymmetric read you can fix once.

4. **Cross-project comparisons are data, not prescriptions.** Android's design answered "can iOS's bug happen the same way?" (no, because they have one source). It did NOT answer "should iOS remove its second source?" — that's a different question with its own tradeoffs (cold-launch display was the reason). Don't let parity arguments paper over a local diagnosis.

5. **"I don't know with the confidence I was projecting" is a valid answer.** Saying so cost nothing and would have saved the user from three rounds of bad pitches.
