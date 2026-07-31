---
name: release
description: Use when the user wants to cut a release, ship a version, prepare for release, or invokes /release
disable-model-invocation: true
argument-hint: [hotfix]
allowed-tools: Bash(git log *), Bash(git checkout *), Bash(git tag *), Bash(git push *), Bash(git cherry-pick *), Bash(git add *), Bash(git commit *), Bash(git describe *), Bash(date *), Bash(xcodebuild *), Bash(gh *), Bash(fastlane *), Read, Edit, Agent, Grep
---

# Release

Three-phase workflow. The release branch and tag push automatically so TestFlight can build a dogfooding candidate; the tag-built build is submitted to App Review and the public GitHub release drafted only after the user confirms on-device testing.

**Versioning is CalVer — `YYYY.M.N`, matching Android** (`2026.7.6`, not `2026.07.6`):
- `YYYY.M` = release **year** and **month**, month **un-padded** (Apple normalizes `07`→`7` anyway, and Android strips it — so they match exactly).
- `N` = the release **cycle within the month**: the first release of a month is `.1`, each subsequent release (feature *or* hotfix) takes the next number. It is **not** a build counter.
- The number is **derived from the calendar + existing tags**, never chosen by a bump argument. There is no major/minor/patch.
- Tag prefix stays `flipcash-` (`flipcash-2026.7.6`); Android's is `fcash/…` — prefixes differ, numbers match.

`$ARGUMENTS`: pass `hotfix` to patch an already-shipped version on its release branch; otherwise this is a normal release off `main`.

## Pre-flight context

- Working tree: !`git status --porcelain`
- Latest tag: !`git describe --tags --match 'flipcash-*' --abbrev=0 HEAD 2>/dev/null || echo "no tags found"`
- Today: !`date +%Y-%m-%d`

## Phase 1: Prepare & Verify

### 1. Clean working tree
If the pre-flight working tree output is non-empty → STOP. Commit or stash first.

### 2. Calculate next version
CalVer is calendar-anchored. Compute the year and month, then scan existing tags for the current month to pick the cycle number — this resets `N` to 1 each month automatically and is transition-safe (a leftover semver tag like `flipcash-1.17.0` simply won't match the current-month glob):

```bash
Y=$(date +%Y)
M=$(date +%m | sed 's/^0//')          # un-padded month, matches Android
# highest existing cycle for this year+month, else 0
N=$(git tag --list "flipcash-$Y.$M.*" \
      | sed "s/^flipcash-$Y\.$M\.//" \
      | sort -n | tail -1)
N=$(( ${N:-0} + 1 ))
NEXT="$Y.$M.$N"
```

- **Normal release:** that `NEXT` is the version.
- **Hotfix (`$ARGUMENTS` = `hotfix`):** same computation (next free cycle this month), but you'll cut it from the release branch of the version being patched, not `main` — see step 4.

Confirm with user: "Cutting flipcash-{NEXT} (CalVer) — correct?" If they expect a different month/cycle (e.g. the release actually lands next month), let them override `NEXT` explicitly.

> **First CalVer release note:** during the semver→CalVer transition the latest tag is still `flipcash-1.17.0`. The current-month glob finds no CalVer tags, so `N`=1 and `NEXT` = `{thisYear}.{thisMonth}.1` — exactly right. `main`'s `MARKETING_VERSION` must already hold that value (set by the Phase-0 bump PR); verify in step 3. The App Store jump `1.17.0 → {YYYY}.{M}.1` is a valid one-way forward bump (year ≫ 1).

### 3. Verify MARKETING_VERSION on main (normal release only)
Skip for hotfix — the hotfix bumps the version on the release branch in step 4b.

The bump must already be merged into `origin/main` before cutting the release. A complete bump flips every app-family line to `{NEXT}`:
```bash
git fetch origin main
git show origin/main:Code.xcodeproj/project.pbxproj | grep -c "MARKETING_VERSION = {NEXT};"
# sanity: no stale app-family version should remain (the `= 1.0;` lines are unrelated non-app targets)
git show origin/main:Code.xcodeproj/project.pbxproj | grep -o "MARKETING_VERSION = [^;]*;" | sort | uniq -c
```

- **`{NEXT}` count is non-zero and the only app-family value present**: the bump flipped every line — proceed. (The absolute number — 12 today — grows whenever app targets are added; the `MARKETING_VERSION = 1.0;` lines are unrelated non-app targets and stay put.)
- **A stale app-family value is still present**: STOP — the bump PR missed some targets. Have the user re-apply the `replace_all` on `chore/bump-version-{NEXT}`, merge, then re-run.
- **`{NEXT}` count is `0`**: STOP. Check whether a `chore/bump-version-{NEXT}` PR is already open (the previous /release run should have auto-prepped one in step 9a, or the Phase-0 migration PR for the first CalVer cut). If yes, tell the user: *"Merge `chore/bump-version-{NEXT}` and re-run /release."* If no PR exists, tell the user to open one — flip the app-family `MARKETING_VERSION` to `{NEXT}` with `replace_all` — merge it, then re-run. Do not commit the bump locally to main from inside this skill.

### 4. Determine base
- **normal release**: base is `origin/main`. Show the pre-flight latest tag to user. If it picks up a legacy/unexpected tag, ask for the correct base.
- **hotfix**: base is the `release/flipcash-{version-being-patched}` branch. Ask the user which shipped version they're patching, then checkout that branch:
  ```bash
  git checkout release/flipcash-{version-being-patched}
  ```

### 4a. Cherry-pick commits (hotfix only)
Show commits on `main` that aren't on the release branch yet:
```bash
git log release/flipcash-{version-being-patched}..main --oneline --no-merges
```
Ask the user which SHAs to pick (oldest first). Then:
```bash
git cherry-pick <sha> <sha> ...
```
If a cherry-pick conflicts, STOP and hand off to the user — do not resolve conflicts autonomously.

Skip this step if the user says there are no commits to pick (rare — usually means the branch already has them applied manually).

### 4b. Bump MARKETING_VERSION (hotfix only)
The release branch's `Code.xcodeproj/project.pbxproj` is still pinned at the version being patched. The binary produced from this branch needs the new cycle number or TestFlight/App Store will reject it as a duplicate. Use the Edit tool with `replace_all: true`:

- **old_string**: `MARKETING_VERSION = {version-being-patched};`
- **new_string**: `MARKETING_VERSION = {NEXT};`

The Flipcash app and its extension targets share one `MARKETING_VERSION` (extension versions must match the host app), while unrelated targets are pinned at other values (`1.0`) — so `replace_all` hits exactly the app-family lines.

Then commit:
```bash
git add Code.xcodeproj/project.pbxproj
git commit -m "chore: bump version to {NEXT}"
```

### 5. What's shipping
```bash
git log {base-tag}..HEAD --format="- %s" --no-merges
```
`{base-tag}` is the latest CalVer tag on the line you're cutting from: for a normal release the previous release tag; for a hotfix, `flipcash-{version-being-patched}`.

Display for sanity check.

### 6. Run all tests
```bash
xcodebuild test -scheme Flipcash \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -testPlan AllTargets
```
The `AllTargets` test plan already includes UI tests. Do NOT run UI tests separately.

Any failure → STOP.

### 7. Generate changelog
Use the Agent tool with `model: "haiku"`. Pass the commit list with this prompt:

> Given these git commits (conventional commit format), write user-facing release notes.
> - Group under: ## New, ## Improved, ## Fixed (omit empty sections)
> - Write for end users — no jargon, file names, or internals
> - One short sentence per item
> - If no user-facing changes, output: Bug fixes and performance improvements.
> - Output ONLY markdown

Show to user for approval.

### 8. Branch
For **normal release**: step 3 already verified the bump is on `origin/main`. Pull main locally, then branch:
```bash
git checkout main && git pull --ff-only
git checkout -b release/flipcash-{NEXT}
```

For **hotfix**: already on `release/flipcash-{version-being-patched}` from step 4; the version bump commit from step 4b is already on the branch. Skip branch creation.

### 8a. Write TestFlight "What to Test" notes
Xcode Cloud attaches `TestFlight/WhatToTest.en-US.txt` (repo root) — read from the **commit it builds** — as the build's "What to Test" for testers, so the notes must be in the tagged commit. Overwrite that file with **two sections**:

1. **New in this release** — the step-7 changelog as plain-text bullets (drop the `##` headers). That's everything new or updated since the last tag, phrased as flows to verify end to end.
2. **Baseline** — the standing core-flow checklist already in the committed file (the **same list** shown in the Dogfooding Gate below, so testers run exactly what you do). Carry it over unchanged; keep the two lists in sync if you edit either.

Then commit on the release branch:
```bash
git add TestFlight/WhatToTest.en-US.txt
git commit -m "chore: TestFlight notes for {NEXT}"
```
This release-branch commit never merges to main (like the hotfix bump).

### 8b. Tag
```bash
git tag flipcash-{NEXT}
```

## Phase 2: Push for TestFlight

### 9. Push branch and tag
```bash
git push -u origin release/flipcash-{NEXT}
git push origin flipcash-{NEXT}
```
The tag push kicks off the TestFlight build.

### 9a. Prep the next-cycle bump PR (normal release only)
Skip for hotfix — hotfixes don't change `main`'s `MARKETING_VERSION`.

CalVer's "next" is date-dependent, so prep the presumptive **next same-month cycle**: `{next-cycle}` = same `YYYY.M` as the version just shipped, cycle `N+1` (shipping `2026.7.6` → prep `2026.7.7`). If the next release actually lands in a new month, the monthly rollover (the `prep-dev` cron, if adopted — see the migration plan) or a manual bump resets it to `{newYear}.{newMonth}.1`; either way step 3 of the next /release re-verifies before cutting. This mirrors Android's `bump-patch.yml` (increment cycle after a prod release) + monthly cron (reset on the 1st).

Check first — if a `chore/bump-version-{next-cycle}` PR or branch already exists, skip silently.

Otherwise, from `main`:
```bash
git checkout main && git pull --ff-only
git checkout -b chore/bump-version-{next-cycle}
```
Edit `Code.xcodeproj/project.pbxproj` with `replace_all: true`: `MARKETING_VERSION = {NEXT};` → `MARKETING_VERSION = {next-cycle};` (the app and its extensions share the version and flip together — afterwards no app-family `MARKETING_VERSION = {NEXT};` lines should remain).
```bash
git add Code.xcodeproj/project.pbxproj
git commit -m "chore: bump version to {next-cycle}"
git push -u origin chore/bump-version-{next-cycle}
gh pr create --base main --title "chore: bump version to {next-cycle}" --body "<one-line body>"
```

The PR sits open for the user to merge whenever — it's a precondition the next /release will need.

## STOP — Dogfooding Gate

**Do NOT submit to App Review or draft the GitHub release until the user explicitly confirms on-device testing.** Confirming triggers the App Store submission — the next step is irreversible from here (it goes to Apple), so wait for an explicit go-ahead.

```
Branch and tag pushed — TestFlight build should be on its way.
Testers get this same checklist as the build's TestFlight "What to Test" notes (step 8a).
Not yet submitted to App Review; public GitHub release not yet drafted.

Please verify on the TestFlight build:
□ Claim a Cash Link on an empty account, then buy a currency with the received balance
□ Add money to your balance (Phantom or Coinbase)
□ Scan & Send between 2 devices
□ Expand a chat notification — the rich transcript renders + Reply works

Tell me when you're ready to submit to App Review.
```

## Phase 3: Ship

After user confirms:

### 10. Submit to App Review
The gate has cleared the tag-built TestFlight build; submit that same build for `{NEXT}`:

```bash
fastlane release version:{NEXT}
```

`fastlane release` (in `fastlane/Fastfile`) attaches the latest processed build for `{NEXT}` to the App Store version and submits it with phased release. It reads the ASC creds from `fastlane/.env` — if it reports a missing `ASC_*` / `APP_IDENTIFIER`, have the user restore that file (`Scripts/pull_secrets`) and re-run.

Use the step-7 changelog as the "What's New" notes — App Store notes are plain text, so drop the `##` section headers and pass the lines: `fastlane release version:{NEXT} notes:"{plain-text changelog}"`. If a build for `{NEXT}` isn't processed yet (deliver can't find it), wait and re-run — don't fall back to a different version.

**Pass `build:{number}` explicitly** (the tag-built, dogfooded build) — `deliver` otherwise takes the latest build for the version, and a stray deploy build can share the version string. Confirm the number with `fastlane distribute group:'…' dry_run:true` (reports the latest processed build).

**If `deliver` fails at submit** with *"missing … 'whatsNew'"* or a version "not in valid state", the safe fallback is to paste the "What's New" and submit the build from the App Store Connect UI (deliver only *submits* here — the binary is already uploaded, so nothing is lost). The lane sets `whatsNew` via a `set_whats_new` helper before submitting, but that path was unvalidated as of 1.17.0 (which was submitted manually).

### 11. GitHub Release (draft)
Always create the release as a draft. Publish it manually from the GitHub UI once the App Store rollout is live — publishing fires webhooks and "Latest release" badges, so it should reflect what's actually available to users.

```bash
gh release create flipcash-{NEXT} --draft --title "Flipcash {NEXT}" --notes "{changelog}"
```

Remind the user at the end: *"Submitted to App Review and release drafted. Publish the GitHub release once the App Store rollout is live."*

## Never
- Merge the release branch into main
- Commit changelog files to main — the release-branch `TestFlight/WhatToTest.en-US.txt` (step 8a) is the sole exception: it's the Xcode Cloud TestFlight-notes mechanism, committed on the release branch only and never merged to main
- Skip the dogfooding gate
- Submit to App Review (`fastlane release`) or draft the GitHub release before the user confirms on-device testing
- Submit a different version than the one that was tagged and dogfooded — if the build isn't processed yet, wait, don't switch versions
- Zero-pad the month (`2026.07.x`) — Android un-pads and Apple normalizes it away; padding breaks number parity
- Tag a hotfix without bumping `MARKETING_VERSION` on the release branch (step 4b) — TestFlight rejects duplicate build versions
- Open the bump PR for the *current* release's version inside step 3 — step 3 must find it already on `main`, merged by the user from a prior /release's step-9a PR (or the Phase-0 migration PR); auto-prepping the *next* cycle's bump PR in step 9a is the norm
- Cut the release branch or tag from a local-only bump commit — always branch from the `main` whose `origin/main` already has the merged bump
- Resolve cherry-pick conflicts autonomously — stop and hand off to the user
