# Reflections

A log of situations where things got out of hand. Each entry documents the issue, missteps, and how it was resolved.

- [2026-02-06 - Give Flow Currency Selection](2026-02-06-give-flow-currency-selection.md): Over-engineered a narrow bug fix by restructuring the presentation flow, causing a flash-then-dismiss race condition and breaking USDF-only users.
- [2026-02-10 - Deeplink .onChange Race Condition](2026-02-10-deeplink-onchange-race.md): Proposed adding a parallel `.task` modifier instead of using the simpler `.onChange(initial: true)` to handle a deeplink race condition.
- [2026-02-27 - Liquid Glass Button Gesture Fix](2026-02-27-liquid-glass-button-gesture-fix.md): Applied `.glassEffect(.interactive())` as a ViewModifier on Button instead of inside a ButtonStyle — gesture exclusivity swallowed taps.
- [2026-03-02 - SendCashOperation Verified State Regression](2026-03-02-send-cash-verified-state-regression.md): Path 2 (transfer) called `getVerifiedState()` from cache instead of reusing the state already resolved in Path 1 (message send). New currencies weren't in cache → `missingVerifiedState` → bill instantly disappeared.
