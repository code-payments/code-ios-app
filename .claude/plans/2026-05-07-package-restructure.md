# Package Restructure — Migration Plan

**Started:** 2026-05-07
**Last updated:** 2026-05-09
**Status:** Step 1 shipped via PR #255. Step 2 implementation done locally on `refactor/flipcash-ui-default-isolation`; awaiting user smoke + soak gates before commit/PR. Steps 3–4 pending.

---

## Why

Two pains motivated this work:

1. **Manual `@MainActor` boilerplate.** 41 files in the app target carried explicit `@MainActor` annotations — Session, Controllers, Database, Screens, ViewModels, Navigation. They were added during a rolled-back Swift 6 attempt and never collapsed because the app target lacked a default-isolation setting.
2. **Slow build / preview pipeline.** `#Preview` consistently times out. The app target compiles 162 files for any preview, and `FlipcashCore` is a 201-file god module that mixes Solana wire types, gRPC clients, logging, hashes, and currency models in one compile graph.

Secondary goal: improve testability by separating "domain logic that runs anywhere" from "stateful, observable, UI-driven" code.

---

## Target end state

```
┌─────────────────────────────────────────────────────────────────────┐
│  Flipcash  (.xcodeproj app target)                                  │
│    Swift 6  •  default isolation = MainActor  (build settings)     │
│    AppDelegate, FlipcashApp, Container, Session, Controllers,       │
│    Database, Navigation, Screens, ViewModels, Operations            │
│    → no manual @MainActor anywhere                                  │
└──────────┬──────────────────────────────┬───────────────────────────┘
           │                              │
           ▼                              ▼
┌──────────────────────┐    ┌─────────────────────────────────────────┐
│  FlipcashUI  (SPM)   │    │  FlipcashClient  (SPM, NEW)             │
│  Swift 6             │    │  Swift 6  •  no default isolation       │
│  defaultIsolation    │    │  Stateful clients, Sendable services,   │
│      (MainActor)     │    │  Intents, Actions, VerifiedProtoService │
│  Views, Theme,       │    │  ~59 files moved from Core/Clients/     │
│  Camera, Dialog,     │    │  + FlipcashAPI + FlipcashCoreAPI as     │
│  Haptics, Containers │    │     internal deps                       │
└──────────┬───────────┘    └────────────┬────────────────────────────┘
           │                             │
           └──────────────┬──────────────┘
                          ▼
              ┌────────────────────────────────┐
              │  FlipcashCore  (SPM, slimmed)  │
              │  Swift 6  •  no default        │
              │      isolation                 │
              │  Models, Solana, Hashes,       │
              │  Logging, Formatters,          │
              │  Utilities, Extensions, Vendor │
              │  ~142 files (was 201)          │
              │  No grpc-swift dep anymore     │
              └────────────────────────────────┘
```

### Out of scope

- No feature-package split (Onramp, Onboarding, Settings as own packages).
- No splitting Solana out of Core.
- No converting `Client` / `FlipClient` from `@MainActor` to `actor`.
- No moving Database into a package.

These can be revisited after Step 4.

---

## Status

- [x] **Step 0 — Cleanup** — empty package skeletons (`CodeAPI/`, `FlipchatAPI/`, etc.) deleted from working tree. They were never git-tracked, so no commit was needed; the Xcode 26 pbxproj cleanup that landed alongside Step 1 (commit `adab4ccd`) covered the actual project-file detritus.
- [x] **Step 1 — App target → Swift 6 + `defaultIsolation = MainActor` + strip 41 `@MainActor` annotations** — shipped via PR #255 (39 commits). All 5 concurrency stress baselines green under TSan + Main Thread Checker. Full smoke + soak passed clean.
- [~] **Step 2 — `FlipcashUI` → `defaultIsolation(MainActor.self)`** + strip 8 manual `@MainActor` annotations across 5 files. Implementation complete on `refactor/flipcash-ui-default-isolation`; build clean, 5 baseline stress suites green. Pending user-side smoke (scanner) + soak gates before commit + PR.
- [ ] **Step 3 — Extract `FlipcashClient`** — move ~59 files from `FlipcashCore/Clients/`; FlipcashAPI / FlipcashCoreAPI become its dependencies; FlipcashCore loses the `grpc-swift` dep. **Risk: medium.** Estimated size: medium PR, mostly mechanical file moves.
- [ ] **Step 4 — Re-evaluate** — measure build time delta, preview behavior, outstanding annotations; decide whether further splits (feature packages, Solana extract) are warranted.

---

## Step 1 retrospective (what surfaced)

Useful context for Step 2 and Step 3 — most of these were "previously masked" by the rolled-back attempt's manual `@MainActor` sprinkles.

- **Layered Swift 6 diagnostics.** Flipping `SWIFT_VERSION = 6.0` then `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` surfaced four waves of source-isolation issues. Each fix unblocked the next wave because the compiler halts at the first failing batch. Plan more rounds than estimated; budget for ~12 commits of source fixes per Swift-mode flip.
- **Tests, not production, were the broken side in several places.** `WalletProcessingState` had to keep `nonisolated` until `WalletProcessingStateTests` was annotated `@MainActor`. `GradientStop.init(from: Color)` needed `@MainActor` because it touches `UIColor`, but tests reached it from non-main contexts. The pattern: when the strip exposes "this needs `nonisolated(unsafe)` to compile," check whether the real fix is on the test side first.
- **Test target intentionally NOT default-MainActor.** Applying `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` to test targets broke `BaseUITestCase: XCTestCase`. Test targets stay on the legacy default; tests opt into `@MainActor` explicitly via `@Suite @MainActor` per file as needed.
- **The TestSupport `@MainActor` ripple is small and mechanical.** When stripping production explicit `@MainActor`, test-target extensions of those types lose isolation inheritance and need explicit `@MainActor` added. Expect ~3-5 TestSupport sites per equivalent-sized future strip.
- **`@unchecked Sendable` / `nonisolated(unsafe)` use should always pair with a `// SAFETY:` comment naming an invariant + a `// FOLLOW-UP:` comment naming the upstream change that unblocks removal.** Any escape hatch without both is a code-review reject.
- **The 5 concurrency stress baselines are reusable infrastructure for future steps.** They run under TSan + Main Thread Checker on every PR via the `Tag.concurrency` tag. Tag any new stress tests for Steps 2/3 the same way.

### Files / decisions to carry forward

- The `runCancellationStress` helper in `FlipcashTests/Concurrency/StressTestSupport.swift` — reuse for any new actor stress tests.
- The `// SAFETY:` + `// FOLLOW-UP:` comment pattern around `@preconcurrency import …`, `@unchecked Sendable`, etc.
- The `@retroactive @unchecked Sendable` pattern for upstream classes that aren't yet Sendable (used for `JSONRPCAPIClient`).
- App target build settings now: `SWIFT_VERSION = 6.0`, `SWIFT_UPCOMING_FEATURE_NONISOLATED_NONSENDING_BY_DEFAULT = YES`, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` on 4 app-target configs.

---

## Step 2 retrospective (in progress, 2026-05-09)

Surfaced diagnostics that needed root-cause fixes before stripping the annotations. Useful for Step 3, where a similar package-wide isolation flip is on the menu.

**FlipcashUI changes (the actual point of this step):**
- `FlipcashUI/Package.swift` bumped to `// swift-tools-version: 6.2` (required for `.defaultIsolation`; `enableUpcomingFeature("NonisolatedNonsendingByDefault")` added alongside).
- 8 type/function-level `@MainActor` annotations stripped across the 5 files the original plan listed.

**Surfaced fixes (root-cause, not patches):**
- `FlipcashUI/.../Bill/KikCode.swift`: `nonisolated` on the `KikCode` namespace + 3 nested-type extensions. `Shape.path(in:)` is nonisolated by protocol contract; with default-MainActor on the package, the previously-ambient `KikCode` namespace and its `Payload`/`Description`/`Error` types became MainActor and stopped being callable from `CodeShape`. They are pure math/encoding — `nonisolated` is the accurate description.
- `FlipcashUI/.../Chart/ChartDataPoint.swift`: `nonisolated public struct`. Pure value type already declared `Sendable`; consumed by `MarketCapController.processDataPoints` (a `nonisolated` background processor in the app target) which broke the moment the struct's init went MainActor.
- `Flipcash/Core/Controllers/MarketCapController.swift`: `nonisolated(unsafe) static let targetPointCount = 100` → `nonisolated static let`. `Int` is Sendable, no need for `unsafe`. (Pre-existing oversight from Step 1; surfaced because the rebuild was no longer incremental.)
- `Flipcash/Core/Controllers/RatesController.swift`: file-scope `private let logger` → `private nonisolated let logger`. `Logger` is Sendable; the binding had been inferred MainActor by Step 1's app-target default, and the background `rateWriteQueue.async` closure couldn't access it.
- `Flipcash/Utilities/PhotoLibrary.swift`: `static func write(...)` and `class Writer` marked `nonisolated`; completion closures marked `@Sendable`. The whole point of this code is to do `UIImageWriteToSavedPhotosAlbum` off-main, so MainActor inheritance was actively wrong. Also dropped a redundant `await` on a same-isolation call (now no-op under nonisolated-nonsending semantics).
- `Flipcash/UI/ApplePayWebView.swift`: removed `Coordinator.deinit` and the unused `weak var contentController`. The deinit was redundant with the static `dismantleUIView` already removing the script handler at the SwiftUI-blessed teardown point — no warning to suppress, just dead code.

**Layered-diagnostic pattern repeated.** Similar to Step 1: each fix unblocked the next batch of compiler diagnostics. Budget for at least one additional round when running Step 3.

**Tests, not production, were not the broken side this time.** Step 2 only needed source fixes; no test annotation churn.

**Smoke gate find — `CameraSession` capture path was always wrong, masked by `@preconcurrency import AVKit`.** First device run crashed on launch into the scanner with `_dispatch_assert_queue_fail` on `com.code.videoDelegate.queue`. AVFoundation invokes the sample-buffer / metadata delegate callbacks on the queues passed to `setSampleBufferDelegate(_:queue:)` / `setMetadataObjectsDelegate(_:queue:)` — never the main queue. The class had been `@MainActor` for years, which made the entire receive path (`captureOutput → receiveHandler → receiveSampleBuffer → extractor.extract`) cross actor boundaries every frame. `@preconcurrency import AVKit` downgraded the resulting Sendable / isolation diagnostics to warnings; under Xcode 26's Swift 6.2 runtime the MainActor check now traps via `dispatch_assert_queue`. Fix splits `CameraSession`'s isolation:
- The class itself stays `@MainActor` (via the package default) so SwiftUI lifecycle code can call `configureDevices` / `start` / `stop` directly.
- The receive path is `nonisolated` end-to-end: the inner `VideoDelegate` / `MetadataDelegate` classes, the `receiveHandler` closures, the `CameraSessionExtractor` protocol (so `CodeExtractor.extract` is callable from the queue), the `extraction` / `metadataExtraction` publishers, and `receiveSampleBuffer`. Storage that crosses isolation is `nonisolated(unsafe) let` since AVCaptureSession, PassthroughSubject, and the unconstrained generic `T` aren't `Sendable`.
- Class is `@unchecked Sendable` with class-level SAFETY notes covering the once-during-init invariant for every stored ref. This is required because `DispatchQueue.main.async`'s closure parameter is `@Sendable` and ends up capturing `self`.

This is exactly the "smoke surfaces a previously-masked bug" outcome the verification-gate section of this plan called out. The fix is shipped on the same Step 2 branch rather than split, since it's the same Swift 6.2 isolation correction touching the same files.

Carry-forward for Step 3: any class that wraps a callback-style Apple framework (URLSession, AVFoundation, MapKit) with `@preconcurrency import` is a candidate for the same treatment — the Swift 6.2 runtime will surface what the `@preconcurrency` shim hid. Search for `@preconcurrency import` + closure-based delegates when extracting `FlipcashClient`.

**Style carry-forward (from the simplify pass against the established codebase pattern):**

- **`@preconcurrency import Combine` + `nonisolated let` for PassthroughSubject**, no `(unsafe)` needed. Match `FlipcashCore/Sources/FlipcashCore/Clients/Payments API/Services/VerifiedProtoService.swift:37,40` and the SAFETY block at `Flipcash/Core/Controllers/RatesController.swift:9-14`. `nonisolated(unsafe)` is reserved for storage whose underlying type genuinely has no `@preconcurrency`-coverable origin (e.g., the unconstrained generic `T` in `CameraSession`, set-once `var receiveHandler`s, serial-queue-guarded `lastString`).
- **`nonisolated let session: AVCaptureSession`** works under `@preconcurrency import AVKit` — `(unsafe)` would be redundant.
- **SAFETY / FOLLOW-UP comments are `//` prose, not `///` doc.** Match `Database.swift:16-22` shape: `// SAFETY: …` line, `// FOLLOW-UP: …` line, optionally a one-line `See <other site>` redirect when the same invariant applies twice. The reflection at `.claude/reflections/2026-05-09-camera-isolation-masked-by-preconcurrency.md` records the full incident; CLAUDE.md's pitfall table got a short summary entry.
- **Logger keyword order:** `nonisolated private let logger = Logger(label: "…")` matches the existing sites (`Database.swift:12`, `Database+Balance.swift:12`, `Coinbase.swift:11`). Don't write `private nonisolated let`.

**Carry-forward for Step 3.**
- Same `nonisolated` rule of thumb for "pure data / pure compute" types in modules that flip to default MainActor.
- `swift-tools-version: 6.2` is now a precedent — when extracting `FlipcashClient`, declare `6.2` in its `Package.swift` from the start so `.defaultIsolation` is available if we want it (Step 3 plan currently says "no default isolation" for `FlipcashClient`; reconfirm at Step 3 time).
- `private let foo = ...` at file scope is silently MainActor-isolated under `defaultIsolation = MainActor`. Loggers, formatters, and other Sendable file-scoped constants want explicit `nonisolated`.

---

## Step 2 — How to execute (original plan, kept for reference)

**Goal:** drop the 5 manual `@MainActor` annotations from `FlipcashUI` by setting `defaultIsolation(MainActor.self)` on the package.

**Files:**

- Modify: `FlipcashUI/Package.swift` — add the default-isolation setting.
- Modify: 5 `FlipcashUI` source files that carry manual `@MainActor`. Confirm via `grep -rln '@MainActor' FlipcashUI/Sources/` at start time. As of 2026-05-07 they were:
  - `FlipcashUI/Sources/FlipcashUI/Camera/CameraSession.swift`
  - `FlipcashUI/Sources/FlipcashUI/Camera/CameraAuthorizer.swift`
  - `FlipcashUI/Sources/FlipcashUI/Haptics/Haptics.swift`
  - `FlipcashUI/Sources/FlipcashUI/Modifiers/Separator.swift`
  - `FlipcashUI/Sources/FlipcashUI/Transitions/Animations.swift`

**Sub-steps (each its own commit):**

1. Update `FlipcashUI/Package.swift`:
   - Add `defaultIsolation(MainActor.self)` to the package or each target.
   - Enable `NonisolatedNonsendingByDefault` upcoming feature on the target.
2. Build all consumers (`./Scripts/build.sh`). Fix any new diagnostics — same root-cause-not-patch rule as Step 1.
3. Strip the 5 type-level `@MainActor` annotations. Preserve `Task { @MainActor in ... }` closure isolation specifiers.
4. Run the 5 baseline concurrency suites + a manual smoke of the camera (scanner flow) + dialog presentation.

**Verification gates** — same as Step 1: compile gate, test gate (TSan + MTC), smoke gate, soak gate.

**Rollback:** `git revert` of the `Package.swift` change + the 5 stripped annotations.

**Branch name suggestion:** `refactor/flipcash-ui-default-isolation`

---

## Step 3 — How to execute

**Goal:** Extract a new `FlipcashClient` SwiftPM package containing the gRPC client layer (currently `FlipcashCore/Sources/FlipcashCore/Clients/`). FlipcashAPI and FlipcashCoreAPI become FlipcashClient's dependencies. FlipcashCore loses its `grpc-swift` dep.

**Files to move (~59 files):**

Everything under `FlipcashCore/Sources/FlipcashCore/Clients/`:

- `Flip API/` — FlipClient + service wrappers
- `Payments API/` — Client + Intents + Actions + Services + Utilities

**Sub-steps (each its own commit):**

1. Create `FlipcashClient/Package.swift` with deps: `FlipcashCore`, `FlipcashAPI`, `FlipcashCoreAPI`.
2. Move files in batches by sub-folder (Flip API, Payments API/Services, Payments API/Intents, Payments API/Utilities, Payments API root). Use `git mv` so blame survives. One commit per batch. Build after each.
3. Update `FlipcashCore/Package.swift` — drop `FlipcashAPI` / `FlipcashCoreAPI` deps and the transitive `grpc-swift` dep.
4. Update `Code.xcodeproj/project.pbxproj` — link `FlipcashClient` to the app target.
5. Update imports across the app target and FlipcashUI in a dedicated commit (after all files have moved).
6. Build the full project. Run all baseline concurrency suites + targeted client tests.

**Verification gates** — same four (compile / test / smoke / soak). Smoke covers every gRPC-touching flow because import paths can silently mask wrong dependencies.

**Rollback:** Each batched commit is revertable. Full rollback may need multiple reverts in reverse order.

**Branch name suggestion:** `refactor/extract-flipcash-client`

---

## Step 4 — Re-evaluate

**Goal:** Decision-only step. Capture metrics, decide what's next.

**Inputs to collect:**

- Build time before vs after Steps 2 + 3 (use `xcode-build-benchmark` skill).
- `#Preview` compile time on a screen with no network — does it still time out?
- `@MainActor` annotation count app-wide.
- Outstanding `@unchecked Sendable` / `nonisolated(unsafe)` / `@preconcurrency` annotations (with their FOLLOW-UP triggers).

**Decision points:**

- Continue with feature-package splits (Onramp, Settings, etc.)? Cost vs benefit.
- Extract Solana from Core? 73 self-contained files; same shape as `FlipcashClient`.
- Convert `Client` / `FlipClient` from `@MainActor` to `actor`? Affects every callsite.
- Move Database into its own package? Currently in the app target.

Document the decision in this file under a new `## Step 4 outcome` section, then close the migration.

---

## Verification gates (apply at every step)

1. **Compile gate** — clean build with `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` for the touched module.
2. **Test gate** — relevant test suites pass with **TSan + Main Thread Checker** enabled in the test scheme. Run the 5 baseline concurrency suites explicitly:

   ```
   ./Scripts/test.sh \
     FlipcashTests/AppRouterStressTests \
     FlipcashTests/LiveMintDataStreamerStressTests \
     FlipcashTests/MessagingServiceFanInStressTests \
     FlipcashTests/RatesControllerStressTests \
     FlipcashTests/VerifiedProtoServiceStressTests
   ```

3. **Smoke gate** — manual exercise of high-risk flows (≥ 5 min per flow), same sanitizers on, on a Debug build. For Step 2 the high-risk flow is the **scanner** (camera path is what FlipcashUI's `@MainActor` strip touches). For Step 3 it's every **gRPC-touching flow**: send cash, receive cash, swap, currency creation, onramp, message stream.
4. **Soak gate** — run the build for ≥ 30 min mixing flows; tail logs for warnings, dispatch-assertion crashes, TSan reports. (Replaces a dogfood window — solo developer.)

If smoke surfaces a crash, treat it as a **find** (a bug previously masked by manual annotations), not a regression. Do not silence with `@unchecked Sendable`, `nonisolated(unsafe)`, or `@preconcurrency` without a `// SAFETY:` comment + `// FOLLOW-UP:` removal trigger.

---

## How to continue

This plan lives at `.claude/plans/2026-05-07-package-restructure.md` on `main` once PR #255 merges. There is no automation that resumes the work — a human (or a Claude session a human invokes) picks it up.

**To resume Step 2:**

1. Start a new Claude Code session at the repo root.
2. Say: "Continue the package restructure plan — Step 2 (FlipcashUI default isolation)."
3. The session reads this file and follows the **Step 2 — How to execute** section above. Same verification gates. Same root-cause-not-patch rule on any new Swift 6 diagnostics.

**To resume Step 3:** same pattern, swap "Step 2" for "Step 3."

**To resume Step 4:** "Run the package-restructure migration's Step 4 — re-evaluate." That session collects metrics and writes the outcome back into this file.

**Order:** Steps are sequential. Step 2 must land cleanly before Step 3. Don't pipeline.

**Don't:**

- Skip the verification gates "because Step 1 was clean." Each step's strip can expose its own previously-masked bugs.
- Add `@unchecked` / `nonisolated(unsafe)` / `@preconcurrency` to make a build pass without a SAFETY + FOLLOW-UP comment.
- Move tests to be `@MainActor` to satisfy production isolation. Production isolation should drive the test side, not the other way around.

---

## References

- PR #255 — Step 1 implementation (this PR).
- CLAUDE.md — Hard rules: Swift Testing, Sendable in metadata, no `@unchecked` without a SAFETY comment.
- `swift-concurrency` skill — guardrails on `@MainActor` blanket usage, escape-hatch policy.
- `swift-testing-expert` skill — `confirmation` over `Task.sleep`, tag-based filtering, isolation justification.
- `simplify` skill — review for reuse, quality, efficiency on each step.
