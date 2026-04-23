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
Derive the current released version from the pre-flight latest tag (strip the `flipcash-` prefix). The `MARKETING_VERSION` in the project file is always bumped ahead for TestFlight builds and must NOT be used.

Determine bump type from `$ARGUMENTS` (default: `minor`):

| Argument | Bump | Example |
|----------|------|---------|
| `major` | X+1.0.0 | 2.3.1 → 3.0.0 |
| `minor` (default) | X.Y+1.0 | 2.3.1 → 2.4.0 |
| `patch` | X.Y.Z+1 | 2.3.1 → 2.3.2 |

Confirm with user: "Bumping {type}: flipcash-{current} → flipcash-{next} — correct?"

### 3. Determine base
- **major / minor**: base is HEAD on the current branch. Show the pre-flight latest tag to user. If it picks up a legacy tag, ask for the correct base.
- **patch**: base is the `release/flipcash-X.Y.Z` branch (the release being patched). Checkout that branch before proceeding:
  ```bash
  git checkout release/flipcash-{current-version}
  ```

### 3a. Cherry-pick commits (patch only)
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

### 3b. Bump MARKETING_VERSION (patch only)
The release branch's `Code.xcodeproj/project.pbxproj` is still pinned at `{current-version}`. The binary produced from this branch needs the patched version or TestFlight/App Store will reject it as a duplicate. Use the Edit tool with `replace_all: true`:

- **old_string**: `MARKETING_VERSION = {current-version};`
- **new_string**: `MARKETING_VERSION = {next-version};`

Other targets in the pbxproj use different `MARKETING_VERSION` values (legacy apps, test targets), so `replace_all` is safe — it only hits the Flipcash target.

Then commit:
```bash
git add Code.xcodeproj/project.pbxproj
git commit -m "chore: bump version to {next-version}"
```

### 4. What's shipping
```bash
git log {base-tag}..HEAD --format="- %s" --no-merges
```
For patch releases, `{base-tag}` is `flipcash-{current-version}` (the tag on the branch being patched).

Display for sanity check.

### 5. Run all tests
```bash
xcodebuild test -scheme Flipcash \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -testPlan AllTargets
```
The `AllTargets` test plan already includes UI tests. Do NOT run UI tests separately.

Any failure → STOP.

### 6. Generate changelog
Use the Agent tool with `model: "haiku"`. Pass the commit list with this prompt:

> Given these git commits (conventional commit format), write user-facing release notes.
> - Group under: ## New, ## Improved, ## Fixed (omit empty sections)
> - Write for end users — no jargon, file names, or internals
> - One short sentence per item
> - If no user-facing changes, output: Bug fixes and performance improvements.
> - Output ONLY markdown

Show to user for approval.

### 7. Branch and tag
For **major / minor**: the version in `Code.xcodeproj/project.pbxproj` is already bumped ahead for TestFlight — do NOT modify it. Create the branch:
```bash
git checkout -b release/flipcash-{next-version}
```

For **patch**: already on `release/flipcash-X.Y.Z` from step 3; the version bump commit from step 3b is already on the branch. Skip branch creation.

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

### 8. Push
```bash
git push -u origin release/flipcash-{version}
git push origin flipcash-{version}
```

### 9. GitHub Release
```bash
gh release create flipcash-{version} --title "Flipcash {version}" --notes "{changelog}"
```

## Never
- Merge the release branch into main
- Commit changelog files
- Skip the dogfooding gate
- Proceed past the gate without explicit user confirmation
- Tag a patch without bumping `MARKETING_VERSION` on the release branch (step 3b) — TestFlight rejects duplicate build versions
- Resolve cherry-pick conflicts autonomously — stop and hand off to the user
