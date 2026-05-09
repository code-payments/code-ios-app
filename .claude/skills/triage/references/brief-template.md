# Triage brief template

The exact markdown structure to write to `.claude/plans/<YYYY-MM-DD>-bugsnag-<short_id>.md`.

Hard cap: ~200–300 words total. If a section runs longer, tighten it. Skim-readable in under a minute.

```markdown
# Bugsnag triage: <error_class>

**id:** `<short_id>…` · **URL:** <html_url>
**Triaged:** <YYYY-MM-DD> · **Status:** open · production
**Last 7d:** <events> events · <users> users · last seen <last_seen date>
**App version:** <event.app.version> (local: <MARKETING_VERSION>)
**Introduced in:** <introduced_in_release or "unknown">
**Experts consulted:** <comma-separated list, set after the expert routing step>

## ⚠️ Possible fix already in main

(Only present if `git log --since=<last_seen>` on the touched files returned commits. Omit the entire section otherwise.)

- `<short_sha>` — <commit subject> (touches `<file1>`, `<file2>`)

## Root cause

<2–4 sentences. Every claim cites file.swift:NN or quoted log.>

## Evidence

- `<file>:<line>` — <one-line quote>
- log `[<timestamp>] <level> <subsystem>` — <one-line quote from metaData.app_logs.recent_logs>
- nserror.userInfo — `<key>=<value>` (domain-specific runtime values, e.g. `quarks`, `mint`, `intentId`)
- breadcrumb `[<timestamp>] <type>` — <one-line quote>
- `git log` since first_seen — <one-line summary>

(omit any line that has no relevant content — Evidence shows what's there, not a fixed schema)

## Proposed direction

<one paragraph. The shape of the fix, not the steps.>

## Risk

<one or two sentences. What it touches, who feels the change.>

## Expert input

- **/simplify**: <one bullet, key insight or "no changes needed">
- (other experts only if triggered)

## Next step

If actioned: run `superpowers:writing-plans` against this file to expand into an implementation plan.
```

## Notes on each section

- **Header block** — everything above the first `##`. The reader should know whether to engage from this alone.
- **Possible fix already in main** — optional. Only included when commits exist on the touched files since `last_seen`. Tells the reader to verify whether those commits address the issue before taking further action — but the brief is still produced normally.
- **Root cause** — if the chain breaks, rename to "Leading hypothesis" and the Proposed direction becomes "Verification steps".
- **Evidence** — schema is illustrative; include only the rows you have. A row with no quote is rot.
- **Proposed direction** — the *shape* of the fix, not numbered steps. Numbered steps belong in the implementation plan that comes later.
- **Expert input** — only triggered experts get a bullet. No empty headings.
