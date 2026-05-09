# Camera Isolation Masked by `@preconcurrency`

**Date:** 2026-05-09

## The Bug

Step 2 of the package restructure (set `defaultIsolation(MainActor.self)` on `FlipcashUI`, strip 8 redundant `@MainActor` annotations) was tagged "Risk: low" in the migration plan. Build clean, 5 baseline concurrency stress suites green, no warnings, plan said it should be a near-no-op. First device dogfood crashed instantly the moment the camera started: `_dispatch_assert_queue_fail` on `com.code.videoDelegate.queue`.

## Root Cause

`CameraSession` had been `@MainActor` for years. AVFoundation invokes the sample-buffer / metadata delegate callbacks on the queues passed to `setSampleBufferDelegate(_:queue:)` / `setMetadataObjectsDelegate(_:queue:)` — never the main queue. Every frame, the receive path (`captureOutput → receiveHandler → receiveSampleBuffer → extractor.extract`) was crossing actor boundaries. `@preconcurrency import AVKit` had been suppressing the resulting Sendable / isolation diagnostics to warnings, so it compiled clean. Under Xcode 26's stricter Swift 6.2 runtime, the MainActor check now traps via `dispatch_assert_queue` — exactly what the `@preconcurrency` shim had been hiding.

The migration plan flipped the package from `// swift-tools-version: 6.1` to `6.2` (required for `.defaultIsolation`). That toolchain bump was what activated the runtime check. The `@MainActor` strip was a no-op semantically — the package default supplies the same isolation. The crash was always latent; toolchain enforcement just exposed it.

## The Fix

Split `CameraSession`'s isolation along the actual data flow:

- Class stays `@MainActor` (via package default) — `configureDevices`, `start`, `stop` are UI lifecycle.
- Receive path is `nonisolated` end-to-end: inner `VideoDelegate` / `MetadataDelegate` classes, `receiveHandler` closures, the `CameraSessionExtractor` protocol (so the extractor's `extract` is callable from the queue), `extraction` / `metadataExtraction` publishers, and `receiveSampleBuffer`.
- Storage that crosses isolation: `nonisolated let` for Combine subjects (under `@preconcurrency import Combine`) and `AVCaptureSession` (under `@preconcurrency import AVKit`). Generic `T` has no Sendable constraint so its `nonisolated(unsafe)` is documented, not relaxed.
- Class is `@unchecked Sendable` (required because `DispatchQueue.main.async`'s closure parameter is `@Sendable` and ends up capturing `self`). All escape hatches got SAFETY + FOLLOW-UP comments matching the project pattern.

## Lessons

1. **"Risk: low" in a migration plan does not survive dogfood.** The plan was right that the strip was semantically a no-op — and wrong that no-op meant safe. The runtime-only escape hatches (`@preconcurrency import`) hide bugs that the next compiler version may surface as crashes. Treat any toolchain bump as a high-risk smoke gate even when nothing visible changes.
2. **Compile-clean + stress-suite green is not a substitute for hardware paths.** The 5 baseline stress suites cover the actor / streamer / router / messaging boundaries — none of them touches AVFoundation. Camera, WebKit message handlers, MapKit delegates, `URLSessionDelegate` callbacks all need their own runtime smoke gates. A future Step 3 task should be exercising every `@preconcurrency import` consumer on real hardware.
3. **`@preconcurrency import <module>` is a *deferred* Sendable error.** When wrapping a callback-based Apple framework, the receive path needs explicit `nonisolated` end-to-end the moment any stricter runtime check ships — even if today's compiler is happy. Search for `@preconcurrency import` + closure-based delegates as a pre-flight check whenever bumping tools-version or default isolation.
4. **The plan's verification gates anticipated this.** The text said "If smoke surfaces a crash, treat it as a find (a bug previously masked by manual annotations), not a regression." Reading the plan's own carry-forward notes before declaring a step complete would have flagged this as a known risk earlier.
