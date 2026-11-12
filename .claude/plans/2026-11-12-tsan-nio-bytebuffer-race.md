# TSan race in swift-nio ByteBuffer under the Sanitizers plan

**Date:** 2026-11-12, against `origin/main` 345dce1f7

**Symptom:** `xcodebuild test … -testPlan Sanitizers` exits 65. On the 08:38 run, 2588 tests
failed at `(0.000 seconds)` across two host pids. The crash report
(`Flipcash-2026-11-12-083857.ips`) shows SIGABRT from `__tsan::ReportRace → OutputReport →
__sanitizer::Die`. The faulting thread is `nio.nioTransportServices.connectionchannel`, inside
`HTTP2FrameDecoder.append → ByteBuffer._Storage.reallocStorage`. Unlike
[2026-08-25](2026-08-25-tsan-ui-test-crash.md), this is a real race report, not a fault inside
the TSan runtime.

## The full report

Capturing both stacks needs `log_path`. The xcodebuild log shows 0 races because the report goes
to the app's stderr. Run with:

```
TEST_RUNNER_TSAN_OPTIONS="log_path=<sim>/data/tmp/tsan-runN/tsan log_exe_name=1 halt_on_error=0" \
  xcodebuild test[-without-building] … -testPlan Sanitizers
```

Four full runs produced a report in runs 3 and 4 (one each). Run 4, pid 9614:

- **Write**, GCD worker T19: `ByteBuffer._Storage.reallocStorage` ←
  `ByteBuffer.writeImmutableBuffer` ← `GRPCMessageDeframer.append` (GRPCMessageDecoder.swift:137)
  ← `GRPCStreamStateMachine.clientReceive` ← `GRPCClientStreamHandler.channelRead` ←
  `HTTP2StreamChannel.deliverPendingReads` ← … ← `StateManagedNWConnectionChannel.dataReceivedHandler`.
- **Previous read**, GCD worker T64: `ByteBuffer._slicedStorageBuffer` ←
  `withUnsafeReadableBytes` ← `GRPCNIOTransportBytes.withUnsafeBytes` ← `Message.init(serializedBytes:)`
  ← `ProtobufDeserializer.deserialize` ← `ClientStreamExecutor.RawBodyPartToMessageSequence.AsyncIterator.next`
  (a Swift Task).
- **Heap block** (64 bytes, the `_Storage` object; the access is `bytes` at +0x18), allocated on
  T53 by `HTTP2FrameDecoder.SimulatingDataFramesParserState.accumulate`.

The original 08:38 crash had a different write site (`HTTP2FrameDecoder…accumulate` instead of
`GRPCMessageDeframer.append`). Both end in `reallocStorage` on a `ByteBuffer` storage that a
response deserializer read earlier.

## Cause: refcount ordering TSan cannot see

`ByteBuffer._setBytes` (swift-nio 2.92.0, `ByteBuffer-core.swift:494`) only reaches
`reallocStorage` after `isKnownUniquelyReferenced(&self._storage)` passes. Otherwise it copies.
The deserializer's slice holds a reference to the same `_Storage` while it reads, so the
in-place write can only happen after that slice is released. The edge that orders read before
write is the Swift refcount: an atomic decrement in `swift_release`, then the uniqueness load.
Both live in libswiftCore, which is not TSan-instrumented, so TSan sees two unordered accesses.

A standalone check confirms TSan reports this pattern. It's a 30-line program: a struct over a
class storage, one thread reads then drops its copy, the other spins on
`isKnownUniquelyReferenced` then rewrites the storage pointer, with no locks or semaphores
between them. Built with `xcrun swiftc -sanitize=thread`, it reported `data race` between the
write and the read in 3 of 3 runs on macOS.

So this is a false positive inside swift-nio, not a race in our code. No package bump fixes it:
the pattern is how every CoW type works. No upstream issue was found for these versions (nio
2.92.0, nio-http2 1.46.0, nio-transport-services 1.28.0, grpc-swift-2 2.4.1,
grpc-swift-nio-transport 2.4.4).

## Why unit tests hit it at all: the test host talks to mainnet

The race needs live HTTP/2 response traffic. No unit test opens a real `NWConnection` itself, but
the hosted unit tests did anyway:

- `Client(network:)` and `FlipClient(network:)` start `runConnections()` in `init`. `Container()`,
  `Container.mock`, `Client.mock` and `FlipClient.mock` all build mainnet clients.
- `SessionAuthenticator.startPolling()` ran before the `isRunningTests` guard. It polls flags
  every 30s for every authenticator, including the host app's own and `Container.mock`'s.
- `Session.registerPoller()` (balance, limits and flags every 10s) and the launch
  `updateProfile()` / `syncUserPreferences()` tasks ran for every test `Session`. Only
  `startStreaming()` was guarded.
- `AppDelegate`'s `.active` handler warmed up both channels.

Fix: each of those now returns early under `Container.isRunningUnitTests`, matching
`startStreaming()`. UI tests keep their RPCs. `UnitTestHostPollingTests` asserts that a test
`Session` and `SessionAuthenticator` register no poller; it fails with the guards removed.

Not done: test clients are still live mainnet clients that connect in `init` (see
[Outcome](#outcome)).

## A suppression is the fallback, not the fix

The two write sites share only `ByteBuffer._Storage.reallocStorage`, so a suppression would have
to key on that frame (`race:ByteBuffer._Storage.reallocStorage`). That hides every ByteBuffer
race, real ones included. It would also have to reach the host app through `TSAN_OPTIONS` in the
plan's environment, and how that interacts with the options Xcode injects is unconfirmed.
Removing the traffic removes the trigger without hiding anything.

## A main-actor stall fails the plan separately

In runs 1–4, `PendingReadPointerTests/markSeen_commitsAfterDelay` (45–52s against a 2s
deadline) and `RatesControllerStressTests/concurrentUpdates_doNotTearValues` (its 60s
`.timeLimit`) failed every time. Run on their own they pass in under 0.2s. These failures exit 65
even when no race fires.

### Cause: parallel `@MainActor` tests queue on one TSan-slowed main thread

`FlipcashTests` was `parallelizable` in the plan, so Swift Testing ran its tests concurrently in
one host. Of the 386 test files with suites, 267 are `@MainActor`. Under TSan their work all queues on the
main thread. Every hop back to the main actor waits behind that backlog, so a test that needs
a few hops spends tens of seconds waiting before its own work runs. Any test bounded by wall
clock (`.timeLimit(.minutes(1))` on ten suites, short poll deadlines) fails when it lands
behind the backlog. Which test that is changes from run to run.

Evidence, from one parallel run with `sample <pid> 3` every ~10s on the clone's host
(`sample` does attach when run outside the sandbox):

- **The main thread was 96–100% busy for the whole run.** Idle means a leaf frame of
  `mach_msg2_trap` or a wait call. The time is spread across many tests: collection-view
  reloads, `ChatTranscriptDiffFuzzTests`, `Database.init` schema creation (13.6%, the biggest
  single bucket) and SwiftUI hosting. No single test dominates, and no thread is blocked on a
  lock or semaphore.
- **Non-main threads averaged about 1.5 busy cores of 14.** NIO/Network threads were roughly
  12% of that. So the mainnet connections and other suites' background work aren't starving
  the CPU. The one serial resource is the main thread.
- **Victims stall before their bodies run.** In that run, four `PendingReadPointerTests` cases
  with no waits finished within 8ms of each other at 53.8s. The three
  `Regression_native_amount_mismatch` cases finished at 46.3s, and `scenarioD` hit its 60s
  limit.
- **Serial runs don't stall.** `-parallel-testing-enabled NO` exited 0 in 193s wall clock,
  against 222s for the failing parallel run. Parallelism bought no speed, because the main
  thread is the bottleneck.

`ChatStoreWriteNotificationTests/postReachesObserver` failed in both parallel runs here too
(6.3–6.7s). Darwin notifications are delivered on the main thread, and the test allowed 2s.

The second host pid is not a crash. Xcode runs `.serialized` suites (`AccountManagerTests`,
`BetaFlagsTests`, …) in a separate launch after the parallel pass. Neither run left a
`Flipcash-*.ips`.

### Fix

- **`Sanitizers.xctestplan` sets `FlipcashTests` to `"parallelizable": false`.** This
  serializes the target in process, with no CLI flag needed, so the release-gate command is
  unchanged. `SanitizersPlanTests` reads the plan through `#filePath` and fails if any target
  is parallelizable again. With the setting flipped back, it failed.
- **The two short poll deadlines now wait on their condition.** `markSeen_commitsAfterDelay`
  uses `waitUntil` (90s failure bound). The Darwin notification test's bound went from 2s
  to 90s. `AllTargets` still runs these tests in parallel.
- **`.timeLimit(.minutes(1))` is unchanged.** Run serially, those tests finish well inside it.

## Outcome

All runs on iPhone 17 simulator `CC79E655-F343-4146-ABB7-5A607375DCA5`, built from this branch
on 2026-11-12.

| | Race reports | Exit 0 | Stall failures |
|---|---|---|---|
| Before, runs 1–4 (`log_path`, `halt_on_error=0`) | 2 of 4 | 0 of 4 | 4 of 4 |
| After, 6 runs (same options) | 0 of 6 | 1 of 6 | 5 of 6 |
| After, 2 runs with no `TSAN_OPTIONS` override | 0 of 2 | 1 of 2 | 1 of 2 |

After the change, the stall failures were `RatesControllerStressTests/concurrentUpdates_doNotTearValues`
at its 60s limit (3 runs; these runs also show a second host pid), both
`UpdateAvailabilityTests` toast tests at ~47s (2 runs), and
`PendingReadPointerTests/markSeen_commitsAfterDelay` at 45s (1 run). No crash reports.

At the before rate, 0 of 6 is about a 1.6% chance, so the guards very likely removed the race's
trigger. They don't remove the connections. `lsof` on the test host during a run still showed
TLS connections to mainnet, growing from 3 at the start to more than 10. Tests call
`Container()` directly at 54 sites, and each builds fresh mainnet clients that connect in
`init`. If the race returns, give `Container` and the client mocks a non-connecting unit-test
transport.

### Outcome of the serial plan

These runs used `xcodebuild test-without-building … -testPlan Sanitizers` on a dedicated iPhone 17
simulator (`0ACF2A0A-8B3B-4A82-B42C-F2406685E5B7`, so no other worktree's install could kill the
host), with `TEST_RUNNER_TSAN_OPTIONS="log_path=… log_exe_name=1 halt_on_error=0"`. They were
built from `fix/tsan-test-stall` on 2026-11-12.

| | Exit 0 | Stall failures | Race reports (log / `log_path` / `.ips`) |
|---|---|---|---|
| Parallel plan, runs 1–2 (base `6bd4ad47b`) | 0 of 2 | 2 of 2 | 0 / 0 / 0 |
| `-parallel-testing-enabled NO`, run 3 (base) | 1 of 1 | 0 of 1 | 0 / 0 / 0 |
| Plan `parallelizable: false`, no CLI flag, runs 4–9 | 6 of 6 | 0 of 6 | 0 / 0 / 0 |

Runs 4–9 took 163–203s wall clock, none used a clone, and each passed all 5535 test cases. With
no race in any run, the `log_path` directory stayed empty. That fits a clean run, but it doesn't
prove the capture path works for the clone hosts in runs 1–2.

If a later change makes this plan parallel again, `SanitizersPlanTests` fails. A wall-clock test
that still fails here should wait on its condition (`waitUntil`), not get a longer limit.

## Release skill step 6a

Step 6a counts `WARNING: ThreadSanitizer: data race` in the xcodebuild log, which reads 0 for
this race because the report goes to the host's stderr. Proposed (not applied):

1. Run the plan with `TEST_RUNNER_TSAN_OPTIONS="log_path=<sim data>/tmp/tsan-release/tsan
   log_exe_name=1"` on a fixed simulator UDID, and count A from
   `grep -l 'WARNING: ThreadSanitizer' <dir>/*` as well as the log. Leave `halt_on_error` at the
   default so the gate behaves the same.
2. After the run, list `~/Library/Logs/DiagnosticReports/Flipcash-*.ips` newer than the run's
   start. Any report whose stack contains `__tsan::ReportRace` is a race (A > 0), even when the
   log count reads 0.
3. Classify "host pids > 1" by those two sources before calling it the 2026-08-25 runtime abort.
   That abort leaves only the banner in `log_path`; a race leaves a full report.
