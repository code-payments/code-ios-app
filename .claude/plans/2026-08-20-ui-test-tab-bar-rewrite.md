# UI test rewrite for the tab-bar UI

Shipping the tab-bar UI to everyone (`BetaFlags.Option.newUI` → `.shipped`) removed the
v1 scanner chrome that the XCUITest suite navigated through. The affected tests are
skipped via `BaseUITestCase.skipPendingTabBarRewrite(_:)` so the release can run; this
is the map for putting them back.

Grep `skipPendingTabBarRewrite` for the live list. The helper is deleted with the last
call site.

## What moved

| v1 affordance | v2 route |
|---|---|
| `ScanTopBar` Settings button (`app.buttons["Settings"]`) | You tab (`app.buttons["You"]`) → `YouScreen` settings list ("My Account", "Advanced"); **Log Out is under Advanced** |
| `ScanBottomBar` Cash button (`app.buttons["Cash"]`) | no scanner give entry; per-currency **Give** on `CurrencyInfoScreen`, or the `flipcash://give` deeplink |
| `scan-wallet-button` | Wallet tab (`app.buttons["Wallet"]`) |
| `scan-tips-button` | Chat tab (`app.buttons["Chat"]`) — embedded, so no `navigationBars["Tips"]` Close button |
| `scan-discover-button` | Wallet tab → "Discover Currencies" tile (a push, not a sheet) |
| `discover-create-currency-card` promo | Wallet tab → "Create a Currency" tile — `CurrencyDiscoveryScreen.hidesPromo` hides the card |
| Settings "Add Money" / "Withdraw Money" rows | Wallet tab tiles of the same name |
| `CurrencyInfoScreen` "Buy" / "Sell" / "Give" footer | `CurrencyInfoContentV2` action tiles — **Give / Convert / Withdraw** for a currency you hold, **Get** for one you don't. No Buy, no Sell. |

## Gotchas

- **The tab bar hides on push.** `HomeTabView.isTabBarHidden` is true when a card is
  expanded, a bill is showing, or the active tab's stack is non-empty. So
  `assertMainScreenReached()` (now the Wallet tab) only holds at a tab root — pop first.
- **The You tab's settings rows sit below the fold.** They render under the tip card, so
  scroll them into view (`scrollUpToAndTap(_:in:)`) rather than tapping blind.
- **`GiveDiscoverGateRegressionTests` tests behavior that no longer exists.** USDF is
  giveable now (`BetaFlags.allowsDollarsGive`), so `GiveCashGate.discoverCurrencies` is
  unreachable and the "No Community Currencies Yet" dialog never shows. Delete the test
  with the phase-2 teardown rather than rewriting it.
- **`BaseUITestCase.navigateToGiveAmount()` still taps the v1 Cash button.** Its only
  callers are skipped; rewrite it against whichever give entry the tests should cover.
- **A wallet card opens `CurrencyInfoScreen` as an overlay, not a push.** `TokenCardStack`
  reports the tap through `onCardTap`; the wallet lifts the page over the deck with a
  close box instead of a back chevron, so there is no `navigationBars` entry to wait on.
- **The v1 buy/sell entries are gone from an owned currency.** `CurrencyInfoContentV2`
  gates its tiles on `isOwned` (balance has displayable value), and the owned branch is
  Give/Convert/Withdraw. Buying more of a currency you already hold has no entry point
  there, and buy pushes `.buyCurrency(mint)` onto the stack rather than presenting the
  `.buy` nested sheet the reserves test asserts. Deciding what the v2 equivalents should
  assert is a product question, not a selector swap — `BuyReservesRegressionTests`,
  `BuyWithCurrencyRegressionTests` and `CurrencySellRegressionTests` are skipped on that.

## Rewritten so far

- `LoginSmokeTests.testRelogin_viaAccountSelection` — You tab → Advanced → Log Out.
- `BuyApplePayRegressionTests`, `BuyDepositRegressionTests`, `BuyPhantomRegressionTests`
  — enter through the Wallet tab's `wallet-tile-add-money` tile. The picker's heading is
  **"Add Money With"** in v2, not "Select Method", and the debit-card row runs the
  verified-contact gate *before* "Amount to Add".
- `WalletUsdfRowRegressionTests` — the v2 deck's cards carry `currency-row` /
  `currency-row-usdf`, so the wallet page object matches again.
