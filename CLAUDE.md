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
| Setting up, building, or regenerating protos; touching SQLite/CodeScanner | [Technology Stack, Setup & Tooling](.claude/docs/technology-stack.md) |
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

- **Understand the context.** Take your time to understand how the changes _should_ fit into the complete project. Perhaps a refactor is required. Perhaps the current structure is not ideal. Take your time to identify this.
- **Double-check your work.** Verify changes compile and don't break existing functionality.
- **Ask clarifying questions.** When requirements are ambiguous or something is unclear or can have multiple meanings, don't assume. Ask clarifying questions where needed but try to keep these as concise and as minimal as possible.

### Before Making Changes

1. Read the relevant files first - never propose changes to code you haven't read
2. Understand the existing patterns and conventions in the current file but also any related or dependant files
3. Check module boundaries (see Hard Rules below)
4. Consider impact on other parts of the codebase

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
- **Generated files** — Never edit files under `Generated/`; change the wrapping service files instead.
- **Database schema** — Bump `SQLiteVersion` in Info.plist on every schema change (no migrations; DB is rebuilt from server).
- **Logging** — Message string is a constant; every variable goes in structured `metadata`. Never log proto blobs whole.
- **Error reporting** — Call `ErrorReporting.captureError(...)` unconditionally; classify via `ServerError.reportingLevel`, never gate at the call site. Best-effort chatter never reports.
- **Form validation** — Validate free-form input through the `Validator` family and submit the validator's `Output`, never inline regex/trim; keypad amounts parse only via `AmountValidator`.
- **Money & numbers** — Follow the Nine Rules: money lives in `TokenAmount`/`FiatAmount`/`ExchangedFiat`; one parse in, one format out; compare only within a domain; display-rounded is what we accept; affordability goes through `Session.hasSufficientFunds(for:)`.
- **Package.resolved** — Always commit the workspace `Package.resolved`; individual package ones stay gitignored.
