# TSan aborts the app under test — analysis

**Date:** 2026-08-25 (amended same day — the scope is wider than the original title implied;
resolved 2026-09-22)

> **Status (2026-09-22): the abort no longer reproduces.** Two independent `Sanitizers` runs at
> `e10472dd` finished on a single host process with no TSan output at all. Everything below is kept
> as the record of what the abort was and how it was diagnosed; it no longer describes the current
> runtime. See [The abort no longer reproduces](#the-abort-no-longer-reproduces-2026-09-22).
> Step 6a of the release skill is a hard gate again as of the same date.

**Symptom:** any authenticated `FlipcashUITests` run under the `AllTargets` plan loses the app
within seconds. XCUITest reports `Failed to get matching snapshots: Lost connection to the
application (pid N)` or `Application com.flipcash.app.ios is not running`; `runningboardd` logs
`termination reported by launchd (0, 0, 16896)` — wait status 16896 is exit code 66, Thread
Sanitizer's default `exitcode`.

**It is not confined to UI tests.** The `Sanitizers` plan added to work around this aborts as well,
and so does each of its two targets run alone. Every unsanitized run of the same tests passes. The
UI-test analysis below is intact as far as it goes; the scope claim it carried was wrong. Evidence
in [The unit targets abort too](#the-unit-targets-abort-too), and what the release checklist does
about it in [Amended](#amended-what-the-release-checklist-does-with-sanitizers).

## It is not a data race

No race report is ever produced. With `log_path` pointed at a stable directory and `verbosity=1`,
every `tsan.Flipcash.<pid>` file across runs with `halt_on_error=1`, `halt_on_error=0` and
`abort_on_error=1` contains only the 1362-byte startup banner. The exit code is 66 in all three
cases, including `halt_on_error=0`, which a race report would not produce.

Turning off TSan's own fault handlers lets the system crash reporter capture what actually
happens. Two runs from different entry points, two crash reports, one signature — a bad access at
address `0x10` on the main thread, entirely inside `libclang_rt.tsan_iossim_dynamic.dylib`:

```
os_unfair_lock_lock                                  <- faults here, address 0x10
__tsan::SlotLock(ThreadState*)
__tsan::TraceSwitchPartImpl(ThreadState*)
__tsan::TraceRestartFuncEntry(ThreadState*, unsigned long)
__tsan::ScopedInterceptor::ScopedInterceptor(...)
wrap_os_unfair_lock_lock_with_options
__sanitizer::InternalFree(...)
__tsan::DoReset(ThreadState*, unsigned long)
__tsan::SlotAttachAndLock(ThreadState*)
__tsan::Acquire(ThreadState*, unsigned long, unsigned long)
<intercepted call>
```

The mechanism: `DoReset` reclaims TSan's epoch space by detaching every thread's slot, so
`thr->slot` is null for the duration. While detached it frees the old trace parts through
`__sanitizer::InternalFree`, whose Darwin allocator path calls `os_unfair_lock_lock_with_options`
— itself an intercepted function. The interceptor's `ScopedInterceptor` constructor pushes a
function entry into the trace, that trace part is full, so `TraceSwitchPartImpl` calls
`SlotLock(thr)`, which loads the mutex at offset `0x10` of the null slot. TSan re-enters its own
interceptors from inside `DoReset`.

The two reports differ only in which intercepted function was running:

| pid | intercepted call under `Acquire` | reached from |
|---|---|---|
| 50453 | `wrap_os_unfair_lock_lock` | `CALayerGetSuperlayer` <- `-[UIView superview]` <- `-[UINavigationBarAccessibility _accessibilityFetchCachedNavBarElements]` |
| 59396 | `wrap_dispatch_once` | `_AXSAutomationLocalizedStringLookupInfoEnabled` <- `UIAXRuntimeConvertOutgoingParameterizedValue` |

Different intercepted functions, different callers, same fault — it follows `DoReset`, not any
particular app code.

## Why it surfaces fastest on UI tests

Both stacks sit under `-[NSObject(UIAccessibilityAutomation) _accessibilityUserTestingSnapshotWithOptions:]`,
driven by `XCTAutomationSupport`'s snapshot request over `AXRuntime`. That traversal is a single
synchronous main-thread burst of many thousands of intercepted sync calls, so it both consumes
epoch space fast enough to trigger `DoReset` and maximises the chance that the interceptor
re-entered inside `DoReset` finds its trace part exactly full.

> **Corrected 2026-08-25 (same day).** This section originally claimed "App-hosted unit tests take
> no accessibility snapshots and have run clean under TSan", and the change below was built on it.
> That claim is wrong — the unit targets abort too. The snapshot burst is what makes the UI-test
> case fast and reliable, not what makes it possible: ordinary unit-test execution reaches
> `DoReset` on its own, just later. See [The unit targets abort too](#the-unit-targets-abort-too).

The screen does not matter. It has been observed opening the region picker from the wallet
balance header, switching to the Chats tab, and on the Amount to Tip keypad before any picker
opens.

## The unit targets abort too

The `Sanitizers` plan does not survive a run either, so scoping TSan to the unit targets did not
avoid the crash — it only moved it. Seven runs, all on `libclang_rt.tsan_iossim_dynamic.dylib`
from Xcode's clang 21 against the iOS 27.0 simulator:

```
xcodebuild test -scheme Flipcash -destination 'platform=iOS Simulator,name=iPhone 17' -testPlan Sanitizers
```

Every one exits 65, and every one loses the host mid-run and restarts it. Five of the seven carry
the same banner the UI tests produced — `ThreadSanitizer:DEADLYSIGNAL` followed by
`ThreadSanitizer: nested bug in the same thread, aborting.`, then one `Restarting after unexpected
exit`. The two `-only-testing:FlipcashTests` runs aborted and restarted with no banner in the
xcodebuild log at all, so the banner is corroboration rather than the thing to test for. Failures
are reported as "The test runner exited with code 66 before finishing running tests"; 66 is TSan's
default `exitcode`.

| run | scope | failing tests | ran before abort | after restart | data races |
|---|---|---|---|---|---|
| 1 | both targets | 1186 | 575 | 62 | 0 |
| 2 | both targets | 1351 | 578 | 62 | 0 |
| 3 | both targets | 1136 | 571 | 62 | 0 |
| 4 | `-only-testing:FlipcashCoreTests` | 799 | 111 suites | — | 0 |
| 5 | `-only-testing:FlipcashCoreTests` | 398 | 111 suites | — | 0 |
| 6 | `-only-testing:FlipcashTests` | 597 | 580 | 62 | 0 |
| 7 | `-only-testing:FlipcashTests` | 613 | 564 | 62 | 0 |

**Neither target completes on its own.** Both bundles load into a single `Flipcash` host process,
so within the combined plan one abort takes both down — but that is not the whole explanation,
because each target aborts alone as well. There is no narrower scope that finishes.

**No run reported a race.** `WARNING: ThreadSanitizer: data race` appears zero times across all
seven, and no test recorded an issue. The unit targets are in exactly the position the UI tests
were: TSan kills the host before producing the output it exists to produce.

**Every reported failure is a casualty, not a finding.** The abort lands mid-run and xcodebuild
marks everything still in flight as failed. In run 1 the first launch (pid 57682) passed 575 tests
and then reported 677 failures, every one of them at `(0.000 seconds)` — they never executed. The
restarted launch (pid 57866) ran 62 tests with zero failures. Across all seven runs, not one
failure has a non-zero duration and not one records an issue. The `-only-testing:FlipcashCoreTests`
runs make it starkest: 111 suites passed, 0 suites failed, 0 issues recorded — and 799 tests
reported as failing.

The blast radius is the only thing that varies, and it varies widely: 1136–1351 failing tests in
the combined runs here, against 15 in the report that opened this investigation. What gets killed
depends on what happens to be in flight when `DoReset` fires. The abort point itself is stable —
roughly 575 tests into the combined run, every time.

The control settles the attribution. The same two targets with TSan off pass end to end:

```
xcodebuild test -scheme Flipcash -destination 'platform=iOS Simulator,name=iPhone 17' \
  -testPlan AllTargets -only-testing:FlipcashTests -only-testing:FlipcashCoreTests
```

Exit 0, `** TEST SUCCEEDED **`, 1324 passed, 0 failed, one host process, no restart, and no
repetition consumed despite `AllTargets`' `retryOnFailure` being available. Nothing is wrong with
the tests.

A stable abort point is also the one piece of value left here. TSan does instrument the prefix it
reaches, and a race in those first ~575 tests would still be reported; that is how the zxing
Reed-Solomon race was caught in [2026-07-27](2026-07-27-xcode27-swift64-support.md). Everything
ordered after the abort point gets no TSan coverage at all.

## Why a suppression file cannot fix it

Suppressions are consulted when TSan builds a report. This process never reaches report
generation — it faults in slot bookkeeping — and `race:`/`mutex:` entries do not stop an
interceptor from running.

Nor is there a flag that avoids the path. Dumping the runtime's own `help=1` output shows
`ignore_noninstrumented_modules` and `ignore_interceptors_accesses` are already `true` by default
on Darwin, and both gate reporting and shadow accesses rather than the trace bookkeeping in
`ScopedInterceptor`. `history_size` reports `Current Value: 0x0` — inert in TSan v3, which uses
fixed trace parts.

Toolchain: `libclang_rt.tsan_iossim_dynamic.dylib` from Xcode's clang 21, iOS 27.0 simulator.

## Change

TSan stays on for the targets where it produces reports, and comes off the run where it kills the
app before producing any.

- `FlipcashTests/Sanitizers.xctestplan` (new) — `FlipcashTests` + `FlipcashCoreTests`,
  `threadSanitizerEnabled: true`. It drops `AllTargets`' `retryOnFailure` repetition: a race that
  only trips on one attempt is the finding, so retrying until green would throw it away.
- `FlipcashTests/AllTargets.xctestplan` — `threadSanitizerEnabled: false`, all three targets
  unchanged, so `-testPlan AllTargets` still covers UI tests in one run.
- `Flipcash.xcscheme` — the new plan added to `<TestPlans>` so `-testPlan Sanitizers` resolves.

`Scripts/test.sh` passes no `-testPlan`, so targeted runs use `AllTargets` and are no longer
sanitized. Use `-testPlan Sanitizers` to run the unit targets under TSan. The release checklist
runs both plans.

### Amended: what the release checklist does with `Sanitizers`

> **No longer in force (2026-09-22).** The inconclusive rule below was deleted from step 6a when
> the plan started passing; it is kept here as the record of a decision, not as guidance. Do not
> apply it. A `Sanitizers` run that does not exit 0 now stops the release.

The change above assumed `Sanitizers` would pass. It does not, and it cannot be made to — no
narrower scope finishes. Three options were on the table: drop the plan, narrow it to whatever
still completes, or keep it and stop treating the abort as a failure.

Narrowing is out on the evidence — runs 4–7 above show neither target completes alone.

Dropping it would give up the prefix TSan still instruments, which is real coverage and the only
TSan surface left in the repo. So the plan stays, and the release checklist stops treating the
abort as a release blocker. `Any failure → STOP` cannot stand for a step that fails every time; a
gate that can never pass is one the operator learns to wave through, which is worse than not
running it.

The abort is separable from a real finding by signature, so this is a decidable check rather than a
judgement call. Treat the run as **inconclusive** — not failed — when all of these hold:

- no `WARNING: ThreadSanitizer: data race` in the log,
- `ThreadSanitizer:DEADLYSIGNAL` and `nested bug in the same thread` present,
- every reported failure at `(0.000 seconds)`, and no test recording an issue.

Anything else — a race report, or a failure with a real duration — is a genuine finding and still
stops the release. Step 6 of [the release skill](../skills/release/SKILL.md) carries the
commands.

Revisit when a newer Xcode ships a fixed TSan runtime: if `Sanitizers` starts passing end to end,
restore it as a hard gate and delete the inconclusive branch.

**That happened on 2026-09-22** — see [The abort no longer reproduces](#the-abort-no-longer-reproduces-2026-09-22)
for the evidence, and for why the gate has not been hardened yet.

## The abort no longer reproduces (2026-09-22)

The `Sanitizers` plan now completes. Two independent runs at `e10472dd`, both
`-destination 'platform=iOS Simulator,name=iPhone 17'` against iOS 27.0, agree on every number the
diagnosis above turned on:

(Numbered separately from the seven aborting runs above: these are run A, reported by the person
who spotted the change, and run B, an independent re-run from a clean worktree.)

| | run A | run B |
|---|---|---|
| tests total | 2760 | 2760 |
| passed / failed / skipped | 2753 / 2 / 5 | 2753 / 2 / 5 |
| `ThreadSanitizer` anywhere in the log | 0 | 0 |
| `ThreadSanitizer:DEADLYSIGNAL` | 0 | 0 |
| `nested bug in the same thread` | 0 | 0 |
| failures at `(0.000 seconds)` | 0 | 0 |
| distinct host pids | 1 | 1 (`iPhone 17 - Flipcash (8142)`) |

Run B's totals are read from the `.xcresult` rather than the streamed log: `totalTestCount` 2760,
`passedTests` 2753, `failedTests` 2, `skippedTests` 5. Suite counts are left out of the table
because they depend on how you ask: the same `.xcresult` reports 370 suites directly under the two
bundles and 381 counting nested ones, while the streamed log shows 249 `Test suite '…' started`
lines for `FlipcashTests` alongside Swift Testing's own "132 suites" for `FlipcashCoreTests`. The
test counts are the ones to compare between runs.

One host pid is the load-bearing number. All seven runs in
[The unit targets abort too](#the-unit-targets-abort-too) lost the host mid-run and restarted it,
and two of them dropped the banner while still aborting — so the pid count is what that section
said to trust, and it now says the runner survived.

TSan was genuinely on. `FlipcashTests/Sanitizers.xctestplan` still carries
`"threadSanitizerEnabled": true` in `defaultOptions`, and `testTargets` still lists both
`FlipcashTests` and `FlipcashCoreTests`. Zero `ThreadSanitizer` matches is an instrumented run with
nothing to report, not a missing runtime: the same grep returned the banner on five of the seven
2026-08-25 runs.

No data race was reported. That was true of the aborting runs too, but it now means something —
the run reached the end instead of dying around test 575, so the roughly 2200 tests that used to
get no TSan coverage at all were covered this time.

### The exit code is still 65, for a different reason

Both runs exit 65, and both fail exactly two tests, on a wall-clock deadline while the assertion
about behaviour passes:

- `GalleryScannerTests/budgetIsRespected()` — `Expectation failed: elapsed < 2.0`,
  `elapsed → 13.849`. The `guard case .cancelled` ahead of it did not fire, so the budget did end
  the search.
- `GalleryScannerTests/qrCodeDecodes()` — `Expectation failed: elapsed < 3`, `elapsed → 13.834`.
  The `guard case .url` and the `url ==` expectation both passed, so the QR pass did win the race
  against the ladder.

Both feed the scanner a deliberately large frame — 3024x4032 and 2400x2400 — precisely so the
work is CPU-bound, and TSan's instrumentation stretches it past bounds of 2s and 3s. Fixed the
same day in `b05cb270` (#829) by asserting the outcome instead of the clock; see
[What this changed](#what-this-changed).

### `recorded an issue` does not detect a real failure in `FlipcashTests`

Count C from [the release skill](../skills/release/SKILL.md)'s step 6a reads **0** on this run,
with two genuinely failing tests in it. The skill calls C "the one that carries the weight", on the
grounds that every target here is Swift Testing so a real failure always records an issue. That
does not hold for `FlipcashTests` as xcodebuild streams it.

The two targets report through different formatters in the same log. `FlipcashCoreTests` emits
Swift Testing's own output (`◇`/`✔`, ending `Test run with 1022 tests in 132 suites passed`).
`FlipcashTests` emits the XCTest bridge form, `Test case '<name>' failed on '<device>' (15.475
seconds)`, which never contains the phrase. All six `issue` matches in run B's 44,782-line log are
unrelated: `CLANG_UNDEFINED_BEHAVIOR_SANITIZER_TRAP_ON_SECURITY_ISSUES` build settings and
`CMSIssuerAndSerialNumber.swift` filenames.

Count B caught both (`B = 2`), which is what it is there for, so the classification still reaches
the right verdict and the 2026-08-25 conclusion is unaffected — that rested on every failure
sitting at `(0.000 seconds)`, which is B. But for `FlipcashTests` B is the primary signal rather
than the backstop the skill describes, and the wording should be corrected when step 6a is revised.

### An unrelated 600-second tail

Run B reported `687.292 elapsed -- Testing started completed`, most of it after the tests had
finished: `IDETestOperationsObserverDebug: Failure collecting diagnostics from simulator: Timed out
after 600.0 seconds`. Subtract that and the test phase is the same order as run A's 73.9 seconds.
Post-run diagnostics collection, not TSan — worth knowing before reading a twelve-minute run as a
hang.

### What this changed

Step 6a of [the release skill](../skills/release/SKILL.md) is a hard gate again, and the
inconclusive branch is gone from it and marked out of force in
[Amended](#amended-what-the-release-checklist-does-with-sanitizers) above. The three counts stay
as the way to report a run — A for races, B for tests reported failed, C for Swift Testing issues
recorded — they just no longer have an "inconclusive" verdict to reach.

`GalleryScannerTests` was the thing holding it. Both deadline assertions were replaced with
outcome assertions in `b05cb270` (#829) — `budgetIsRespected()` now asserts only `.cancelled`, and
`qrCodeDecodes()` scans the larger frame on the same 0.5s budget and asserts `.url`, so TSan
changes how long they take and not what they claim.

The run at `b05cb270`, same simulator, is the one that closed it:

```
** TEST SUCCEEDED **   exit 0
2760 tests: 2755 passed, 0 failed, 5 skipped, 90.5s
A = 0   B = 0   C = 0
one host pid: iPhone 17 - Flipcash (72940)
```

Step 6a is a hard gate again and the inconclusive branch is gone from it. The gate is now "exit 0,
or stop" rather than a verdict assembled from the counts, which closes a hole the count-only form
would have had: an abort produces `A = 0`, `C = 0` and a `B` made entirely of `(0.000 seconds)`
casualties, so a gate reading only the counts would have passed the very failure this doc is
about. B also no longer filters out zero-duration failures — that filter existed to screen out
casualties, and with the abort gone it would only hide a real test that fails fast.

## One failure the crash was hiding

With the app surviving, `CurrencySelectionSmokeTests` failed three runs in a row at
`assertMainScreenReached()`. A screenshot taken while it was stuck shows the app's own "Push
Notifications Required" screen still up: `allowPushNotificationsIfNeeded()` waited 2s for its OK
button, but after a fresh sign-up that screen is gated on account registration and appears later
than that — around t=15s in these runs — so the helper returned early and the test then waited out
30s for a tab bar behind a modal. The helper now waits up to 30s for either the OK button or the
tab bar, whichever lands first, which keeps the already-granted case as fast as it was. Unrelated
to TSan; it was simply unreachable while the app died first.

## Reproducing

> **Superseded 2026-09-22.** The abort no longer reproduces, so the recipe below no longer produces
> it. The classification commands are still how to read a `Sanitizers` run, and the pid count is
> still how to tell a surviving runner from a restarted one — they now return the clean values.

The unit-target abort needs no setup — run the plan and read the classification:

```
xcodebuild test -scheme Flipcash -destination 'platform=iOS Simulator,name=iPhone 17' \
  -testPlan Sanitizers 2>&1 | tee /tmp/sanitizers.log
grep -c 'WARNING: ThreadSanitizer: data race' /tmp/sanitizers.log   # 0 = no finding
grep -c 'nested bug in the same thread' /tmp/sanitizers.log         # 1 = the known abort
grep ' failed on ' /tmp/sanitizers.log | grep -vc '(0.000 seconds)' # 0 = all casualties
```

Note that the crash reports the UI-test investigation relied on are not available here: TSan's own
fault handlers are on under the plan, so it exits 66 with nothing written to
`~/Library/Logs/DiagnosticReports/`. The `DEADLYSIGNAL` banner reaches the xcodebuild log in most
runs but not all — two of the seven runs above dropped it while still aborting and restarting, so
count host pids rather than trusting the banner:

```
grep -oE 'iPhone 17 - Flipcash \([0-9]+\)' /tmp/sanitizers.log | sort -u
```

More than one pid means the runner died and restarted.

For the UI-test case, patch `UITargetAppEnvironmentVariables['TSAN_OPTIONS']` on the `IsUITestBundle` target of a built
`.xctestrun`, then `test-without-building`. Set `log_path` to the device-level tmp directory
(`<device>/data/tmp/tsan`), not the app data container — the container path changes on reinstall
— plus `log_exe_name=1` and `verbosity=1`. Turning off TSan's fault handlers is what lets the
reports reach `~/Library/Logs/DiagnosticReports/Flipcash-*.ips`; leave them on and TSan exits 66
with nothing written. Check the app's exit status with:

```
xcrun simctl spawn <UDID> log show --style compact --last 10m \
  --predicate 'process == "runningboardd" AND eventMessage CONTAINS "termination reported by launchd"'
```
