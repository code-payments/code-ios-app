# Poller Background Suspension Fix — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop `Session`'s 10s poller from holding a SQLite write lock when iOS suspends the app, which RunningBoard kills with `0xdead10cc`.

**Architecture:** Two halves, because cancelling alone is provably insufficient — `fetchTransactionLimits` ignores cancellation ([Client+Transaction.swift:324](../../FlipcashCore/Sources/FlipcashCore/Clients/Payments%20API/Client+Transaction.swift)) and no suspension point separates its return from the synchronous write. First, `didEnterBackground()` cancels the poller so no *new* tick starts. Second, `AppDelegate` awaits the tick *already* running before checkpointing, inside the background-task assertion it already takes. `didBecomeActive()` re-arms.

**Tech Stack:** Swift 6, Swift Concurrency (`Task`, structured cancellation), Swift Testing, SQLite.swift, UIKit background-task assertions.

**Triage brief:** [2026-09-20-crash-ffe0f684.md](2026-09-20-crash-ffe0f684.md)

**Branch:** `fix/poller-suspend-db-lock` off `18030428`. Do **not** reuse the `claude/`-prefixed triage worktree branch.

---

## Caveats — read before starting

- **None of the code below has been compiled.** It is written from reading the sources, not from a build. Expect to adjust; treat compile errors as expected feedback, not as a broken plan.
- **The real `Session` is not constructible in tests.** There is no `makeTestSession()` helper, and `MockSession` ([FlipcashTests/TestSupport/MockSession.swift:14](../../FlipcashTests/TestSupport/MockSession.swift)) is a separate class, not the real one. So Task 2 and Task 3 have **no unit test**; the mechanism they rely on is tested in Task 1, and their wiring is verified manually in Task 4. Do not invent a `Session` test — say so instead if asked.
- **Out of scope, deliberately:** adding `withTaskCancellationHandler` to `fetchTransactionLimits` and the other continuation bridges. It would shorten the drain but is not needed to fix the crash, and it touches the network layer. File it separately.

## File Structure

| File | Change | Responsibility |
|---|---|---|
| `FlipcashCore/Sources/FlipcashCore/Utilities/Poller.swift` | Modify | Gains `cancel()` and `waitUntilFinished()` — the drain primitive. |
| `FlipcashTests/Regressions/Regression_ffe0f684.swift` | Create | Proves the drain actually waits for in-flight work. |
| `Flipcash/Core/Session/Session.swift` | Modify | Cancels on background, drains on request, re-arms on foreground. |
| `Flipcash/Core/AppDelegate.swift` | Modify | Runs drain + checkpoint under one assertion. |

---

### Task 1: Give `Poller` a drainable cancel

**Files:**
- Modify: `FlipcashCore/Sources/FlipcashCore/Utilities/Poller.swift`
- Test: `FlipcashTests/Regressions/Regression_ffe0f684.swift` (create)

- [x] **Step 1: Write the failing test**

Create `FlipcashTests/Regressions/Regression_ffe0f684.swift`:

```swift
//
//  Regression_ffe0f684.swift
//  Flipcash
//
//  Symptom:  RUNNINGBOARD 0xdead10cc SIGKILL. Session's 10s poller kept firing
//            after the app backgrounded; a tick's `database.transaction` held a
//            SQLite write lock on the App Group store when iOS suspended us.
//
//  Fix:      Poller gains cancel() + waitUntilFinished(). didEnterBackground()
//            cancels so no new tick starts; AppDelegate awaits the in-flight one
//            inside the background-task assertion before checkpointing.
//

import Foundation
import Testing
@testable import FlipcashCore

/// Tracks whether the poller's action is currently executing.
private actor ActionTracker {
    private(set) var isRunning = false
    private(set) var completedCount = 0

    func begin() {
        isRunning = true
    }

    func end() {
        isRunning = false
        completedCount += 1
    }
}

@Suite("Regression: ffe0f684 – Poller drains in-flight work before suspension", .bug("FFE0F684-681B-44A2-AA12-36FD00D03549"))
struct Regression_ffe0f684 {

    @Test("waitUntilFinished() does not return while an action is still in flight")
    func drain_waitsForInFlightAction() async {
        let tracker = ActionTracker()
        let poller = Poller(seconds: 60, fireImmediately: true) {
            await tracker.begin()
            try? await Task.sleep(for: .milliseconds(200))
            await tracker.end()
        }

        // Let the immediate tick get into the action body.
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await tracker.isRunning)

        poller.cancel()
        await poller.waitUntilFinished()

        // The load-bearing assertion: a waitUntilFinished() that only cancels
        // without awaiting the task would return here with isRunning still true.
        #expect(await tracker.isRunning == false)
        #expect(await tracker.completedCount == 1)
    }

    @Test("cancel() while sleeping stops the loop without running another action")
    func cancel_whileSleeping_runsNoFurtherAction() async {
        let tracker = ActionTracker()
        let poller = Poller(seconds: 60, fireImmediately: true) {
            await tracker.begin()
            await tracker.end()
        }

        // The immediate tick is over; the loop is now in Task.sleep(60s).
        try? await Task.sleep(for: .milliseconds(100))
        #expect(await tracker.completedCount == 1)

        poller.cancel()
        await poller.waitUntilFinished()

        #expect(await tracker.completedCount == 1)
    }
}
```

- [x] **Step 2: Run the test to verify it fails**

```bash
./Scripts/test.sh FlipcashTests/Regression_ffe0f684
```

Expected: **compile failure** — `value of type 'Poller' has no member 'cancel'` / `no member 'waitUntilFinished'`.

This is an API-addition fix, so the first red is a compile error rather than a behavioural failure. That is a weak red on its own. The guard against a false green is the first test's `isRunning == false` assertion: an implementation that cancels without awaiting the task still compiles and still fails that line. Confirm in Step 4 that you did not weaken it.

- [x] **Step 3: Add the two methods**

In `FlipcashCore/Sources/FlipcashCore/Utilities/Poller.swift`, insert between `init` and `deinit`:

```swift
    /// Stops the poller from starting another action.
    ///
    /// An action already in flight runs to completion: `action` is not required to be
    /// cancellation-aware, and the ones we pass are not — `fetchTransactionLimits` bridges a
    /// completion handler through a bare continuation. Pair with ``waitUntilFinished()`` when the
    /// caller needs to know nothing is still running.
    public func cancel() {
        task.cancel()
    }

    /// Waits for an in-flight action to finish.
    ///
    /// Call after ``cancel()`` on the way to the background: a SQLite write still holding its lock
    /// when iOS suspends the process is a `0xdead10cc` kill, not a slow next launch.
    public func waitUntilFinished() async {
        await task.value
    }
```

- [x] **Step 4: Run the test to verify it passes**

```bash
./Scripts/test.sh FlipcashTests/Regression_ffe0f684
```

Expected: PASS, both tests. If `drain_waitsForInFlightAction` passes but you changed its assertions to get there, revert and fix the implementation instead.

- [x] **Step 5: Commit**

```bash
git add FlipcashCore/Sources/FlipcashCore/Utilities/Poller.swift FlipcashTests/Regressions/Regression_ffe0f684.swift
git commit -m "fix(core): let Poller be cancelled and drained"
```

---

### Task 2: Cancel on background, re-arm on foreground

**Files:**
- Modify: `Flipcash/Core/Session/Session.swift:247`, `:491-514`

No unit test — see Caveats. Verified in Task 4.

- [x] **Step 1: Make `poller` nullable**

`Session.swift:247`, replace:

```swift
    @ObservationIgnored private var poller: Poller!
```

with:

```swift
    @ObservationIgnored private var poller: Poller?
```

- [x] **Step 2: Cancel in `didEnterBackground()` and add the drain**

Replace the whole of `didEnterBackground()` (`Session.swift:501-514`) with:

```swift
    func didEnterBackground() {
        // If the sendOperation is ignoring stream, it's likely
        // presenting a share sheet or in some way mid-process
        // so we don't want to dismiss the bill from under it
        if let sendOperation, !sendOperation.ignoresStream {
            dismissCashBill(style: .slide)
        }

        // Stop the poller before anything else gets a chance to start another tick. Every tick
        // writes the App Group store, and a write still in flight when iOS suspends us is a
        // `0xdead10cc` kill. This only stops new ticks; `drainPoller()` waits for the current one.
        poller?.cancel()

        // Drop the live rate/reserve stream — nothing consumes it in the
        // background and iOS suspends the socket anyway. `didBecomeActive`
        // re-establishes it on return, keeping the lifecycle symmetric and
        // avoiding reconnect churn during the grace window.
        ratesController.stopStreaming()
    }

    /// Waits for a poller tick that was already running when ``didEnterBackground()`` cancelled it.
    ///
    /// Call inside a background-task assertion, before closing the store: cancellation cannot
    /// interrupt the tick, because the limits fetch ignores it and no suspension point separates
    /// that fetch's return from the synchronous write that follows.
    func drainPoller() async {
        await poller?.waitUntilFinished()
        poller = nil
    }
```

- [x] **Step 3: Re-arm in `didBecomeActive()`**

Replace `didBecomeActive()` (`Session.swift:491-499`) with:

```swift
    func didBecomeActive() {
        // Re-arm the poller `didEnterBackground` stopped. Guarded because scenePhase → active
        // fires repeatedly — including once at launch, after `init` has already registered it.
        if poller == nil {
            registerPoller()
        }

        ratesController.ensureStreamConnected()
        // Anything that landed while backgrounded — a tip received, a deposit
        // that settled — is only in the local DB once history is pulled, and
        // the balance poller does not pull it. Nothing else re-syncs on
        // foreground, so the activity feed would stay stale until the next
        // transaction of the user's own.
        historyController.sync()
    }
```

- [x] **Step 4: Build**

```bash
./Scripts/build.sh
```

Expected: BUILD SUCCEEDED. If `registerPoller()` is declared below `didBecomeActive()` in the file, that is fine — Swift does not require forward declaration.

- [x] **Step 5: Commit**

```bash
git add Flipcash/Core/Session/Session.swift
git commit -m "fix(session): stop the poller while backgrounded"
```

---

### Task 3: Drain and checkpoint under one assertion

**Files:**
- Modify: `Flipcash/Core/AppDelegate.swift:125-132`, `:151-181`

- [x] **Step 1: Add the assertion helpers**

Add as properties/methods on `AppDelegate`, immediately above the existing `closeDatabase()` (`AppDelegate.swift:161`):

```swift
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    private func endBackgroundTask() {
        guard backgroundTaskID != .invalid else {
            return
        }

        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }
```

- [x] **Step 2: Replace `closeDatabase()` with `shutDownForBackground()`**

Delete `closeDatabase()` entirely (`AppDelegate.swift:151-181`, doc comment included) and put this in its place:

```swift
    /// Drains in-flight session work and closes the store on the way to the background.
    ///
    /// `.active` has no counterpart on purpose: the connections reopen on the first
    /// read after the app comes back, so a return that never happens costs nothing and
    /// a close that lands at an awkward moment repairs itself.
    ///
    /// The assertion covers the drain as well as the checkpoint, and the drain is the part that
    /// matters for correctness. `didEnterBackground` has already cancelled the poller, but a tick
    /// that was mid-flight keeps its SQLite write lock until it returns — and being suspended while
    /// holding a lock on the App Group store is a `0xdead10cc` kill, not a slow next launch.
    ///
    /// Draining before the checkpoint is also what makes the checkpoint stick: `Database.writer`
    /// reopens the store on next access, so a tick landing after the close simply re-dirties the WAL.
    private func shutDownForBackground() {
        guard let sessionContainer else {
            return
        }

        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "database.close") { [weak self] in
            self?.endBackgroundTask()
        }

        Task { @MainActor [weak self] in
            defer { self?.endBackgroundTask() }

            await sessionContainer.session.drainPoller()

            do {
                try sessionContainer.database.close()
            } catch {
                logger.error("Failed to close the database", metadata: ["error": "\(error)"])
            }
        }
    }
```

If the compiler rejects the expiration handler's isolation (it is a non-isolated `@Sendable` closure, while `AppDelegate` is `MainActor` by the target's `SWIFT_DEFAULT_ACTOR_ISOLATION`), wrap its body:

```swift
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "database.close") { [weak self] in
            MainActor.assumeIsolated { self?.endBackgroundTask() }
        }
```

`beginBackgroundTask` calls the handler on the main thread, so the assumption holds.

- [x] **Step 3: Update the call site**

`AppDelegate.swift:132`, in `scenePhaseChanged(_:)`, replace `closeDatabase()` with:

```swift
            shutDownForBackground()
```

Leave the three lines above it in place and in order — `didEnterBackground()` must run first, because it is what cancels the poller that `shutDownForBackground()` then drains.

- [x] **Step 4: Build**

```bash
./Scripts/build.sh
```

Expected: BUILD SUCCEEDED, and no remaining references to `closeDatabase`. Confirm:

```bash
grep -rn "closeDatabase" --include=*.swift .
```

Expected: no output.

- [x] **Step 5: Commit**

```bash
git add Flipcash/Core/AppDelegate.swift
git commit -m "fix(app): drain in-flight session work before closing the store"
```

---

### Task 4: Verify on simulator — DONE

**The method in the original plan did not work.** It said to watch for `Limits updated`
(Session.swift:604) stopping after backgrounding. That marker is unusable: all three poller
legs are throttled or silent (`fetchLimitsIfNeeded` only logs when limits actually go stale),
so a tick produces no log output at all. A 20s foreground capture yielded 2 log lines total.

Two further traps cost time and are worth recording:

- `./Scripts/build.sh` defaults to `generic/platform=iOS`, a **device** build landing in
  `Debug-iphoneos`. To install on a simulator you must pass a simulator destination
  explicitly, or you will install a stale `Debug-iphonesimulator` bundle and see nothing.
- The app binary in the bundle is a ~40KB stub. Real code lives in `Flipcash.debug.dylib`,
  so `strings Flipcash.app/Flipcash` never confirms a build landed. Grep the dylib.

**What actually worked** — temporary instrumentation plus a negative control:

1. Add a local `Logger(label:)` inside the poller closure logging tick begin/end. It must be
   a local logger: the closure is nonisolated, and the file-scope `logger` is MainActor-isolated,
   so referencing it fails to compile. (That nonisolation independently corroborates the
   MainActor hop seen on thread 0 of the crash.)
2. Build for the simulator, install, stream with
   `log stream --level debug --predicate 'subsystem == "com.flipcash.app.ios"'`
   (`--level debug` is required; `logger.info` is below the default stream level).
3. Foreground, count ticks. Press HOME. Count ticks over the next 40s.
4. Repeat with `poller?.cancel()` commented out as a negative control.
5. Remove all instrumentation and confirm `git diff HEAD` is empty for the file.

**Recorded results** (logged-in session, iPhone 17 Pro, iOS 26.5):

| Build | `scenePhase → background` | Ticks in following 40s |
|---|---|---|
| Fixed | 14:23:24.881 | **0** (≈4 due) |
| `cancel()` removed | 14:25:26.946 | **2** — at 14:25:37.220 and 14:25:47.688 |

The negative control reproduces the crash precondition — the poller writing to the App Group
store while backgrounded — and the fix eliminates it.

Separately confirmed on the logged-out-of-foreground path: `beginBackgroundTask(withName:
"database.close")` is taken, the drain and checkpoint run, and the assertion is ended 9ms
later. No hang, no assertion leak, process survives.


## Done when

- `./Scripts/test.sh FlipcashTests/Regression_ffe0f684` passes, and was observed failing at Step 1.2.
- `./Scripts/build.sh` succeeds.
- Task 4's instrumented A/B shows 0 background ticks with the fix and 2 without it (see table).
- Ask the user to run the full `AllTargets` suite before the PR — per `.claude/docs/testing.md`, that run is theirs, not yours.
