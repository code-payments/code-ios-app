# CalVer versioning migration (Android parity) + concurrent-release model

**Date:** 2026-07-30
**Status:** Phase 1 (tooling) done in this change; Phase 0 (bump) and Phase 2 (cron) pending.

## Problem

1. Run `1.17.0` (in App Review / hotfix window) alongside starting the next feature release, without the two colliding.
2. Migrate iOS versioning to Android's calendar scheme so the two platforms carry the same version format.

## Findings (as of this date)

### iOS (this repo)
- Version is **manual** in `Code.xcodeproj/project.pbxproj` — `MARKETING_VERSION` appears 12× on the app-family targets (Flipcash + NotificationService + NotificationContent + UITests × build configs); 8 unrelated `= 1.0;` lines are non-app targets. Bumped via `replace_all`.
- `CURRENT_PROJECT_VERSION` (build number) = `272`, committed static, **untouched by version bumps**.
- Tags: `flipcash-X.Y.Z`. Release branches: `release/flipcash-X.Y.Z`, never merged to main.
- CI: Xcode Cloud ("Deploy Flipcash" workflow) builds on tag push. Fastlane `release` lane only *submits* via `deliver`; it does not build or bump. No `match`, no auto-increment.
- Release process codified in `.claude/skills/release/SKILL.md`.
- Current state: `main` = `1.17.0`; `flipcash-1.17.0` tag + `release/flipcash-1.17.0` cut; `chore/bump-version-1.18.0` PR **open, unmerged**.

### Android (`code-android-app`)
- `buildSrc/src/main/java/Packaging.kt` — `object Flipcash : Packaging(majorVersion=2026, minorVersion=7, patchVersion=6)` → versionName `"$major.$minor.$patch"` = **`2026.7.6`**.
- **Month is NOT zero-padded** (`minorVersion` is a plain `Int`; rollover uses `date +%m | sed 's/^0//'`).
- `patchVersion` (`#`) = **release cycle within the month**: reset to `1` on the 1st (cron `prep-dev.yml`), `+1` per production release (`bump-patch.yml` → `update-release-manifest.sh`). Not a build counter.
- `versionCode` = `git rev-list --count HEAD` (monotonic commit count) — store-side integer, independent of versionName.
- Tags: `fcash/2026.7.6`. Base branch `code/cash`.

### Parity conclusion
`2026.7.6` (un-padded) maps **1:1** to Apple's `CFBundleShortVersionString`, which also cannot carry a leading zero (`07`→`7`). Had Android padded, exact parity would be impossible. So `MARKETING_VERSION = 2026.7.6` matches Android exactly.

## Decisions

1. **Format parity, independent cycle counters.** Same `YYYY.M.N` scheme on both; each platform runs its own `N`. Not forcing identical numbers per release — that would imply a coupled release train the teams don't run (cycle counts already diverged; Android is at `.6`).
2. **Cut over now.** Do **not** ship a `1.18.0`. The next feature release is the first CalVer release. `1.17.x` hotfixes stay semver on `release/flipcash-1.17.0`.
3. **Build number stays independent** (`CURRENT_PROJECT_VERSION`). Different store, different mechanism; no unification with Android's commit-count `versionCode`.

## Concurrent-release model (unchanged by CalVer)

- **main** = the next dev version's `MARKETING_VERSION`; all feature work lands here.
- **`release/flipcash-<v>`** = a cut release; hotfixes cherry-pick onto it and re-tag; never merged back.
- 1.17.x lives entirely on `release/flipcash-1.17.0`; the next CalVer release lives on main → its own release branch. They never collide.

## Plan

### Phase 0 — cut over (unblocks next-release work) — PENDING (user-driven, App-Store-facing)
- Replace the open `chore/bump-version-1.18.0` PR with `chore/bump-version-<YYYY.M.1>`.
- `replace_all` the 12 app-family lines `MARKETING_VERSION = 1.17.0;` → `MARKETING_VERSION = <YYYY.M.1>;`.
- **Month choice:** it's 2026-07-30 — if the next release realistically lands in August, use `2026.8.1`; if a July cut is still imminent, `2026.7.7` (one cycle behind Android's current `.6`). This defines the first App Store CalVer version, so the human picks it.
- Merge it → main stamps CalVer; close the old 1.18.0 bump PR.
- The jump `1.17.0 → 2026.M.1` is a valid one-way forward App Store bump.

### Phase 1 — rework `/release` — DONE (this change)
`.claude/skills/release/SKILL.md`:
- `argument-hint` `[major|minor|patch]` → `[hotfix]`.
- Step 2: version derived from calendar + current-month tag scan (`git tag --list "flipcash-$Y.$M.*"`, cycle = max+1 else 1). Transition-safe: a semver tag won't match the CalVer glob, so the first CalVer cut is `.1`.
- Step 3 gate compares against the computed CalVer string.
- Step 4/4a/4b + 5/8: `major/minor/patch` → `normal release` vs `hotfix`; hotfix = next cycle off the version's release branch (no 4th component — matches Android).
- Step 9a: auto-prep bumps main to next **same-month cycle** `N+1`.
- `Never`: added "don't zero-pad the month"; reworded semver-specific lines.

### Phase 2 — optional automation to match Android — PENDING
Port Android's `prep-dev.yml`: a GitHub Action on `cron: '0 0 1 * *'` that `replace_all`s `MARKETING_VERSION` in `project.pbxproj` to `<year>.<month>.1` and opens a PR against main. Keeps main's version honest between releases so dogfood/deploy builds are labelled with the right month (Android's `Packaging.kt` rollover equivalent). Without it, `/release` step 9a keeps the same-month cycle current and a manual bump handles month rollover.

## Loose end to verify (orthogonal to CalVer)
`CURRENT_PROJECT_VERSION` is committed static at `272` and untouched by bumps, yet builds ship — so Xcode Cloud must be overriding `CFBundleVersion` at archive time. Confirm it actually increments per build; if not, TestFlight will reject duplicate build numbers. Independent of this migration.
