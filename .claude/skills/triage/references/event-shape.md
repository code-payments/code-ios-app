# Bugsnag event report shape

A reference for what's in the full event response from `GET /projects/<project_id>/events/<event_id>` and how to use each section during investigation.

The full report (`is_full_report: true`) is required. The truncated event embedded in the issues list response is missing most of the useful fields — always fetch the standalone event endpoint.

## Top-level keys

| Key | Notes |
|-----|-------|
| `id` | Event id |
| `error_id` | Parent error/issue id |
| `is_full_report` | Must be `true`; if not, the event is truncated and you cannot reason from it |
| `received_at` | When Bugsnag received the report |
| `severity` | `error` / `warning` / `info` |
| `unhandled` | `true` for crashes, `false` for handled errors |
| `exceptions[]` | Stack trace data (see below) |
| `breadcrumbs[]` | Timestamped UI/state events |
| `metaData` | Custom metadata buckets — `nserror`, `app_logs`, `app`, `device` |
| `app`, `device`, `user`, `session`, `request`, `feature_flags` | Runtime context |
| `threads[]` | Other threads at crash time (rarely needed) |
| `correlation` | Spans / trace correlation if instrumented |
| `missing_dsym` | Boolean — if true, the event isn't symbolicated |

## Four first-class evidence sources

These four are where citations come from. Order is roughly by signal strength.

### `metaData.app_logs.recent_logs`

Chronological log stream leading up to the crash. Each line carries timestamp, level, subsystem, message, and the structured `metadata` from `logger.x(...)` calls.

**Why it matters:** the user's session in narrative form. Reveals patterns that stack traces hide — repeated retries, state transitions, race-window timing. For our test issue (`invalidIntent insufficient balance`), this section showed seven retries of the same withdrawal in 40 seconds, which is invisible from the stack trace.

**How to cite:** `log [<timestamp>] <level> <subsystem> — <verbatim line>`.

### `metaData.nserror`

The Swift error context. Has `domain`, `code`, `reason`, and `userInfo`.

`userInfo` typically includes:

- `location` — file:line where the error was thrown (e.g., `WithdrawViewModel.swift:completeWithdrawal():371`). This is more useful than the top stack frame because the top frame is usually `ErrorReporting.capture` itself.
- Domain-specific structured fields the developer attached: `mint`, `amount`, `quarks`, `destination`, `intentId`, etc.

**How to cite:** `nserror.userInfo — <key>=<value>` for runtime values, or treat `location` as a normal `file.swift:NN` citation.

### `exceptions[0].stacktrace`

Frames with `method`, `file`, `line_number`, `in_project`. Iterate `in_project: true` frames for app code; walk one frame up if a frame is in generated/SDK code.

**Path mapping:** the `file` field is a CI build path like `Volumes/workspace/repository/Flipcash/Utilities/ErrorReporting.swift`. Strip `Volumes/workspace/repository/` to get the local repo path.

**How to cite:** `<file>:<line>` (after stripping the prefix).

### `breadcrumbs[]`

Timestamped UI/state events — Bugsnag-managed (orientation changes, scenePhase) plus app-emitted. Recent events lead up to the throw.

**How to cite:** `breadcrumb [<timestamp>] <type> — <name>` plus any relevant `metaData` fields.

## Secondary context

- `metaData.app` / `app` — bundle id, version, build, release stage. Use for "is this version-specific?"
- `metaData.device` / `device` — model, OS, free disk, RAM. Use for "is this device-specific?"
- `feature_flags` — flags active at crash time. Use for "is this a flagged-rollout issue?"
- `user`, `session` — disambiguate "one user retrying" vs "many users hitting".
