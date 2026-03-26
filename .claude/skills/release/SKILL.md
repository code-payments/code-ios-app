---
name: release
description: Use when the user wants to cut a release, ship a version, prepare for release, or invokes /release
---

# Release

Two-phase workflow with a dogfooding gate. Nothing leaves the machine until the user confirms they've tested on device.

## Phase 1: Prepare & Verify

### 1. Clean working tree
```bash
git status --porcelain
```
Non-empty → STOP. Commit or stash first.

### 2. Release version
Read `MARKETING_VERSION` from the Flipcash target in `Code.xcodeproj/project.pbxproj`.
Confirm with user: "Releasing v{version} — correct?"

### 3. Previous tag
```bash
git describe --tags --abbrev=0 HEAD
```
Show to user. If it picks up a legacy tag, ask for the correct base.

### 4. What's shipping
```bash
git log {previous-tag}..HEAD --format="- %s" --no-merges
```
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

### 7. Branch and tag
```bash
git checkout -b release/{version}
git tag v{version}
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
- Bump MARKETING_VERSION or CURRENT_PROJECT_VERSION
- Commit changelog files
- Skip the dogfooding gate
- Proceed past the gate without explicit user confirmation
