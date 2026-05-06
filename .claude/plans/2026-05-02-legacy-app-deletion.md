# Legacy App Deletion Plan

**Date:** 2026-05-02
**Goal:** Delete the inactive Code Wallet and Flipchat apps from the repo and project, plus audit pools-related code, so the codebase is one product (Flipcash) and search/indexer/Xcode load times stop paying for dead code.
**Blocks:** [`2026-05-02-package-restructure.md`](2026-05-02-package-restructure.md). Package restructure cannot start until this is merged — half the dependency graph reasoning depends on a single-app repo.
**Branch:** `chore/delete-legacy-apps`

---

## Why now

- Legacy code pollutes every grep/index/AI search even though it hasn't shipped in years. The "Do not modify Code/ / Flipchat/" rule in CLAUDE.md only protects me from editing it; it doesn't make the code invisible.
- Xcode project load and indexing are paying for targets we never build.
- Without a clean baseline, the upcoming package restructure has to reason about which pieces of `CodeServices`/`CodeAPI` are still referenced by anything live — much easier when the legacy callers are gone.

---

## Scope

### Top-level directories to delete

**Legacy Code Wallet (7 dirs):**
- `Code/` — app target
- `CodeAPI/` — proto package
- `CodeGrind/` — internal tool
- `CodePushExtension/` — push extension target
- `CodeServices/` — Solana services package (Flipcash never imports this per CLAUDE.md hard rule — confirmed zero matches for `import CodeServices` across `Flipcash/`, `FlipcashCore/`, `FlipcashUI/`)
- `CodeTests/` — XCTest target
- `CodeUI/` + `CodeUITests/` — UI package + UI test target

**Legacy Flipchat (6 dirs):**
- `Flipchat/`
- `FlipchatAPI/`, `FlipchatPaymentsAPI/`, `FlipchatServices/`
- `FlipchatTests/`, `FlipchatUITests/`

### Keep (do not touch)

- `CodeCurves/` — Ed25519 crypto, used by Flipcash via `FlipcashCore`
- `CodeScanner/` — C++/OpenCV circular-code scanner, used by Flipcash (`CodeExtractor.swift`, `CashCode.Payload+Encoding.swift`) per CLAUDE.md

### Project file (`Code.xcodeproj`)

**Schemes to remove:**
- `Code Dev`, `Code`, `CodeLokalise`, `CodeTests`
- `FC Legacy`
- `Flipchat`, `FlipchatPaymentsGen`, `FlipchatServiceGen`

**Targets to remove:** every target backing the schemes above. Keep `Flipcash`, `FlipcashGen`, `FlipcashTests`, `FlipcashUITests`, and any package targets that survive.

The project file should also be renamed from `Code.xcodeproj` to `Flipcash.xcodeproj` once the legacy targets are gone — but that's a separate follow-up commit (rename touches every CI script and IDE bookmark).

### Pools audit (separate)

CLAUDE.md says "PoolController and pools-related code — feature is deprecated." A grep for `PoolController|PoolsController|class.*Pool|enum.*Pool` against `Flipcash/`, `FlipcashCore/`, `FlipcashUI/` returned zero matches in source (only `.build/` checkouts of grpc-swift / swift-nio, which are unrelated thread-pool code).

**Action:** treat this as already-deleted. Update CLAUDE.md to remove the pools mention from the "Legacy Code" section.

---

## Pre-flight checks

Before any deletion, run from the repo root:

1. `grep -rEln "import (Code|Flipchat)(API|Services|UI|PaymentsAPI|Curves|Scanner)" Flipcash/ FlipcashCore/ FlipcashUI/ FlipcashAPI/ FlipcashCoreAPI/ FlipcashTests/ FlipcashUITests/`
   - Allowed matches: `import CodeCurves`, `import CodeScanner` (kept).
   - Anything else is a real coupling that must be untangled before delete.
2. `grep -rEln "Code\.|Flipchat\." Flipcash/ FlipcashCore/ FlipcashUI/` — catches type-qualified references to module-level types from the legacy targets.
3. `git tag pre-legacy-removal` — preserves a one-checkout escape hatch.
4. Confirm no open PRs touch any of the legacy directories (avoid wasted rebase work).

---

## Sequencing

One PR. The deletion is mechanical and atomic — splitting it into "Code first, then Flipchat" creates a transient broken project file with no real safety benefit.

**Steps:**
1. Run pre-flight checks. Resolve any unexpected import.
2. `git tag pre-legacy-removal`.
3. Delete the directories listed above.
4. Open `Code.xcodeproj` in Xcode 16.x and remove the listed schemes + targets via the IDE (do not hand-edit `project.pbxproj` for target removal — Xcode regenerates internal IDs).
5. Update workspace `Package.resolved` if any deleted package was a workspace dependency.
6. Update CLAUDE.md:
   - Remove the "Legacy Code" subsection under Hard Rules entirely
   - Remove `Code/` and `Flipchat/` from any quick-reference paths
   - Drop the pools mention
7. Update package architecture description in CLAUDE.md to remove `CodeServices/` from the "Don't import" list (becomes moot — it doesn't exist).
8. Run `./Scripts/build.sh` clean.
9. Run `./Scripts/test.sh` for affected suites — at minimum `FlipcashTests`, `FlipcashCoreTests`. User runs `AllTargets` for final verification per workflow rule.

---

## Acceptance criteria

- `ls Code* Flipchat*` shows only `Code.xcodeproj`, `CodeCurves`, `CodeScanner` at the repo root.
- `Code.xcodeproj` opens with no missing-file warnings.
- `xcodebuild -list -project Code.xcodeproj` shows only the Flipcash schemes (and gen schemes).
- `./Scripts/build.sh` succeeds.
- `./Scripts/test.sh FlipcashTests FlipcashCoreTests` passes (final `AllTargets` run is the user's job).
- CLAUDE.md no longer references any deleted module.
- `git tag pre-legacy-removal` exists.

---

## Risks

- **Hidden coupling.** A legacy module's symbol may be referenced from Flipcash without an obvious `import` (e.g. through a shared package re-export). The pre-flight grep should catch direct imports; the second grep catches type-qualified references. If both come back clean, the build is the final arbiter.
- **`CodeServices` is bigger than expected.** It's a 100+ file package. Pre-flight should confirm zero references — if any exist, they have to be moved into `FlipcashCore` first or the file is genuinely unused and gets deleted alongside.
- **Project file conflicts during review.** `project.pbxproj` is famously merge-hostile. PR should be reviewed and merged quickly to avoid rebases.

---

## Status

| Step | Status |
|---|---|
| Pre-flight import grep | Not started |
| Pre-flight type-qualified grep | Not started |
| `pre-legacy-removal` tag | Not started |
| Directory deletions | Not started |
| Scheme + target removal | Not started |
| CLAUDE.md update | Not started |
| Build clean | Not started |
| Affected tests green | Not started |
| Merged | Not started |
| Unblocks `2026-05-02-package-restructure.md` | — |
