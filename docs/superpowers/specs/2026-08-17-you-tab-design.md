# Design: the "You" tab (Spec 1 of 2)

**Platform:** iOS (`code-ios-app`)
**Date:** 2026-08-17
**Figma:** [You tab](https://www.figma.com/design/Jxf2wD9QyfKaONbhHSdU0K/Flipcash?node-id=9217-114237&m=dev)
**Status:** approved design → ready for implementation plan

## Summary

Repurpose the existing `.tipCard` tab into a **"You"** landing page. Today the tab
shows a bare centered tip card with a hamburger that presents the Settings sheet.
The redesign turns it into a scrollable profile/settings surface:

- the tip card near the top, tappable to present **full screen**,
- a **"Share as a Link"** button,
- the settings list rows (`My Account`, `App Settings`, `Advanced`) inlined from
  the current Settings sheet, plus the conditional beta rows and version footer.

This is **Spec 1 of 2**. A follow-up spec (Spec 2) covers the Wallet 2×2 action
grid (Add Money / Withdraw / Discover Currencies / Create a Currency) and the
removal of the Discover promo card. Those are explicitly **out of scope** here.

## Scope decisions (confirmed)

| Decision | Choice |
|---|---|
| Full-screen card presentation | Reuse the scanned-tipcard **bill overlay**; bare card, drag to dismiss. No Share button on the overlay, no Send-a-Tip sheet. |
| Add Money / Withdraw on the You tab | **Absent.** They move to the Wallet grid in Spec 2. Withdraw is temporarily reachable only via Currency Info (accepted gap). |
| "No funds" empty-state text (hidden in Figma) | **Not implemented.** Keep only the current not-tippable → `TipCardSetupPrompt` gating. Noted as future. |
| Tab label | Relabel accessibility to **"You"**; keep the existing `NavTipCard` glyph. |
| Settings-row routing | **Dedicated `AppRouter.Stack.you`** for the tab's `NavigationStack`. |

## Current state (reference)

- **Tabs:** `HomeTab` enum — `scan`, `wallet`, `chat`, `tipCard` — rendered by
  `HomeTabView` (iOS 26 native `TabView` + Liquid Glass bar; legacy floating
  `HomeTabBar` pill below 26). Launch tab is `.wallet`.
  - `Flipcash/Core/Screens/Main/Home/HomeTab.swift`
  - `Flipcash/Core/Screens/Main/Home/HomeTabView.swift`
- **Tip card tab:** `TipCardTab` (private in `HomeTabView`) shows
  `TipcardScreen(isEmbedded: true)` for tippable profiles, else
  `TipCardSetupPrompt`. `TipcardScreen`'s embedded mode centers the card, taps to
  share, and has a hamburger that calls `router.present(.settings)`.
  - `Flipcash/Core/Screens/Main/Tips/TipcardScreen.swift`
  - `Flipcash/Core/Screens/Main/Tips/TipcardView.swift` (the renderable card)
- **Settings sheet:** `SettingsScreen` — an `Add Money` / `Withdraw Money` card
  row, then `My Account` (`settingsMyAccount`), `App Settings`
  (`settingsAppSettings`), `Advanced` (`settingsAdvancedFeatures`), conditional
  `Beta Features` / `Switch Accounts` behind `betaFlags.accessGranted`, and a
  version footer whose 10th tap toggles beta access.
  - `Flipcash/Core/Screens/Settings/SettingsScreen.swift`
- **Bill overlay (full-screen presenter):** `BillOverlayView` renders
  `session.billState.bill` at the app root over any tab, driven by
  `session.presentationState`. `TipFlow.present(_:)` shows a scanned card via
  `session.billState = BillState(bill: .tipcard(codeData:name:avatar:))` +
  `session.presentationState = .visible(.pop)`, then (after 750ms, gated on
  balance) raises the Send-a-Tip sheet. Drag-to-dismiss routes through
  `BillOverlayView.dismissBill` → for `.tipcard`, `tipFlow.cancel()`.
  - `Flipcash/Core/Screens/Main/Bill/BillOverlayView.swift`
  - `Flipcash/Core/Screens/Main/Bill/BillState.swift`
  - `Flipcash/Core/Screens/Main/Tips/TipFlow.swift`
- **Routing:** `AppRouter` keeps a `NavigationPath` per `Stack`; `push` lands on
  `topmostStack = presentedSheet?.stack ?? activeTabStack`. `HomeTabView`
  publishes `router.activeTabStack = selection.pushStack` and hides the tab bar
  when the active tab's stack is non-empty (`isTabBarHidden`) or while
  `session.isShowingBill`.
  - `Flipcash/Core/Navigation/AppRouter.swift`, `AppRouter+Stack.swift`,
    `AppRouter+Destination*.swift`

## Components to build / change

### 1. `HomeTab` — relabel

- `accessibilityLabel` for `.tipCard` → `"You"`. Keep `iconName = "NavTipCard"`.
- Add `pushStack` mapping for `.tipCard` → `.you` (new stack, see §4).
  (`HomeTabView`'s private `HomeTab.pushStack` extension currently returns `nil`
  for `.tipCard`.)

### 2. `YouScreen` (new) — replaces the embedded tip-card layout

A new `YouScreen` view composing:

- **Header tip card:** `TipcardView` (same payload/render as today:
  `TipCode.Payload(userID:)`, display name, avatar). Sized per Figma (card near
  the top rather than vertically centered). `.onTapGesture` → present full screen
  (§3). Reuses the existing avatar load + export/preview warming currently in
  `TipcardScreen` (move that logic into `YouScreen`, or a small shared helper).
- **"Share as a Link" button:** invokes the existing share path — a
  `TipCodeShareItem` (URL `.tipcard(for:)` + warmed `TipCodePreviewCache` image)
  through `ShareSheet.present`. This is the current `shareTipCard()` behavior,
  surfaced as an explicit button instead of a card tap.
- **Settings list:** `SettingsRow`s for `My Account` → `settingsMyAccount`,
  `App Settings` → `settingsAppSettings`, `Advanced` → `settingsAdvancedFeatures`;
  conditional `Beta Features` → `settingsBetaFlags` and `Switch Accounts` →
  `settingsAccountSelection` behind `betaFlags.accessGranted`. Pushes go on the
  `.you` stack (§4).
- **Version footer:** the `Version … • Build …` label with the 10-tap
  beta-access toggle, moved from `SettingsScreen`.
- **Not-tippable gate:** keep `TipCardSetupPrompt` (routes to Chat to add a name).
  `TipCardTab` continues to branch on `sessionContainer.session.profile?.isTippable`.

The `SettingsRow` component and the beta-toggle logic are lifted from
`SettingsScreen`. `SettingsScreen` itself (the sheet) is left intact for now but
is no longer presented from this tab (the hamburger is removed). Whether the
Settings sheet is still presented from anywhere else in the v2 UI is verified
during implementation; if nothing references it, that cleanup can be a follow-up
rather than part of this spec.

### 3. Full-screen tip card presentation

Add `Session.presentOwnTipcard(codeData:name:avatar:)` (or an equivalent small
coordinator method) that mirrors `TipFlow.present`'s card setup **without** the
submission/sheet machinery:

```swift
session.billState = BillState(bill: .tipcard(codeData: codeData, name: name, avatar: avatar))
session.presentationState = .visible(.pop)
```

- No `SendAmountViewModel`, no 750ms sheet scheduling, no balance gate.
- Dismissal reuses the overlay's existing drag-to-dismiss. `dismissBill` routes
  `.tipcard` → `tipFlow.cancel()`, which with no active submission falls through
  to `session.dismissCashBill(style: .slide)` — a safe, correct dismiss. We
  therefore **reuse `.tipcard`** rather than introduce a new bill case.
- `HomeTabView` already hides the tab bar while `session.isShowingBill`, so the
  bar clears during the presentation with no extra wiring.
- The card's resting offset is `restingTipcardOffset` (centered) because
  `tipFlow.isSheetPresented` is false for the own-card path.

### 4. Routing — dedicated `.you` stack

- Add `case you` to `AppRouter.Stack` (update the `sheet` mapping — `.you`
  returns `nil`, it is a tab stack not a sheet — and `description`).
- The You tab hosts `NavigationStack(path: $router[.you])` with
  `.appRouterDestinations()` so the settings sub-destinations render on it.
- `HomeTab.tipCard.pushStack = .you`; `HomeTabView` publishes
  `activeTabStack = .you` when the tab is selected, so `router.push(...)` from the
  rows lands on the You tab's stack and the tab bar hides on drill-in.
- The still-existing Settings sheet keeps `.settings`; the two never share a path.

## Data flow

1. User selects the You tab → `activeTabStack = .you`.
2. `TipCardTab` branches: tippable → `YouScreen`; else `TipCardSetupPrompt`.
3. `YouScreen` renders the card (payload from `sessionContainer.session.userID`, avatar
   loaded async) + Share button + settings rows + version footer.
4. Tap card → `Session.presentOwnTipcard(...)` → bill overlay pops the card full
   screen; drag down dismisses.
5. Tap "Share as a Link" → `ShareSheet.present(TipCodeShareItem(...))`.
6. Tap a settings row → `router.push(.settings*)` → pushes on `.you` → tab bar
   hides, sub-screen renders via `.appRouterDestinations()`.

## Error handling / edge cases

- **Avatar load failure:** card renders without the photo (existing behavior in
  `TipcardScreen.loadAvatar`); carry it over unchanged.
- **Not-tippable / no display name:** show `TipCardSetupPrompt`; the card and its
  tap/share are not shown.
- **Rapid double-tap on the card:** presenting an own-card when a bill is already
  showing should be guarded (no-op if `session.isShowingBill`), mirroring
  `TipFlow.begin`'s re-entrancy guards.
- **Beta rows / version toggle:** preserve the exact 10-tap threshold and
  `betaFlags.setAccessGranted` behavior from `SettingsScreen`.

## Testing

- Unit/snapshot: `YouScreen` in tippable vs. not-tippable states; with/without
  avatar; with/without `betaFlags.accessGranted` (beta rows shown/hidden).
- `Session.presentOwnTipcard` sets `billState.bill == .tipcard(...)` and
  `presentationState == .visible(.pop)`; dismissal clears `isShowingBill`.
- Routing: pushing `settingsMyAccount` while on the You tab lands on
  `router[.you]` and hides the tab bar; `router[.settings]` is untouched.
- Manual: iOS 26 (native tab bar) and ≤25 (legacy pill) — verify tab-bar hide on
  card present and on settings drill-in; verify Share sheet content (name + URL +
  preview image).

## Out of scope (Spec 2)

- Wallet 2×2 action grid (Add Money / Withdraw Money / Discover Currencies /
  Create a Currency) — Figma
  [`9217-114318`](https://www.figma.com/design/Jxf2wD9QyfKaONbhHSdU0K/Flipcash?node-id=9217-114318&m=dev).
- Relocating Withdraw into that grid.
- Removing the Discover promo card; Discover Currencies list "Option B" — Figma
  [`9217-116668`](https://www.figma.com/design/Jxf2wD9QyfKaONbhHSdU0K/Flipcash?node-id=9217-116668&m=dev).
