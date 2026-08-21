# UI test rewrite for the tab-bar UI

Shipping the tab-bar UI to everyone — first `BetaFlags.Option.newUI` → `.shipped`, then
the full flag teardown (see `2026-08-20-newui-flag-teardown.md`) — removed the v1 scanner
chrome that the XCUITest suite navigated through. The affected tests are
skipped via `BaseUITestCase.skipPendingTabBarRewrite(_:)` so the release can run; this
is the map for putting them back.

Grep `skipPendingTabBarRewrite` for the live list. The helper is deleted with the last
call site.

## What moved

| v1 affordance | v2 route |
|---|---|
| `ScanTopBar` Settings button (`app.buttons["Settings"]`) | You tab (`app.buttons["You"]`) → `YouScreen` settings list |
| `ScanBottomBar` Cash button (`app.buttons["Cash"]`) | no scanner give entry; per-currency **Give** on `CurrencyInfoScreen`, or the `flipcash://give` deeplink |
| `scan-wallet-button` | Wallet tab (`app.buttons["Wallet"]`) |
| `scan-tips-button` | Chat tab (`app.buttons["Chat"]`) — embedded, so no `navigationBars["Tips"]` Close button |
| `scan-discover-button` | Wallet tab → "Discover Currencies" tile (a push, not a sheet) |
| `discover-create-currency-card` promo | Wallet tab → "Create a Currency" tile — `CurrencyDiscoveryScreen.hidesPromo` hides the card |
| Settings "Add Money" / "Withdraw Money" rows | Wallet tab tiles of the same name |
| `CurrencyInfoFooter` Buy / Sell buttons | `CurrencyInfoContentV2` tiles: **Give / Convert / Withdraw** when held, **Get** when not |
| Sell flow (`CurrencySell*Screen`) | Convert flow (`ConvertAmountScreen` → `ConvertConfirmationScreen`), pushed onto the Wallet stack |

## Gotchas

- **The tab bar hides on push.** `HomeTabView.isTabBarHidden` is true when a card is
  expanded, a bill is showing, or the active tab's stack is non-empty. So
  `assertMainScreenReached()` (now the Wallet tab) only holds at a tab root — pop first.
- **The You tab gates on a tip profile.** `YouScreen` (and therefore the whole settings
  list) only renders when `session.profile?.isTippable == true`; otherwise the tab shows
  `TipCardSetupPrompt`. Fresh-account tests cannot reach Settings this way.
- **`GiveDiscoverGateRegressionTests` was deleted, not skipped.** USDF is giveable now,
  so `GiveCashGate.discoverCurrencies` is unreachable and the "No Community Currencies
  Yet" dialog never shows — there was no behaviour left to assert.
- **An owned currency has no Buy affordance.** `CurrencyInfoContentV2.actionTiles` shows
  Give / Convert / Withdraw when held and only Get when not, so
  `BuyWithCurrencyRegressionTests` and `BuyReservesRegressionTests` (both select the
  first *wallet* currency, i.e. a held one) need a new entry point, not a selector swap.
  Their `getButton` reference is a compile fix only.
- **`CurrencyInfoUIScreen.assertReached()` waits on `currency-info-back`**, the only
  element present in both the held and unheld layouts. Assert on a specific tile when
  the test knows which side of that split it is on.
- **`BaseUITestCase.navigateToGiveAmount()` still taps the v1 Cash button.** Its only
  callers are skipped; rewrite it against whichever give entry the tests should cover.

## Product gap worth confirming separately

Settings is reachable *only* from the You tab, which requires a tippable profile. An
account without one appears to have no route to Settings at all.
