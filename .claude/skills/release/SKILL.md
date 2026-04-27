---
name: release
description: Use when the user wants to cut a release, ship a version, prepare for release, or invokes /release
disable-model-invocation: true
argument-hint: [major|minor|patch]
allowed-tools: Bash(git log *), Bash(git checkout *), Bash(git tag *), Bash(git push *), Bash(git cherry-pick *), Bash(git add *), Bash(git commit *), Bash(xcodebuild *), Bash(gh *), Read, Edit, Agent, Grep
---

# Release

Two-phase workflow with a dogfooding gate. Nothing leaves the machine until the user confirms they've tested on device.

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
- **Result is `0`**: STOP. Tell the user: *"`origin/main` is still at `{current-version}`. Open a `chore/bump-version-{next-version}` PR that flips `MARKETING_VERSION` from `{current-version}` to `{next-version}` (use `replace_all` — only the Flipcash target's four lines should change), merge it, then re-run /release {bump}."* Do not open the bump PR from inside this skill, and do not commit it locally to main.

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

## STOP — Dogfooding Gate

**Do NOT proceed until the user explicitly confirms.**

```
Ready for dogfooding. Nothing has been pushed.

Please verify on device:
□ Claim a Cash Link on an empty account
□ Buy a currency with Phantom
□ Scan & Send between 2 devices

Safe to abort. Tell me when you're ready to ship.
```

## Phase 2: Ship

After user confirms:

### 9. Push
```bash
git push -u origin release/flipcash-{version}
git push origin flipcash-{version}
```

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
- Proceed past the gate without explicit user confirmation
- Tag a patch without bumping `MARKETING_VERSION` on the release branch (step 4b) — TestFlight rejects duplicate build versions
- Open the major/minor bump PR yourself — step 3 stops and asks the user to do it; the bump must descend from a merged `main` commit before /release continues
- Cut the release branch or tag from a local-only bump commit — always branch from the `main` whose `origin/main` already has the merged bump
- Resolve cherry-pick conflicts autonomously — stop and hand off to the user
