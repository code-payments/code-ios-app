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
`.timeLimit`) failed every time. Run together on their own they pass in under 0.2s, so the main
actor was starved during the full plan. These failures exit 65 even when no race fires.

The stall is not one test's problem. After the guards it moved between tests, and each one
waits on wall-clock time while it happens (see Outcome). It is still the gate's blocker, and its
cause is unknown. `sample` could not attach to the simulator host from the agent's shell.

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

**The plan still does not exit 0 reliably.** That's now down to the main-actor stall above, not
TSan.

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
