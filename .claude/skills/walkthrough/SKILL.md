---
name: walkthrough
description: Walk the house — inspect everything that merged to main since the last walkthrough, judge each touched screen against the House Standard, and write a ranked punch list of cohesion fixes with evidence. Use when the user says "walkthrough", "walk the house", "what shipped this week", "punch list", "inspect what merged", on a weekly cadence, or after a version bump.
argument-hint: "[--since <sha|date>] [--area <ScreenFolder>] [--no-build]"
model: opus
effort: high
---

# Walkthrough

You are inspecting the house after a week of other people's work. The deliverable is **one punch
list** at `.claude/plans/<YYYY-MM-DD>-walkthrough.md`: what drifted from the standard, ranked by what
to fix first, each item with evidence. As in `/triage`: no claim without a citation, and that file is
the only thing you create (plus screenshots in the session scratchpad).

## 1. The range

- Repo remote: the one that points at `code-payments/code-ios-app`; `git fetch` it. Main is its `main`.
- `--since` given: use it. Otherwise read the newest `.claude/plans/*-walkthrough.md` and take the end
  SHA of its `Range:` line. None at all: the last version bump
  (`git log <main> --grep 'bump version' -1 --format=%H`).
- Commits: `git log <from>..<main> --format='%h %s' -- Flipcash/Core/Screens FlipcashUI/Sources Shared`.
  Squash-merged, so one commit is one PR and the `(#N)` is its number. Drop `test:`, `ci:` and
  `chore(deps)` subjects. Zero commits: say so and stop.

## 2. Survey

One `design-surveyor` per screen folder touched, in parallel, each with the commit list for that
folder. Each returns the files, values, components, states and motion for what changed, grouped by
screen. With `--area`, survey only that folder.

## 3. See it (skipped with `--no-build`)

Build and run on the simulator so the critic judges screens, not hunks.

- `./Scripts/build.sh` for the simulator (filtered through xcsift), then install and launch with
  `simctl` as the `verify` skill does, including its test-account login deeplink. If
  `FLIPCASH_UI_TEST_ACCESS_KEY` is absent, ask the user to sign in once on the simulator; app data
  survives reinstalls.
- Reach each touched screen (loupe per `verify` where it is installed; otherwise the simulator
  control tool; otherwise ask the user to tap through while you capture) and save
  `xcrun simctl io <udid> screenshot <scratchpad>/walkthrough/<Screen>.png`. Capture empty and error
  states where a launch argument or a mock reaches them.
- A screen you could not reach is listed under Needs a device, never skipped silently.

## 4. Judge

One `design-critic` per screen folder, in parallel, with: the surveyor's document, the screenshots,
all three lenses, and the commit subjects as the claims. Ask it to judge each screen as it now stands,
not only the diff: an addition that is fine alone and wrong beside its neighbours is a cohesion
finding.

## 5. Write the punch list

```markdown
# Walkthrough — <YYYY-MM-DD>

Range: <from>..<to> (<N> commits, <M> screens) · Seen on the simulator: <list> · Read only: <list>

## Punch list

| # | Screen | Finding (what the user sees) | Rule | Evidence | Fix scope | Owner |
|---|---|---|---|---|---|---|

## Taste calls for Aiden
## Checked sound
## Needs a device
## Standard gaps
```

Rank: first-session-visible and cross-screen inconsistencies first, then single-screen defects, then
polish. Fix scope is one of `value change`, `screen PR`, `system PR (lists screens)`, `decision`.
Owner is `Aiden` (renovation), `Brandon` (defect), or `Decision` (both). Cap the file at 900 words.
Every row cites `path:line` or a screenshot file.

## 6. Chat summary

Five lines: the range, screens seen versus read, the top three items, the path to the file, and the
next step as a phrase the user can say (`start the <Screen>`).

## Hard rules

- Only the punch list and scratchpad screenshots are written. No source, test, or config changes.
- No GitHub comments or issues from this skill.
- Nothing is skipped silently: an area not surveyed, built, or seen is listed as such.
