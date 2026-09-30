# Claude Guidelines for Flipcash iOS

This file provides instructions for Claude when working on the Flipcash iOS codebase. It is
the always-loaded index; the detailed reference material lives under [`.claude/docs/`](.claude/docs/)
and is linked from the map below. **Read the relevant doc before working in that area.**

---

## Documentation Map

| When you're… | Read |
|---|---|
| About to write/change any code | [Hard Rules](.claude/docs/hard-rules.md) — full text, rationale, examples (checklist below) |
| Working on DI, gRPC, navigation, transport errors, or core concepts | [Architecture & Patterns](.claude/docs/architecture.md) |
| Setting up, building, or bumping the contract packages; touching SQLite/CodeScanner | [Technology Stack, Setup & Tooling](.claude/docs/technology-stack.md) |
| Writing or running tests | [Testing](.claude/docs/testing.md) |
| Naming, file placement, imports, or committing | [Code Style & Git Workflow](.claude/docs/code-style.md) |
| About to touch cash bills, navigation, dialogs, amounts, or DI | [Common Pitfalls](.claude/docs/common-pitfalls.md) |
| Looking for a key file, constant, or the Xcode MCP setup | [Quick Reference](.claude/docs/quick-reference.md) |

---

## Maintaining This Document

**Claude should proactively update these docs** when discovering critical information that would prevent mistakes or save significant time in future sessions. This includes:

- New hard rules or constraints discovered through errors
- Critical patterns that aren't obvious from the code
- Module boundaries or dependencies that caused issues
- Non-obvious project conventions

**Keep it lean.** Only add information that is:
1. Not discoverable by reading the code directly
2. Would cause errors or significant rework if unknown
3. Applies broadly across the project (not one-off edge cases)

**Place new content in the right file.** A one-line pointer or non-negotiable rule belongs in this `CLAUDE.md`; detailed rationale, examples, tables, and area-specific guidance belong in the matching doc under `.claude/docs/`. Remove outdated information when it no longer applies.

---

## Plans & Analysis Records

**Record analyses and implementation plans in `.claude/plans/`** when:

- Performing deep-dive analysis of new features or RPC changes
- Planning multi-step implementations
- Documenting architectural decisions
- Investigating complex systems that span multiple files

**File naming:** `YYYY-MM-DD-<topic>.md` (e.g., `2025-11-27-swap-rpc-analysis.md`)

**Purpose:** These records allow future sessions to reference prior analysis without re-exploring the codebase. Keep them detailed but focused on actionable information.

---

## Reflections

**Review [`.claude/reflections/index.md`](.claude/reflections/index.md) before making changes.** This log documents past situations where fixes went off track — over-engineering, breaking existing patterns, or introducing regressions. Reading it helps avoid repeating the same mistakes.

---

## Behavior & Approach

### Working Style

- **Understand the context.** Before editing, read the callers and neighbors of what you change, and check module boundaries. If the right fix needs a refactor beyond the task, say so in the report instead of doing it.
- **Done means the Before Committing checklist passes** ([code-style.md](.claude/docs/code-style.md#before-committing)).
- **Ask only when the answer would change what you build.** Otherwise pick the most reasonable reading, name it in the report, and keep going.

### End-of-run report

End every long run with three headings, in this order:
- **Blocked on me** — decisions left open, approvals needed, anything the user must run (e.g. `AllTargets`). Write "Nothing" if empty.
- **Changed** — files and commits, one line each.
- **Found** — bugs, risks, or doc drift noticed along the way that were out of scope.

### Keeping Context Small

Every file read and build log stays in context and is re-sent on each later step.

- Build and test through `./Scripts/build.sh` / `./Scripts/test.sh`, which filter the log through xcsift (`brew install xcsift`). Filter a raw `xcodebuild` or `swift test` the same way ([testing.md](.claude/docs/testing.md#running-the-app--tests)).
- Run the narrowest suite first (`./Scripts/test.sh <Target>/<Suite>/<Test>`), then widen only as far as the change reaches.
- Search first, then read only the lines you need. Don't re-read a file that hasn't changed.
- Wait inside one command (a `--watch` flag, an `until` loop), not in repeated sleep-and-check turns.
- Hand self-contained searches to an `Explore` subagent so their reads stay out of this conversation.
- After two failed attempts at the same fix, stop and report what you learned.

### Communication

- Be direct and concise
- When uncertain, say so rather than guessing
- Provide file paths with line numbers when referencing code (e.g., `Session.swift:326`)

---

## Hard Rules (Non-Negotiable)

These are the non-negotiables, condensed to one line each. **The full text, rationale, and
code examples for every rule live in [`.claude/docs/hard-rules.md`](.claude/docs/hard-rules.md)** — read
it before touching the relevant area.

- **Comments** — Non-private API gets a one-sentence `///` contract doc (what, never how); inline comments state only non-obvious constraints.
- **State lives in named units** — A concern owning >2 pieces of state gets its own `@Observable` class / `actor`, held as a single `let`, never loose fields on a shared controller.
- **Testing framework** — Swift Testing (`import Testing`, `@Suite`/`@Test`), never XCTest.
- **Exhaustive switches** — Prefer `switch` over `if case` for enums so the compiler flags new cases.
- **Modernize incrementally** — Use modern Swift/SwiftUI APIs in net-new/isolated code; don't refactor working code just to modernize. One observation system per class.
- **Generated protos** — `FlipcashAPI` only re-exports the published contract packages; there is no generated code to edit here. Change the wrapping service files instead.
- **Database schema** — Bump `Database.schemaVersion` on every change to what the store *writes*, including the encoding of a persisted blob (no migrations; DB is rebuilt from server). A change that only adds new tables, which start empty and fill from the server, does not bump.
- **Logging** — Message string is a constant; every variable goes in structured `metadata`. Never log proto blobs whole.
- **Error reporting** — Call `ErrorReporting.captureError(...)` unconditionally; classify via `ServerError.reportingLevel`, never gate at the call site. Best-effort chatter never reports.
- **Form validation** — Validate free-form input through the `Validator` family and submit the validator's `Output`, never inline regex/trim; keypad amounts parse only via `AmountValidator`.
- **Money & numbers** — Follow the Nine Rules: money lives in `TokenAmount`/`FiatAmount`/`ExchangedFiat`; one parse in, one format out; compare only within a domain; display-rounded is what we accept; affordability goes through `Session.hasSufficientFunds(for:)`.
- **Package.resolved** — Always commit the workspace `Package.resolved`; individual package ones stay gitignored.
