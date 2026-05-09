# Package Restructure — Migration Plan

**Started:** 2026-05-07
**Last updated:** 2026-05-07
**Status:** Step 1 shipped via PR #255. Steps 2–4 pending.

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
- [ ] **Step 2 — `FlipcashUI` → `defaultIsolation(MainActor.self)`** + strip 5 manual `@MainActor`. **Risk: low.** Estimated size: small PR, ~10 lines + 5 annotation strips.
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

## Step 2 — How to execute (next up)

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

If smoke surfaces a crash, treat it as a **find** (a bug previously masked by manual annotations), not a regression. Add a regression test under `FlipcashTests/Regressions/Regression_<id>.swift` per CLAUDE.md before fixing. Do not silence with `@unchecked Sendable`, `nonisolated(unsafe)`, or `@preconcurrency` without a `// SAFETY:` comment + `// FOLLOW-UP:` removal trigger.

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
