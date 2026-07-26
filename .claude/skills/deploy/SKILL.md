---
name: deploy
description: Use when the user wants to trigger an Xcode Cloud build for the current branch, kick off the "Deploy Flipcash" workflow, ship an ad-hoc / dogfood build, or push a branch build to a TestFlight group — anything short of a versioned release (for cutting a version, use /release instead).
argument-hint: [testflight-group]
allowed-tools: Bash(git rev-parse *), Bash(git status *), Bash(git push *), Bash(git ls-remote *), Bash(fastlane deploy *), Bash(fastlane distribute *)
---

# Deploy

Triggers the **Deploy Flipcash** Xcode Cloud workflow for the **current branch**, and optionally waits and assigns the resulting build to a TestFlight group. Wraps `fastlane deploy`.

**Not a release.** This builds an arbitrary branch on demand. To cut a version (tag → App Store), use `/release`.

## When to use

- "Trigger a build", "kick off Xcode Cloud", "build this branch", "make a dogfood/TestFlight build"
- "Deploy this to the Internal group" → include the group

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

## Run

Run from the repo root.

| Intent | Command |
|--------|---------|
| Validate + list TestFlight groups, trigger nothing | `fastlane deploy dry_run:true` |
| Just trigger a build | `fastlane deploy` |
| Trigger a specific branch | `fastlane deploy branch:<name>` |
| Trigger **and** assign to a TestFlight group | `fastlane deploy group:'<Group Name>'` |

**Pick the group first.** The group name must match a TestFlight group exactly (case-sensitive) or the lane errors. If the user hasn't named one, run `fastlane deploy dry_run:true` — it prints the available groups (and confirms the workflow + branch resolve) without triggering anything — then confirm the group with the user before the real run.

`group:` makes the lane **block** through the whole Xcode Cloud build + processing (10–30+ min) before assigning — expected, not a hang. Stream the output and report progress. If the user doesn't want to wait, run `fastlane deploy group:'<Group>' wait:false` and tell them to run `fastlane distribute group:'<Group>'` once the build finishes processing.

Assign a group to an already-built build without triggering a new one: `fastlane distribute group:'<Group>' [build:<number>]`. Dry-run the upload half with `fastlane distribute group:'<Group>' dry_run:true` — it confirms the group resolves and reports which build would be assigned (and whether it's processed), without assigning and without blocking.

## Report

State the build number the lane printed and where to watch it (App Store Connect → Xcode Cloud → Builds). If a group was requested, confirm the build was assigned once the lane finishes.

## Don't

- Don't trigger against a branch whose local HEAD isn't on origin — you'd build stale code. Push first.
- Don't guess a TestFlight group name. If the user didn't name one, either omit `group:` or ask which group.
- Don't use this to cut a release — that's `/release`.
