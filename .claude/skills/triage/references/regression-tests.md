# Regression tests for crash fixes

Every crash fixed from Bugsnag (or similar) gets a dedicated regression test in
`FlipcashTests/Regressions/`. The fix session (not the triage run) writes it, and it lands in the
same branch as the fix.

## Conventions

- **One file per incident:** `Regression_{bugsnag_id}.swift` (full 24-char id)
- **Suite name includes the short ID:** `@Suite("Regression: {short_id} – {brief description}", .bug("{bugsnag_id}"))`
- **Reproduce the crash path**, not just the low-level fix. If the crash came through
  `EnterAmountCalculator`, test through `EnterAmountCalculator`.

```swift
// FlipcashTests/Regressions/Regression_698ef3b65e6cc4bb5554e13d.swift

@Suite("Regression: 698ef3b – Quarks comparison overflow for high-rate currencies")
struct Regression_698ef3b {

    @Test("CLP quarks comparison across 6 and 10 decimal precisions does not overflow")
    func quarksComparison_CLP_doesNotOverflow() { ... }
}
```

## Observe the test fail before implementing the fix

A test derived from the fix's own reasoning can pass for the wrong reason — the 6a4f895 → 6a522ee
pair shipped exactly this way: the first fix's test asserted diff *shape* and stayed green while
the changeset applier kept crashing in production. Run the new test against the unfixed code and
watch it fail at the crash layer; for an uncatchable `NSException`, the red state is the runner
aborting with the production crash signature — run that suite alone so the abort attributes
cleanly.

## UIKit collection-view traps (false greens)

- **Window-attach the controller.** `reload(using:)` short-circuits to `reloadData` off-window,
  so an unwindowed test never runs the batch path at all.
- **Push with `animated: true`** (the default) — the non-animated path also skips the diff.
- **Assert live cells** via `collectionView.cellForItem(at:)`. Re-invoking the data-source method
  re-dequeues against current data and always looks correct; only the on-screen cell can show a
  misconfigured row.
- **Assert content, not just counts.** A count-only assertion passes while every bubble renders
  another row's text.
