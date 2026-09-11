# 2026-09-09 - TCC Evidence Read From the Wrong Simulator

## What happened

`AccessKeyBackupSmokeTests.testAccessKeyBackup_saveToPhotos` failed in the full `AllTargets` plan run (`Expected "Allow" Button to be hittable within 30.0s`) but passed alone. The base "iPhone 17" simulator's `TCC.db` still held `kTCCServicePhotosAdd = 2` from the earlier isolated run, unchanged by the plan run, which read as "the reset in `setUp` did not clear the add-only Photos row". Two hypotheses followed: `resetAuthorizationStatus(for: .photos)` skips `kTCCServicePhotosAdd`, or the reset is ignored while the previous test's app instance is still alive.

## The misstep

The row was unchanged because the plan run never touched that device. `AllTargets.xctestplan` marks `FlipcashTests` parallelizable, so `xcodebuild test -testPlan AllTargets` boots `Clone 1 of iPhone 17` and runs every target there, UI tests included (`CoreSimulator.log`: "Boot requested: Clone 1 of iPhone 17"). The clone is deleted after the run, taking its `TCC.db` and `tccd` log with it. Both hypotheses were built on evidence from a simulator the failing test never ran on.

Measured on the base device with a `tccd` log stream and a `TCC.db` poller, the reset deleted the `kTCCServicePhotosAdd` row and the alert appeared in every configuration tried: the test alone, the whole class with the app pre-launched, and the test right after a fresh install where `tccd` logs `bundleRecordWithBundleIdentifier failed ... -10814` and still publishes the delete. The one measurable difference was time-to-alert: about 6s on the base device versus 12.5s on a clone running next to a single parallel unit-test target.

## Resolution

Harness-only change: `BaseUITestCase.setUp` terminates the app before resetting permissions, and `allowSystemAlertIfNeeded(orUntil:)` waits up to 60s for either the springboard "Allow" button or the app moving on without one, tapping Allow only when it shows. The exact failing run was not reproduced; the fix covers the slow-alert path that was measured and the stale-grant path that was hypothesized.

## Lesson

Before reading simulator state as evidence, confirm which simulator the test ran on. With parallel testing on, look for "Clone N of <device>" in `~/Library/Logs/CoreSimulator/CoreSimulator.log` and the xcodebuild log; if the run used a clone, the base device's `TCC.db`, containers, and logs say nothing about it. Capture from inside the run instead: `xcrun simctl spawn <udid> log stream --predicate 'process == "tccd"'` on the base device for `-parallel-testing-enabled NO` runs, and `xcresulttool get test-results activities` for tap timings on any run.
