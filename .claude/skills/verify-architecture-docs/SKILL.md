---
name: verify-architecture-docs
description: Fact-check docs/architecture/*.md against the actual code — catch correctness drift (a doc says X, the code does Y), not just untouched files. Fans out one adversarial checker per doc and writes a drift report.
argument-hint: "[--since <ref> | --doc <path>]"
model: fable
effort: max
allowed-tools:
  - Read
  - Grep
  - Glob
  - Agent
  - Write
  - Bash(git diff:*)
  - Bash(git log:*)
  - Bash(git merge-base:*)
  - Bash(git show:*)
---

# Verify Architecture Docs

ultrathink

You are fact-checking the architecture docs in `docs/architecture/` against the real codebase. The deliverable is **one drift report** at `.claude/plans/<YYYY-MM-DD>-doc-drift.md`. This catches **correctness drift** — a doc that is present but *wrong* — which the path-based upkeep checks (the CLAUDE.md rule + the `Stop` hook) cannot.

## Hard rules

1. **No claim without a citation.** Every finding cites a `file.swift:NN` (or command output) that contradicts the doc. If you can't cite it, it's not a finding.
2. **The code wins.** When a doc and the code disagree, the *doc* is wrong — propose the doc fix, never "change the code to match the doc."
3. **Verify contested claims yourself.** If a checker's finding conflicts with CLAUDE.md or another agent, open the cited file and confirm it before recording — never trust a single agent's claim. Stale CLAUDE.md facts are expected; flag them.
4. **Read source in full, not snippets**, when confirming a behavioral assertion.
5. **Don't fix without approval.** The report is the review artifact. Apply doc edits only after the user approves.

## Steps

### 1. Determine scope
- No args → all 12 docs (`README.md`, `01`–`10`, `features/README.md`).
- `--doc <path>` → just that doc.
- `--since <ref>` → only docs whose watch paths changed since `<ref>`. Map changed paths (`git diff --name-only <ref>...HEAD`) to docs using the "Architecture Docs" trigger list in `CLAUDE.md` and the index in `docs/architecture/README.md`. Include `README.md` / `10-separation-of-concerns.md` only when a *structural/module* change appears (they're cross-cutting syntheses).

### 2. Fan out one checker per in-scope doc (parallel)
Dispatch an adversarial fact-check subagent per doc (read-only). Each one:
- Reads its doc in full.
- For **every concrete checkable claim** — file/dir paths, type & symbol names, numeric/constant values, behavioral assertions — verifies it against the source.
- Returns ONLY evidence-backed discrepancies, each classified **ERROR** (factually wrong) or **GAP** (important omission — high bar; the docs are intentionally concise), formatted: `[ERROR|GAP] § "<quote>" — <what's wrong> — evidence: <file:NN> — fix: <correction>`. A clean doc returns `CLEAN`.

### 3. Reconcile
- For any finding that conflicts with CLAUDE.md or looks surprising, open the cited file and confirm it yourself.
- Drop false positives; keep only findings you can stand behind with a citation. Watch for agents that *invent* symbols — verify a symbol exists before recording a fix that references it.

### 4. Write the report
`.claude/plans/<YYYY-MM-DD>-doc-drift.md`, grouped by doc, each finding as `claim → cited code (file.swift:NN) → verdict (matches | stale | wrong) → fix`. End with a per-doc count and a TOTAL. If everything is clean, say so plainly.

### 5. Offer to apply
List the fixes and ask whether to apply them. Don't edit the docs until the user says go. If asked to apply, re-verify the corrected docs (a second pass) before declaring zero errors.

## Notes
- This is the **correctness** half of doc upkeep; the CLAUDE.md "Architecture Docs" rule is the **omission** half ("you forgot to touch the doc"). Both are needed.
- The methodology mirrors how these docs were originally verified: parallel per-doc checkers → reconcile contested claims against source → report → fix → re-verify. Two passes converge fast.
- Expect to surface stale facts in **CLAUDE.md** too (its Key Constants / Common Pitfalls cite `file.swift:NN`). Note them in the report; don't edit CLAUDE.md without approval.
