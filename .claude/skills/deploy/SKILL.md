---
name: deploy
description: Use when the user wants to trigger an Xcode Cloud build for the current branch, kick off the "Deploy Flipcash" workflow, ship an ad-hoc / dogfood build, push a branch build to a TestFlight group, or set a TestFlight build's "What to Test" notes — anything short of a versioned release (for cutting a version, use /release instead).
argument-hint: [testflight-group]
allowed-tools: Bash(git rev-parse *), Bash(git status *), Bash(git push *), Bash(git ls-remote *), Bash(git fetch *), Bash(git log *), Bash(git merge-base *), Bash(fastlane deploy *), Bash(fastlane distribute *), Read, Write, Agent
---

# Deploy

Triggers the **Deploy Flipcash** Xcode Cloud workflow for the **current branch**, and optionally waits, gives the resulting build its TestFlight "What to Test" notes, and assigns it to a TestFlight group. Wraps `fastlane deploy`.

**Not a release.** This builds an arbitrary branch on demand. To cut a version (tag → App Store), use `/release`.

## When to use

- "Trigger a build", "kick off Xcode Cloud", "build this branch", "make a dogfood/TestFlight build"
- "Deploy this to the Internal group" → include the group
- "What should testers try?", "add release notes to that build" → the What to Test section below

## Preconditions

Xcode Cloud builds the commit at the **tip of the branch on origin**, and the lane refuses to run otherwise. Before invoking:

1. Confirm the branch is pushed and up to date:
   ```bash
   git rev-parse --abbrev-ref HEAD          # the branch that will build
   git status --porcelain                    # must be clean-ish; uncommitted work won't build
   git ls-remote origin refs/heads/$(git rev-parse --abbrev-ref HEAD)
   ```
2. If origin is missing the branch or behind local HEAD, offer to `git push -u origin <branch>` (ask first).

`fastlane/.env` must hold the ASC API creds (`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_CONTENT`, `APP_IDENTIFIER`). If the lane reports one missing, tell the user to run `Scripts/pull_secrets fastlane` (or restore `fastlane/.env`).

## What to Test

Give the build its own TestFlight notes — same shape as `/release` step 8a, different mechanism.

**Why a different mechanism.** Xcode Cloud attaches `TestFlight/WhatToTest.en-US.txt` from the
commit it builds, so a branch build inherits whatever the last release committed — a baseline
checklist that says nothing about this branch. `/release` solves that by committing the file on the
release branch. A feature branch can't: that commit would land in the PR. So `/deploy` writes the
notes onto the finished build through the App Store Connect API instead (`notes_file:`), which
overwrites what Xcode Cloud attached.

**This requires waiting for the build** (10–30+ min) — the notes can only be set after the build
uploads, or Xcode Cloud's copy wins. Passing `notes_file:` turns waiting on by itself, the same way
`group:` does. With `wait:false`, skip the notes and tell the user to run
`fastlane distribute notes_file:<path>` once the build processes.

### 1. What's on the branch

```bash
git fetch origin main
git log $(git merge-base origin/main HEAD)..HEAD --format="- %s" --no-merges
```

If the user named a different branch, substitute it for `HEAD`. If the branch *is* `main`, use the
latest release tag as the base instead: `git log $(git describe --tags --match 'flipcash-*' --abbrev=0)..HEAD`.

### 2. Draft the notes

Use the Agent tool with `model: "haiku"`. Pass the commit list with this prompt:

> Given these git commits (conventional commit format), write TestFlight "What to Test" notes.
> - Plain text, one `•` bullet per item — no markdown headers, no bold
> - Each bullet is a flow a tester can actually run end to end, not a description of the code
> - Write for a tester, not a developer — no file names, module names, or internals
> - Skip commits with nothing to exercise (build config, CI, dependency bumps)
> - If nothing is testable, output: Nothing branch-specific — run the baseline below.
> - Output ONLY the bullets

### 3. Assemble and confirm

Read the committed `TestFlight/WhatToTest.en-US.txt` and carry its **Baseline** block over
unchanged — testers should run the same core-money-flow checklist on every build, and keeping it
verbatim keeps `/deploy` and `/release` in sync. Assemble:

```
What to test in this build
<branch name, and the PR link if there is one>

New on this branch:
<the step-2 bullets>

Baseline — always verify these core money flows:
<the Baseline bullets from the committed file, unchanged>

Report anything off — wrong amounts, stuck screens, or crashes.
```

Show it to the user for approval, then write the approved text to a scratch file (multi-line notes
through a shell argument is a quoting trap) and pass `notes_file:` on the run.

Cap: Apple rejects over 4000 bytes. The lane truncates rather than failing, but trim the bullets
instead of relying on that.

## Run

Run from the repo root.

| Intent | Command |
|--------|---------|
| Validate + list TestFlight groups, trigger nothing | `fastlane deploy dry_run:true` |
| Just trigger a build | `fastlane deploy` |
| Trigger a specific branch | `fastlane deploy branch:<name>` |
| Trigger **and** assign to a TestFlight group | `fastlane deploy group:'<Group Name>'` |
| Trigger, set "What to Test", assign | `fastlane deploy group:'<Group Name>' notes_file:<path>` |
| Set "What to Test" without changing groups | `fastlane deploy notes_file:<path>` |

**Pick the group first.** The group name must match a TestFlight group exactly (case-sensitive) or the lane errors. A default lives in the `TESTFLIGHT_GROUP` env var (in `fastlane/.env`, kept out of the repo); an explicit `group:'Name'` overrides it. If neither is set and the user hasn't named one, run `fastlane deploy dry_run:true` — it prints the available groups (and confirms the workflow + branch resolve) without triggering anything — then confirm the group with the user before the real run.

`group:` makes the lane **block** through the whole Xcode Cloud build + processing (10–30+ min) before assigning — expected, not a hang. Stream the output and report progress. If the user doesn't want to wait, run `fastlane deploy group:'<Group>' wait:false` and tell them to run `fastlane distribute group:'<Group>'` once the build finishes processing.

Act on an already-built build without triggering a new one: `fastlane distribute group:'<Group>' [build:<number>] [notes_file:<path>]` — `group:` and `notes_file:` are independently optional, so this also re-writes the notes on a build that's already with its testers. Dry-run the upload half with `fastlane distribute group:'<Group>' dry_run:true` — it confirms the group resolves and reports which build it would act on (and whether it's processed), without changing anything and without blocking.

**From GitHub instead of locally:** the same flow is exposed as the `Deploy to TestFlight (Xcode Cloud)` workflow (`.github/workflows/deploy.yml`) — Actions tab → Run workflow → pick a branch. It runs the lane on an ubuntu runner using the repo's ASC secrets, and assigns to the `TESTFLIGHT_GROUP` secret when the group field is left blank. Its `notes` field is the "What to Test" — a single-line box, so line breaks go in as literal `\n` and the workflow expands them. Point users there when they can't or don't want to run fastlane locally.

## Report

State the build number the lane printed and where to watch it (App Store Connect → Xcode Cloud → Builds). If a group was requested, confirm the build was assigned once the lane finishes. If notes were set, say so — testers see them as the build's "What to Test".

## Don't

- Don't trigger against a branch whose local HEAD isn't on origin — you'd build stale code. Push first.
- Don't guess a TestFlight group name. If the user didn't name one, either omit `group:` or ask which group.
- Don't commit `TestFlight/WhatToTest.en-US.txt` on a feature branch to set the notes — that file is `/release`'s mechanism and the commit would land in the PR. Use `notes_file:`.
- Don't set notes on a build you didn't wait for — with `wait:false` the write would land before Xcode Cloud attaches the committed file, and be overwritten.
- Don't use this to cut a release — that's `/release`.
