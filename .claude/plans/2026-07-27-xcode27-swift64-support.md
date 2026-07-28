# Xcode 27 / Swift 6.4 local test support — root-cause analysis & plan

**Date:** 2026-07-27
**Context:** `xcodebuild test -scheme Flipcash -testPlan AllTargets` fails locally on Xcode 27.0
(beta, Swift 6.4). Xcode Cloud is green on the same commit and nothing changed there, so the
shipping 1.17.0 binary is fine — this is a **local-toolchain support** problem.

Toolchain in use: Xcode 27.0 (27A5194q), Apple Swift 6.4. Project targets Xcode 16.x / Swift 6.0.

## Symptoms (from the AllTargets run)
- `FlipcashCoreTests` (Swift Testing) ran to completion: **3 issues**, all in
  `ExchangedFiatServerConsistencyTests.bondedTokenServerConsistency` (3/4 bonded cases).
- App-hosted `FlipcashTests`: **1020 tests reported `failed (0.000 seconds)`**, 190 passed —
  the signature of a **test host that crashed mid-run** and cascaded. Log shows
  "Restarting after unexpected exit" ×5.
- `FlipcashUITests`: 5 tests failed, 3 at `BaseUITestCase.swift:107` "Expected to reach the main screen".

## Root cause A (dominant): non-thread-safe zxing C++ encoder + TSan
`AllTargets.xctestplan` has `threadSanitizerEnabled: true`. All **four** Flipcash crash reports today
(`~/Library/Logs/DiagnosticReports/Flipcash-2026-07-27-*.ips`) are **TSan `SIGABRT` data-race aborts
inside the vendored zxing Reed-Solomon encoder**:
- `zxing::GenericGF::checkInit()` — lazy init of shared static Galois-field tables (`QR_CODE_FIELD_256`)
- `zxing::Counted::retain()` — zxing refcount is a **non-atomic `int`**
- `std::vector<int>::resize`/swap — `ReedSolomonEncoder` cached-generators vector mutated concurrently

Driver: the **new Tips `TipCodeEncodingTests`** (`FlipcashTests/TipCodeEncodingTests.swift`, added
#512/#523) is a `@Suite` with **no `.serialized` trait** and several **parameterized** `@Test`s
(4 userIDs) that call `KikCodes.encode`/`decode`. Swift Testing runs parameterized cases in parallel
on the cooperative pool (stack shows `@Sendable @async` on `com.apple.root.user-initiated-qos.cooperative`),
so multiple encodes hit the shared zxing globals at once → race → TSan aborts the host → cascade.
The app also encodes a code during UI-test launch, so the **UI "couldn't reach main screen" failures
are the same root cause** (17:02 TSan crash is in the UI window).

**Why green on Cloud / red locally:** data races are timing-dependent; TSan only fires when accesses
actually overlap. Swift 6.4's cooperative-pool scheduling reliably overlaps them locally.

Fix surface: single facade — `CodeScanner/CodeScanner/Code.mm`:
- `+[KikCodes encode:]` (line 23) and `+[KikCodes decode:]` (line 35) are the only entry points.
- CodeScanner is vendored/editable (NOT under `Generated/`).

### Fix options for A
1. **(Recommended) Serialize the facade** — a static lock (`os_unfair_lock` / serial `dispatch_queue`
   / `@synchronized`) around the body of `+encode:`/`+decode:` in `Code.mm`. Makes the encoder safe for
   ALL concurrent callers (tests + app launch); one-file change; fixes the cascade and the UI failures.
   The `Counted`/cache races happen on every concurrent encode (not just first init), so a one-time
   warm-up is insufficient — full mutual exclusion of encode/decode is required.
2. Add `.serialized` to `TipCodeEncodingTests` — fixes only the unit test, NOT app-launch/UI crashes
   or any real production concurrency. Insufficient alone; fine as defense-in-depth.
3. Make zxing internals thread-safe (atomic `Counted`, guarded `GenericGF` init) — true root but edits
   vendored zxing broadly. Not worth it; the app never needs parallel encodes.

## Root cause B (independent): over-strict Decimal round-trip test vs swift-foundation
`ExchangedFiatServerConsistencyTests` (new, #514) asserts a **buy-then-sell bonding-curve round-trip is
exactly equal**: `fromEntered.nativeAmount.value == fromQuarks.nativeAmount.value` — comparing two
**unrounded, FX-converted `Decimal`s** (`compute(fromEntered:)` uses the entered native; `compute(onChainAmount:)`
derives native from `bondingCurve.sell`). Swift 6.4 ships the rewritten `swift-foundation` `Decimal`
whose rounding differs subtly from the legacy C `NSDecimal`, so the strict `==` now fails on the 3
non-trivial bonded cases. This comparison also violates the repo's **Money Rule 4** ("never compare an
unrounded converted Decimal to anything") / **Rule 5** (compare display-rounded native vs display-rounded native).

### Fix approach for B (measure first)
1. Run the suite in isolation capturing the actual two values per failing case.
2. If they agree at **display precision**, the test is simply too strict → compare display-rounded
   native (Money Rule 5), matching `CoinbaseDepositOperation.checkMinimum`'s shape. Not a shipping bug.
3. If they diverge **beyond** display precision → real bonding-curve buy/sell asymmetry → investigate
   `ExchangedFiat.compute` before touching the test.

## Proposed change set
1. `Code.mm`: serialize `+encode:`/`+decode:` behind a static lock. (fixes A + UI)
2. (optional) `TipCodeEncodingTests`: add `.serialized` trait as defense-in-depth.
3. `ExchangedFiatTests.swift`: after measuring, compare at display precision per Money Rule 5
   (or open a real-bug investigation if divergence exceeds display precision).

Each fix gets a failing-first check: A is verifiable by re-running the app-host bundle under TSan;
B by the isolated suite.

## APPLIED + VERIFIED (2026-07-27)

**A — facade lock (`CodeScanner/CodeScanner/Code.mm`):** wrapped `+encode:`, `+decode:`, and
`+scan:width:height:quality:` bodies in `@synchronized (self)` (class-wide recursive lock). This is
Flipcash's own ObjC++ facade, NOT vendored zxing (`src/zxing/` untouched; the regen script doesn't
rewrite `Code.mm`). Chose the facade over `.serialized` on the test because the app itself races zxing
during UI-test launch (a `std::vector` race at 17:02), so only serializing the real encoder fixes both
the unit-test cascade AND the UI failures.

**B — display-precision comparison (`ExchangedFiatTests.swift`):** replaced exact
`fromEntered.nativeAmount.value == fromQuarks.nativeAmount.value` with both sides
`.rounded(to: rate.currency.maximumFractionDigits)` (Money Rule 5; mirrors `UserFlags.swift:105` /
`CoinbaseDepositOperation.checkMinimum`). Measured divergence was pure rounding dust — 1.4e-12 (326.79),
2.8e-13 (100), 7.2e-10 (10000) — identical at any user-visible precision. Buy→sell through integer-quark
quantization is not an exact inverse, so exact `==` was a false invariant (and a Money-Rule-4 violation).

**Verification:** one TSan-enabled run (`AllTargets` plan) of both suites →
`** TEST SUCCEEDED **`, 0 TSan warnings, 0 `failed (0.000s)`, 0 unexpected-exit restarts.
Pre-fix the same `TipCodeEncodingTests` under TSan aborted the host and cascaded.

## FOLLOW-UP: production Decimal audit (in progress)
The swift-foundation `Decimal` rounding change is what flipped B green→red; audited `Flipcash/` +
`FlipcashCore/Sources/` for Money-Rule-4 violations that could bite production the same way.

**Outcome: no correctness regression from the rewrite.** Production money comparisons are either
quark-domain (integer-exact, impl-independent) or entered-verbatim (string-parsed) vs round-number
server limits (identical under either Decimal impl). Sub-cent flips only reach cosmetics (appreciation
arrow sign in `BalanceScreen`/`StoredBalance`, pre-selected currency, log interpolations) — never money.
A 30-site sweep over-flagged "unrounded"; verified the load-bearing ones by hand (`ExchangedFiat.swift:163/179`
are drift-tolerant by design / assignment-driven, not arithmetic-coincidence).

**One real finding (pre-existing Rule-3 violation, not toolchain-blocking):**
`CoinbaseDepositOperation.swift:131` sends `"\(amount.usdfValue.value)"` (an UNROUNDED FX division) onto
the Coinbase `createOrder` wire — a non-USD entry emits a 15+ digit string. Rule 3 forbids raw Decimal on
an external wire; the swift-foundation `Decimal.description` change makes the emitted string less
predictable. Fix separately (format to USD 2dp) — outward-facing, needs sign-off. NOT done here.
