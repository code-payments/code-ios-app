# TSan aborts the app under test during UI tests — analysis

**Date:** 2026-08-25

**Symptom:** any authenticated `FlipcashUITests` run under the `AllTargets` plan loses the app
within seconds. XCUITest reports `Failed to get matching snapshots: Lost connection to the
application (pid N)` or `Application com.flipcash.app.ios is not running`; `runningboardd` logs
`termination reported by launchd (0, 0, 16896)` — wait status 16896 is exit code 66, Thread
Sanitizer's default `exitcode`.

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

## Why it lands on UI tests specifically

Both stacks sit under `-[NSObject(UIAccessibilityAutomation) _accessibilityUserTestingSnapshotWithOptions:]`,
driven by `XCTAutomationSupport`'s snapshot request over `AXRuntime`. That traversal is a single
synchronous main-thread burst of many thousands of intercepted sync calls, so it both consumes
epoch space fast enough to trigger `DoReset` and maximises the chance that the interceptor
re-entered inside `DoReset` finds its trace part exactly full. App-hosted unit tests take no
accessibility snapshots and have run clean under TSan — see
[2026-07-27](2026-07-27-xcode27-swift64-support.md), where TSan caught the real zxing race.

The screen does not matter. It has been observed opening the region picker from the wallet
balance header, switching to the Chats tab, and on the Amount to Tip keypad before any picker
opens.

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

## One failure the crash was hiding

With the app surviving, `CurrencySelectionSmokeTests` failed three runs in a row at
`assertMainScreenReached()`. A screenshot taken while it was stuck shows the app's own "Push
Notifications Required" screen still up: `allowPushNotificationsIfNeeded()` waited 2s for its OK
button, but after a fresh sign-up that screen is gated on account registration and appears later
than that — around t=15s in these runs — so the helper returned early and the test then waited out
30s for a tab bar behind a modal. The helper now waits up to 30s for either the OK button or the
tab bar, whichever lands first, which keeps the already-granted case as fast as it was. Unrelated
to TSan; it was simply unreachable while the app died first.

Revisit when a newer Xcode ships a TSan runtime that does not re-enter its interceptors from
`DoReset`.

## Reproducing

Patch `UITargetAppEnvironmentVariables['TSAN_OPTIONS']` on the `IsUITestBundle` target of a built
`.xctestrun`, then `test-without-building`. Set `log_path` to the device-level tmp directory
(`<device>/data/tmp/tsan`), not the app data container — the container path changes on reinstall
— plus `log_exe_name=1` and `verbosity=1`. Turning off TSan's fault handlers is what lets the
reports reach `~/Library/Logs/DiagnosticReports/Flipcash-*.ips`; leave them on and TSan exits 66
with nothing written. Check the app's exit status with:

```
xcrun simctl spawn <UDID> log show --style compact --last 10m \
  --predicate 'process == "runningboardd" AND eventMessage CONTAINS "termination reported by launchd"'
```
