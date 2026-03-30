---
name: release
description: Use when the user wants to cut a release, ship a version, prepare for release, or invokes /release
disable-model-invocation: true
argument-hint: [major|minor|patch]
allowed-tools: Bash(git log *), Bash(git checkout *), Bash(git tag *), Bash(git push *), Bash(git add *), Bash(git commit *), Bash(xcodebuild *), Bash(gh *), Read, Edit, Agent, Grep
---

# Release

Two-phase workflow with a dogfooding gate. Nothing leaves the machine until the user confirms they've tested on device.

## Pre-flight context

- Working tree: !`git status --porcelain`
- Latest tag: !`git describe --tags --abbrev=0 HEAD 2>/dev/null || echo "no tags found"`
- Marketing version: !`grep 'MARKETING_VERSION' Code.xcodeproj/project.pbxproj | head -1 | sed 's/.*= //' | tr -d ';\" '`

## Phase 1: Prepare & Verify

### 1. Clean working tree
If the pre-flight working tree output is non-empty → STOP. Commit or stash first.

### 2. Calculate next version
Parse the pre-flight marketing version as X.Y.Z. Determine bump type from `$ARGUMENTS` (default: `minor`):

| Argument | Bump | Example |
|----------|------|---------|
| `major` | X+1.0.0 | 2.3.1 → 3.0.0 |
| `minor` (default) | X.Y+1.0 | 2.3.1 → 2.4.0 |
| `patch` | X.Y.Z+1 | 2.3.1 → 2.3.2 |

Confirm with user: "Bumping {type}: v{current} → v{next} — correct?"

### 3. Determine base
- **major / minor**: base is HEAD on the current branch. Show the pre-flight latest tag to user. If it picks up a legacy tag, ask for the correct base.
- **patch**: base is the `release/X.Y.Z` branch (the release being patched). Checkout that branch before proceeding:
  ```bash
  git checkout release/{current-version}
  ```

### 4. What's shipping
```bash
git log {base-tag}..HEAD --format="- %s" --no-merges
```
For patch releases, `{base-tag}` is `v{current-version}` (the tag on the branch being patched).
Display for sanity check.

### 5. Run all tests
```bash
xcodebuild test -scheme Flipcash \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -testPlan AllTargets
```
```bash
xcodebuild test -scheme Flipcash \
  -only-testing:FlipcashUITests \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```
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

### 7. Branch, bump, and tag
For **patch**: already on `release/X.Y.Z` from step 3.
```bash
git checkout -b release/{next-version}
```
For **major / minor**:
```bash
git checkout -b release/{next-version}
```

Update `MARKETING_VERSION` in `Code.xcodeproj/project.pbxproj` to `{next-version}` using the Edit tool, then:
```bash
git add Code.xcodeproj/project.pbxproj
git commit -m "chore: bump version to {next-version}"
git tag v{next-version}
```

## STOP — Dogfooding Gate

**Do NOT proceed until the user explicitly confirms.**

```
Ready for dogfooding. Nothing has been pushed.

Please verify on device:
□ Claim a Cash Link
□ Scan & Send between 2 devices

Safe to abort. Tell me when you're ready to ship.
```

## Phase 2: Ship

After user confirms:

### 8. Push
```bash
git push -u origin release/{version}
git push origin v{version}
```

### 9. GitHub Release
```bash
gh release create v{version} --title "v{version}" --notes "{changelog}"
```

## Never
- Merge the release branch into main
- Commit changelog files
- Skip the dogfooding gate
- Proceed past the gate without explicit user confirmation
