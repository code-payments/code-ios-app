# Bugsnag triage: Share send failed — `NoPeer()`

**id:** `6ace7ba…` · **URL:** https://app.bugsnag.com/1000710770-ontario-inc/flipcash-ios/errors/6ace7ba489c0031619d1c6c8
**Triaged:** 2026-10-27 · **Status:** open · production + development
**All time:** 7 events · 3 users · last seen 2026-10-28 (`--id` path, no 7d filter)
**App version:** 2026.10.4 (591), ShareExtension process (local: 2026.10.5)
**Introduced in:** 2026.10.3 (272)
**Experts consulted:** /simplify, swiftui-specialist, modernize-tests

## Leading hypothesis

Every share to a private group fails. `ShareModel.swift:299` builds `ChatKeyring` without `groupKey`. Private groups always encrypt (`E2eePolicy.swift:25`), so `groupSeal` throws `NoPeer` (`ChatKeyring.swift:156`). The app (`SessionAuthenticator.swift:771-779`) and the NSE (`ChatNotificationClient.swift:103-109`) both pass `groupKey`. The extension (`2a8c06886`) predates private groups (`08a9511cc`).

The only other throw site, `ChatKeyring.swift:128`, fires only for a DM whose members are all self, because `E2eePolicy.swift:33-34` encrypts a DM only when every member has a `userID`. The event can't tell the two sites apart.

## Evidence

- nserror `domain=…ChatKeyring.(unknown context).NoPeer`, `code=1`, `userInfo={}`; `process=share-extension`, frames unsymbolicated
- `ShareModel.swift:256` — `capture(error, reason: "Share send failed")`, no metadata
- Joined groups reach the share picker: `ShareChatSelection.swift:20`
- No app_logs; breadcrumbs cover only launch and foreground

## Proposed direction

First, confirm the hypothesis: share to a private group from the 2026.10.4 extension and expect "Couldn't send…" plus a new event. Then fix: add a keyring factory beside `ChatNotificationClient.swift:74` that wires `GroupKeyEnvelopes` through `FlipClient+Chat.swift:464,471`, use it at `ShareModel.swift:299`, and drop the `groupKey = nil` default (`ChatKeyring.swift:75`) so a site that omits it fails to compile. Report the chat type at `ShareModel.swift:256`. Members who joined by invite still hit retryable `GroupKeyUnavailable` until the app stores their envelope (`ChatNotificationClient.swift:99`).

Secondary: `NoPeer` is `private` (`ChatKeyring.swift:170`), so `canRetry` defaults to `true` and shows a connectivity message (`ShareModel.swift:351-368`).

## Verification

`FlipcashTests/Regressions/Regression_6ace7ba489c0031619d1c6c8.swift`, suite `"Regression: 6ace7ba – …", .bug("6ace7ba489c0031619d1c6c8")`. It must fail on the unfixed code first. A private group sealed through the extension's factory yields a seal (`try #require`), not `NoPeer`. Stub the factory's network closures as `ChatKeyringTests.swift:149` does. Don't hand-build a `ChatKeyring`; that test would pass without the fix.

## Risk

Small. Behavior changes only in the extension's send path. Removing the default changes every `ChatKeyring(` call site, including tests.

## Expert input

- **/simplify**: an altitude point. A required `groupKey` catches this whole class of bug at compile time, instead of one call site at a time.
- **swiftui-specialist**: no view-layer impact. The keyring stays inside the private `Session`, so no observed state is added.
- **modernize-tests**: the test goes in `FlipcashTests/Regressions/` with a `.bug` trait. The factory's network calls must be injectable.

## Next step

If actioned: run `superpowers:writing-plans` against this file, and load `karpathy-guidelines` before writing code. The fix must land with the regression test above, observed failing on the unfixed code first. See `references/regression-tests.md`.
