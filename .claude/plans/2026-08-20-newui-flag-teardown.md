# `BetaFlags.Option.newUI` teardown

The tab-bar UI shipped to everyone in #613 by flipping `newUI` to `.shipped`. This is the
follow-up that removes the flag itself, collapses every branch it gated, and deletes the
v1 surfaces stranded as a result. Mirrors the Android teardown (`code-android-app` #1290).

`BetaFlags` itself stays — `.vibrateOnScan` and `.enableCoinbase` still use it, and
`Availability.shipped` is kept as the mechanism for the next rollout.

## The two shells, collapsed to one

v1 was scanner-first: `ScanScreen` owned the chrome (`ScanTopBar`, `ScanBottomBar`), the
balance was a screen (`BalanceScreen`) presented as the `.balance` sheet, and Discover was
the `.discover` sheet. v2 is `HomeTabView` — Scan / Wallet / Chat / You — where the wallet
and the tips list are *tabs*, not sheets.

Deleted outright: `BalanceScreen`, `ScanTopBar`, `ScanBottomBar`, `CurrencyCreationPromoCard`,
`CurrencyInfoHeaderSection`, `CurrencyInfoFooter`, and the whole v1 sell flow
(`CurrencySellViewModel`, `CurrencySellAmountScreen`, `CurrencySellConfirmationScreen`,
`CurrencySellConfirmationViewModel`) — Convert replaced it.

Extracted rather than deleted, because v2 still needs them:
- `ExchangedBalance` — the balance model that lived inside `BalanceScreen`.
- `Home/BalanceHeaderButton` — the wallet's balance header.
- `Navigation/RootSheetHost` — the app-level sheet host `ScanScreen` used to embed, so
  `router.present(_:)` works from any tab rather than only from the scanner.

## Router: two sheets became tabs

`SheetPresentation` lost `.balance` and `.discover`. That has knock-on effects worth
knowing before touching `AppRouter`:

- `Stack.sheet` is now `nil` for `.balance` and `.you` (tab stacks) as well as for
  `.buy` / `.addMoney` / `.sendAmount` (nested-only, payload-bearing).
- `navigate(to:)` therefore has two branches. The tab branch is checked **first**, because
  a tab stack has no sheet to look up: it dismisses every sheet, sets the path, and parks
  `requestedTabStack` for `HomeTabView.selectRequestedTab()` to consume. The sheet branch
  handles the rest.
- Which branch a destination takes is decided by `Stack.isTabHosted`, a static fact on the
  stack — *not* a set registered at runtime by the view. An earlier revision had
  `HomeTabView.onAppear` publish `router.tabStacks`; a deep link arriving before that view
  appeared would then find the set empty, fall through to the sheet lookup, and be dropped
  on the floor (`.balance` has no sheet). `isTabHosted` must agree with `HomeTab.pushStack`
  — `AppRouterCrossStackTests.tabHostedStacks_matchHomeTabs()` pins the two together.
- `.tips` is **both**: the Chat tab hosts it, and `present(.tips)` still puts the same
  stack in a sheet from surfaces with no tab bar. The tab wins for `navigate(to:)`.
- Deep links follow: `flipcash://balance` → `.wallet` (bring the tab forward at its root),
  `flipcash://discover` → `.discoverCurrencies` (a push onto the wallet).
- `topmostStack` is `presentedSheet?.stack ?? activeTabStack`, so `push`/`pop` work in a
  tab with no sheet up. The "no sheet presented" warnings are now "no topmost stack".

## Currency Info

`CurrencyInfoScreen` collapsed onto `CurrencyInfoContentV2`. The v2 layout renders
**Give / Convert / Withdraw** for a held currency and only **Get** for one that isn't
held — so an owned token has no Buy affordance at all. Anything that navigated to Buy
from a wallet currency needs a new entry point.

## Test fallout

- Router fixtures: tests about *sheet* semantics swapped the removed `.balance`/`.discover`
  root for `.give` (or `.settings`/`.tips` where `.give` collided). Tests about *stack
  paths* kept `.balance` and host it via `router.activeTabStack = .balance`, which also
  exercises the `topmostStack` fallback.
- `navigate` can only reach three owning stacks now (`.balance`, `.settings`, `.tips`) and
  two of those are tab-hosted, so the only sheet↔sheet swap left is into `.settings`. The
  cross-stack suite was rewritten around that rather than renamed.
- The deleted sell suite's money math was ported to `ConvertConfirmationViewModelTests`
  (fee bps, native-proportional scaling, `UInt64` overflow, stale-pin refusal) and two
  converted scenarios in `Regression_native_amount_mismatch`.
- XCUITests: none. The suite's tab-bar rewrite landed separately in #659 and is
  recorded in `2026-08-20-ui-test-tab-bar-rewrite.md`; this branch rebased onto it and
  kept none of its own UI-test changes.

## Orphan sweep

After the deletions, a HEAD-vs-worktree reference-count diff found exactly three
symbols whose last consumer was v1 code:

| Symbol | Was used by | Disposition |
|---|---|---|
| `Session.canUseTips` | `ScanScreen`'s bottom bar | deleted (body was `true` — Tips shipped out of beta) |
| `Image.Symbol.hamburger` | `ScanTopBar` | deleted, along with `UI.xcassets/icons/hamburger.imageset` |
| `Analytics.TokenInfoEvent.openedFromWallet` | `BalanceScreen` | **kept and rewired** — see below |

`openedFromWallet` marks the wallet → token-info funnel step, which the tab-bar
shell stopped emitting because the v2 wallet expands the card in place rather
than pushing a screen. Rather than lose the signal with v1, `WalletScreen`
now fires it from `openCard`. `openedFromDeeplink` had the same gap (dead since
before this change), so `openCardImmediately` — reached only from
`DeepLinkController`'s `requestedCardMint` — now fires that one.
