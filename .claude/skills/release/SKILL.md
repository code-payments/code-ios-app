---
name: release
description: Use when the user wants to cut a release, ship a version, prepare for release, or invokes /release
disable-model-invocation: true
argument-hint: [major|minor|patch]
allowed-tools: Bash(git log *), Bash(git checkout *), Bash(git tag *), Bash(git push *), Bash(git cherry-pick *), Bash(git add *), Bash(git commit *), Bash(xcodebuild *), Bash(gh *), Read, Edit, Agent, Grep
---

# Release

Three-phase workflow. The release branch and tag push automatically so TestFlight can build a dogfooding candidate; the public GitHub release is only drafted after the user confirms on-device testing.

## Pre-flight context

- Working tree: !`git status --porcelain`
- Latest tag: !`git describe --tags --match 'flipcash-*' --abbrev=0 HEAD 2>/dev/null || echo "no tags found"`

## Phase 1: Prepare & Verify

### 1. Clean working tree
If the pre-flight working tree output is non-empty → STOP. Commit or stash first.

### 2. Calculate next version
Derive the current released version from the pre-flight latest tag (strip the `flipcash-` prefix). Do not infer the version from `MARKETING_VERSION` — it is the version under development, not the version released.

Determine bump type from `$ARGUMENTS` (default: `minor`):

| Argument | Bump | Example |
|----------|------|---------|
| `major` | X+1.0.0 | 2.3.1 → 3.0.0 |
| `minor` (default) | X.Y+1.0 | 2.3.1 → 2.4.0 |
| `patch` | X.Y.Z+1 | 2.3.1 → 2.3.2 |

Confirm with user: "Bumping {type}: flipcash-{current} → flipcash-{next} — correct?"

### 3. Verify MARKETING_VERSION on main (major / minor only)
Skip for patch — patch bumps the version on the release branch in step 4b.

The bump must already be merged into `origin/main` before cutting the release. Check it:
```bash
git fetch origin main
git show origin/main:Code.xcodeproj/project.pbxproj | grep -c "MARKETING_VERSION = {next-version};"
```

- **Result is `4`** (Flipcash target's four configurations): proceed.
- **Result is `0`**: STOP. Check whether a `chore/bump-version-{next-version}` PR is already open (the previous /release run should have auto-prepped one in step 9a). If yes, tell the user: *"Merge `chore/bump-version-{next-version}` and re-run /release {bump}."* If no PR exists, tell the user to open one — `MARKETING_VERSION = {current-version};` → `MARKETING_VERSION = {next-version};` with `replace_all` — merge it, then re-run. Do not commit the bump locally to main from inside this skill.

### 4. Determine base
- **major / minor**: base is `origin/main`. Show the pre-flight latest tag to user. If it picks up a legacy tag, ask for the correct base.
- **patch**: base is the `release/flipcash-X.Y.Z` branch (the release being patched). Checkout that branch before proceeding:
  ```bash
  git checkout release/flipcash-{current-version}
  ```

### 4a. Cherry-pick commits (patch only)
Show commits on `main` that aren't on the release branch yet:
```bash
git log release/flipcash-{current-version}..main --oneline --no-merges
```
Ask the user which SHAs to pick (oldest first). Then:
```bash
git cherry-pick <sha> <sha> ...
```
If a cherry-pick conflicts, STOP and hand off to the user — do not resolve conflicts autonomously.

Skip this step if the user says there are no commits to pick (rare — usually means the branch already has them applied manually).

### 4b. Bump MARKETING_VERSION (patch only)
The release branch's `Code.xcodeproj/project.pbxproj` is still pinned at `{current-version}`. The binary produced from this branch needs the patched version or TestFlight/App Store will reject it as a duplicate. Use the Edit tool with `replace_all: true`:

- **old_string**: `MARKETING_VERSION = {current-version};`
- **new_string**: `MARKETING_VERSION = {next-version};`

Other targets in the pbxproj use different `MARKETING_VERSION` values (legacy apps, test targets), so `replace_all` is safe — it only hits the Flipcash target.

Then commit:
```bash
git add Code.xcodeproj/project.pbxproj
git commit -m "chore: bump version to {next-version}"
```

### 5. What's shipping
```bash
git log {base-tag}..HEAD --format="- %s" --no-merges
```
For patch releases, `{base-tag}` is `flipcash-{current-version}` (the tag on the branch being patched).

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

### 8. Branch and tag
For **major / minor**: step 3 already verified the bump is on `origin/main`. Pull main locally, then branch:
```bash
git checkout main && git pull --ff-only
git checkout -b release/flipcash-{next-version}
```

For **patch**: already on `release/flipcash-X.Y.Z` from step 4; the version bump commit from step 4b is already on the branch. Skip branch creation.

Then tag:
```bash
git tag flipcash-{next-version}
```

## Phase 2: Push for TestFlight

### 9. Push branch and tag
```bash
git push -u origin release/flipcash-{version}
git push origin flipcash-{version}
```
The tag push kicks off the TestFlight build.

### 9a. Prep the next-minor bump PR (major / minor only)
Skip for patch — patches don't change `main`'s `MARKETING_VERSION`.

Compute `{next-minor}` = the next minor after the version being shipped (e.g. shipping `1.10.0` → `1.11.0`; shipping `2.0.0` → `2.1.0`).

Check first — if a `chore/bump-version-{next-minor}` PR or branch already exists, skip silently.

Otherwise, from `main`:
```bash
git checkout main && git pull --ff-only
git checkout -b chore/bump-version-{next-minor}
```
Edit `Code.xcodeproj/project.pbxproj` with `replace_all: true`: `MARKETING_VERSION = {version};` → `MARKETING_VERSION = {next-minor};` (only the Flipcash target's four lines should change).
```bash
git add Code.xcodeproj/project.pbxproj
git commit -m "chore: bump version to {next-minor}"
git push -u origin chore/bump-version-{next-minor}
gh pr create --base main --title "chore: bump version to {next-minor}" --body "<one-line body>"
```

The PR sits open for the user to merge whenever — it's a precondition the next /release will need.

## STOP — Dogfooding Gate

**Do NOT draft the GitHub release until the user explicitly confirms on-device testing.**

```
Branch and tag pushed — TestFlight build should be on its way.
Public GitHub release not yet drafted.

Please verify on the TestFlight build:
□ Claim a Cash Link on an empty account
□ Buy a currency with Phantom
□ Scan & Send between 2 devices
□ Expand a chat notification — the rich transcript renders + Reply works

Tell me when you're ready to draft the public release.
```

## Phase 3: Ship

After user confirms:

### 10. GitHub Release (draft)
Always create the release as a draft. Publish it manually from the GitHub UI once the App Store rollout is live — publishing fires webhooks and "Latest release" badges, so it should reflect what's actually available to users.

```bash
gh release create flipcash-{version} --draft --title "Flipcash {version}" --notes "{changelog}"
```

Remind the user at the end: *"Release drafted. Promote it in the GitHub UI once the App Store rollout is live."*

## Never
- Merge the release branch into main
- Commit changelog files
- Skip the dogfooding gate
- Draft the GitHub release before the user confirms on-device testing
- Tag a patch without bumping `MARKETING_VERSION` on the release branch (step 4b) — TestFlight rejects duplicate build versions
- Open the bump PR for the *current* release's version inside step 3 — step 3 must find it already on `main`, merged by the user from a prior /release's step-9a PR (or opened manually); auto-prepping the *next* version's bump PR in step 9a is the new normal
- Cut the release branch or tag from a local-only bump commit — always branch from the `main` whose `origin/main` already has the merged bump
- Resolve cherry-pick conflicts autonomously — stop and hand off to the user
