---
name: triage
description: Daily Bugsnag triage ritual — surface the top open production issue, investigate with evidence, propose a fix direction, route through experts, write a lean review brief.
argument-hint: "[--skip <count> | --id <bugsnag_id_or_url>]"
model: opus
effort: max
allowed-tools:
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Skill
  - Bash(./.claude/skills/triage/scripts/bugsnag-top.sh:*)
  - Bash(curl:*)
  - Bash(jq:*)
  - Bash(git log:*)
  - Bash(git show:*)
  - Bash(find:*)
---

# Triage

<!-- `ultrathink` escalates the harness to max thinking budget. The harness scans for it as a standalone token, so it must remain on its own line and not be wrapped in code fences or prose. -->
ultrathink

You are running the daily Bugsnag triage ritual. The deliverable is **one lean review brief** at `.claude/plans/<YYYY-MM-DD>-bugsnag-<short_id>.md`. The brief is the user's review artifact — see `references/brief-template.md` for the structure and word cap.

## Hard rules

1. **Max effort, no shortcuts.** Read full stack traces. Read each source file the trace touches in full, not snippets. Trace through callers when the crash site is ambiguous. Never skip an expert review when the trigger applies.
2. **No claim without a citation.** Every assertion in the brief (stack lines, "this is the root cause", "this code path runs first") must be followed by a `file.swift:NN` reference or a quoted log/breadcrumb excerpt. If unable to cite, mark as "hypothesis, unverified" and propose how to verify.
3. **Root cause must be reachable from evidence.** The Root cause section is a short chain: `evidence → inference → evidence → inference → cause`. No leaps. If the chain breaks, the section is renamed "Leading hypothesis" and the Proposed direction becomes "Verification steps".
4. **No mid-flow questions.** The brief is the review checkpoint. Don't ask the user anything until it's written.
5. **Skip experts whose triggers don't apply.** Running an irrelevant expert wastes tokens.

## Steps

### 1. Fetch the issue

Run the data fetch script with whatever arguments the user passed (`--skip <N>` or `--id <bugsnag_id_or_url>`):

```bash
./.claude/skills/triage/scripts/bugsnag-top.sh $ARGUMENTS
```

The script emits one JSON object on success. On any non-zero exit, the script already wrote a clear stderr message — relay that to the user verbatim and stop. Do not proceed.

When `--id` is used, the script bypasses the default filters (status=open, release_stage=production, last 7d) so the user can target any issue — including closed, fixed, ignored, or stale ones — directly.

Parse the JSON. You'll use:

- `id`, `short_id`, `error_class`, `message`
- `events`, `users`, `first_seen`, `last_seen`, `release_stages`
- `introduced_in_release`, `grouping_hint`
- `html_url` (browser link to put in the brief header)
- `latest_event_id`, `latest_event_url` (for fetching the full event report next)

### 2. Existing-plan check

Glob `.claude/plans/*-bugsnag-<short_id>.md`.

If a file matches, exit immediately with a one-liner pointing at it. Format:

> Top issue `<short_id>` already triaged → `<matching path>`. Use `/triage --skip <N+1>` for the next-ranked issue.

…where `N` is the `--skip` value used (defaulting to 0). Do not write a second brief.

### 3. Invoke systematic-debugging

Use the `Skill` tool to invoke `superpowers:systematic-debugging`. That skill owns the evidence-before-conclusion discipline for the rest of this run.

### 4. Fetch the full latest event

The event endpoint returns a full report:

```bash
curl -sH "Authorization: token $BUGSNAG_TOKEN" -H "X-Version: 2" "<latest_event_url>"
```

Confirm the response has `is_full_report: true`. If `false`, the event is truncated and you cannot reason about its stack — note this in the brief and propose better instrumentation.

#### 4a. Version sanity check (skip stale versions)

**Skip this step entirely if `$ARGUMENTS` contains `--id`.** The user explicitly chose this issue; honor the override.

Otherwise, don't waste cycles investigating a bug that's only firing on old app builds. Read the current marketing version from the project:

```bash
grep -m1 'MARKETING_VERSION = ' Code.xcodeproj/project.pbxproj | sed 's/.*= //; s/;//' | xargs
```

The first match is good enough — across configurations the app uses one marketing version, and any one of them is a valid baseline for the staleness comparison.

Compare it (semver) to the event's `app.version`. Skip the issue — print a one-liner and stop, do not write a brief — when either condition holds:

- **`app.version` is missing or empty** → the event is corrupted or odd. Skip:
  > Top issue's latest event has no `app.version` (corrupted or odd event). Skipping. Use `/triage --skip <N+1>`.
- **`app.version` is older than the local marketing version** → likely fixed in a newer build. Skip:
  > Top issue last seen in `<event.app.version>` but you're on `<MARKETING_VERSION>`. Likely fixed in a newer build. Use `/triage --skip <N+1>` for the next-ranked current-version issue.

Where `<N>` is the current `--skip` value (defaulting to 0).

Read `references/event-shape.md` for the full structure of the event response and which sections are first-class evidence sources. The four that drive citations:

- `exceptions[0].stacktrace` (frames with `in_project`)
- `metaData.nserror` (Swift error domain/code/userInfo, often with `location: file.swift:NN`)
- `metaData.app_logs.recent_logs` (chronological log stream — usually the strongest signal)
- `breadcrumbs[]` (timestamped UI/state events)

Plus secondary context in `metaData.app`, `metaData.device`, `feature_flags`, `user`, `session`, `request`.

Save the response to a tempfile (`mktemp`) and run subsequent jq queries against the file. Never re-curl the same event — it's the hottest part of the run.

### 5. Locate source files for app frames

For each `in_project: true` stack frame **and** each file mentioned in `metaData.nserror.userInfo.location` (Swift errors thrown via `ErrorReporting.captureError` typically include the call-site file:line in nserror, which is more useful than the top stack frame — the top frame is usually `ErrorReporting.capture` itself):

- The `file` path is a CI build path like `Volumes/workspace/repository/Flipcash/Utilities/ErrorReporting.swift`. Strip the `Volumes/workspace/repository/` prefix to get the local repo path.
- `Read` the file in full (no `limit`/`offset` unless the file genuinely exceeds the read window — if it does, read the relevant section anchored on `line_number`).
- If a frame is in generated/SDK code (`<compiler-generated>`, `Generated/`, package sources), walk one frame up to find the calling app code.
- If the file no longer exists at that path, run `git log --follow --all -- '*<basename>'` to find rename/move history.

#### 5a. Possible-fix check (commit verification)

Once the touched files are known, look for commits that may already address this issue:

```bash
git log --since="<last_seen>" --oneline -- <file1> <file2> ...
```

If any commits are found, capture each as `<short_sha> — <subject>` and which file(s) it touched. These go into the brief as a `## ⚠️ Possible fix already in main` section right after the header (before Root cause). If no commits are found, the section is omitted entirely.

This is **not** a skip — keep investigating. The flag tells the reviewer to check whether the listed commits actually address the root cause before further action.

### 6. Build the evidence chain

Mine all four sources for citations:

1. **`metaData.app_logs.recent_logs`** — scan for ERROR/WARNING lines, repeated patterns, and the last few lines before the throw. Quote them in Evidence with their timestamps. This is usually the strongest signal for "what was the user actually doing?"
2. **`metaData.nserror.userInfo`** — extract `location`, plus any domain-specific keys (`mint`, `amount`, `intentId`, etc.). These are the exact runtime values at crash time.
3. **Stack trace** — the throw point and the call chain. Cite app frames as `file.swift:NN`.
4. **`breadcrumbs[]`** — UI/state events around the crash. Quote with `[<timestamp>] <type> — <name>` and any relevant `metaData`.

Then check git context for the touched files:

```bash
git log --since="<first_seen>" -- <file>
```

For each Root cause claim, gather a citation from at least one of the four sources above. If you cannot cite, downgrade the language to "hypothesis, unverified".

### 7. Draft the brief

Write the file at `.claude/plans/<YYYY-MM-DD>-bugsnag-<short_id>.md` (today's date in ISO format). Read `references/brief-template.md` for the exact structure and the word cap.

### 8. Run /simplify

Use the `Skill` tool to invoke the project's `simplify` skill on the draft brief. Apply the feedback in place. Note the key insight in the Expert input section.

### 9. Route to domain experts (parallel where independent)

Inspect the **Proposed direction** you wrote. For each trigger that applies, dispatch the matching expert via `Skill` (run independent experts in parallel by issuing multiple Skill calls in one assistant turn — see `superpowers:dispatching-parallel-agents`):

| Expert | Trigger |
|--------|---------|
| `swiftui-expert:swiftui-expert-skill` | Proposed direction touches files under `Flipcash/Core/Screens/`, `FlipcashUI/Sources/`, or any `.swift` containing `View`, `@State`, `@Observable`, `@Environment`. Also: hangs / hitches / matched-geometry errors in the stack. |
| `swift-concurrency:swift-concurrency` | Stack trace contains `Task`, `Sendable`, `actor`, `@MainActor`, `await`, `_dispatch_assert_queue`, or `EXC_BAD_ACCESS` on a known concurrent path. Also: proposed direction changes isolation, adds/removes `@MainActor`, or wraps in `Task { }`. |
| `swift-testing-expert:swift-testing-expert` | Proposed direction adds files under `FlipcashTests/`, `FlipcashCoreTests/`, or modifies any `@Suite` / `@Test`. |
| `xcuitest-resilience` | Proposed direction adds files under `FlipcashUITests/` or modifies `XCUIApplication` / `XCUIElement` usage. |

After each expert returns, fold their concrete actionable feedback into the brief: tighten the Proposed direction if needed, append a one-bullet summary under Expert input. Skipped experts are omitted entirely from the brief — no empty headings.

Update the `Experts consulted:` line in the brief header.

### 10. Print the chat summary

A 4–6 line summary, no code blocks:

- Error class and short id
- Last 7d events / users
- Root cause one-liner
- Experts consulted
- Path to brief file

That's the end of the run.

## Failure modes

The script handles all API-side failures (missing token, 401, network down, no qualifying issues, --skip overrun) and exits with a clear stderr message. Relay it and stop.

For investigation-side failures:

- **Latest event has zero `in_project: true` frames AND empty `metaData.app_logs` / `metaData.nserror`** — only then write the "insufficient symbolicated app frames" brief and skip experts. If app frames are absent but `metaData.nserror.userInfo.location` or `metaData.app_logs.recent_logs` has content, those are valid evidence sources — proceed normally and cite from them.
- **Source file moved/renamed** — use `git log --follow --all -- '*<basename>'`. Note the rename with the commit SHA in Evidence.
- **Plan file write fails** — print the error verbatim. Don't dump the brief content to chat as a fallback.
- **Expert skill invocation fails** — note in Expert input as `**/<expert>**: skipped — <error>`. Don't fail the whole run.
