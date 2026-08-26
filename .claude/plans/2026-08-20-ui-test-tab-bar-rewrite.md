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
| `CurrencyInfoScreen` "Transaction History" button | the **"Recent"** section header (`RecentActivitySection.onShowAll`); the rows under it are a non-interactive preview |
| `CurrencyInfoScreen` "Buy" / "Sell" / "Give" footer | `CurrencyInfoContentV2` action tiles — **Give / Convert / Withdraw** for a currency you hold, **Get** for one you don't. No Buy, no Sell. |
| Buy paying with reserves / Sell to Dollars | **Convert**, from either end. Open the balance you are paying *from* and convert to the one you want: token → Dollars replaces Sell, Dollars → token replaces buy-with-reserves, token → token replaces buy-with-currency. |

## Gotchas

- **The tab bar hides on push.** `HomeTabView.isTabBarHidden` is true when a card is
  expanded, a bill is showing, or the active tab's stack is non-empty. So
  `assertMainScreenReached()` (now the Wallet tab) only holds at a tab root — pop first.
- **The You tab's settings rows sit below the fold.** They render under the tip card, so
  scroll them into view (`scrollUpToAndTap(_:in:)`) rather than tapping blind.
- **`GiveCashGate` has no v2 entry from a tab root.** `ScanBottomBar` — the only caller
  that gated a *give* — renders under `if !isEmbedded`, and the Scan tab embeds
  `ScanScreen`. The gate still fires from a chat's Send Cash (`ConversationScreen`),
  `TipFlow`, and the give deeplink, none of which a fresh empty account can reach. So
  both dialog regressions built on the Cash button lose their subject:
  `GiveDiscoverGateRegressionTests` doubly so, since USDF is giveable now
  (`BetaFlags.allowsDollarsGive`) and `GiveCashGate.discoverCurrencies` is unreachable
  either way. Deleted. `GiveRegressionTests` (the "No Balance Yet" gate) is the same
  shape and stays skipped pending the same call.
- **Per-token history moved into the "Recent" header.** `CurrencyInfoContentV2` has no
  "Transaction History" button; the header button is the only way in, and it sits below
  the hero card and the action tiles, so it needs scrolling into view.
- **The Access Key row is on Advanced, not My Account.** `SettingsMyAccountScreen` says
  so in its own header doc: it keeps Access Key, Log Out and Delete Account off itself,
  and holds only Change Display Name, Blocked, and the beta-gated Switch Accounts.
- **The Chat tab is chats only — it is not a door into profile creation.**
  `TipsScreen(isEmbedded: true)` renders `TipConversationsScreen` unconditionally, so
  `TipsIntroScreen` and its `start-receiving-tips-button` never appear in v2. The v2 door
  is the You tab's `you-start-receiving-tips-button`, which pushes `.changeDisplayName`
  → `ProfileNameScreen(completion: .back)`: name only, returning to the You tab.
- **The profile photo step is dead in the app, not just in v2.** `ProfileNameScreen`'s
  `.tipcard` completion pushes straight past it — "the card omits the profile photo" —
  so `.profilePhoto` has no caller at all. Any rewrite drops `profile-photo-picker` and
  `profile-photo-next-button` rather than re-routing to them.
- **A wallet card opens `CurrencyInfoScreen` as an overlay, not a push.** `TokenCardStack`
  reports the tap through `onCardTap`; the wallet lifts the page over the deck with a
  close box instead of a back chevron, so there is no `navigationBars` entry to wait on.
- **The v1 buy/sell entries are gone from an owned currency.** `CurrencyInfoContentV2`
  gates its tiles on `isOwned` (balance has displayable value), and the owned branch is
  Give/Convert/Withdraw. The replacement for both is **Convert**, entered from the
  balance you are paying *from* rather than the one you are acquiring — so a test buys
  more of a currency it already holds by opening Dollars and converting into it.
- **Convert only offers balances you already hold.** `ConvertAmountViewModel.destinationOptions`
  is `session.balances(for:)` minus the source, so convert cannot acquire a currency the
  account has never held — that is what **Get** (`.buyCurrency(mint)`, on an unheld
  currency) is for. The defaults matter for tests: a non-Dollars source defaults to
  Dollars, and a Dollars source defaults to the largest other holding, so only a
  token→token convert has to open the picker.
- **A finished convert lands on the Wallet, not back on the currency.**
  `ConvertFlowDestinationView` gives the processing screen a `dismissParentContainer`
  that calls `popToRoot()` + `dismissExpandedCard()`. Assert the Wallet root after OK.
- **Convert is pushed, so the v1 nested-sheet dismissal regressions can't recur.**
  `BuyReservesRegressionTests` swiped down on the processing screen to prove the `.buy`
  sheet survived; there is no sheet in the convert stack, so that assertion was dropped
  rather than ported.

## Rewritten so far

- `LoginSmokeTests.testRelogin_viaAccountSelection` — You tab → Advanced → Log Out.
- `BuyApplePayRegressionTests`, `BuyDepositRegressionTests`, `BuyPhantomRegressionTests`
  — enter through the Wallet tab's `wallet-tile-add-money` tile. The picker's heading is
  **"Add Money With"** in v2, not "Select Method", and the debit-card row runs the
  verified-contact gate *before* "Amount to Add".
- `WalletUsdfRowRegressionTests` — the v2 deck's cards carry `currency-row` /
  `currency-row-usdf`, so the wallet page object matches again.
- The You-tab settings group — `AccessKeyBackupSmokeTests` (×3), `BlockedUsersSmokeTests`,
  `ApplicationLogsRegressionTests` — enters through the You tab and scrolls to the row.
  Access Key and Application Logs are on **Advanced**; Blocked is on **My Account**.
  `SettingsUIScreen` lost `addMoneyButton` / `withdrawMoneyButton` with the rows.
- The wallet money-tile group — `WithdrawSmokeTests`,
  `WithdrawPickerEmptyRegressionTests`, `DepositSmokeTests` (×2) — enters through
  `wallet-tile-withdraw-money` / `wallet-tile-add-money` instead of the Settings rows.
- `GiveSmokeTests` and `CashLinkRegressionTests` — `navigateToGiveAmount()` now goes
  Wallet → first currency card → its **Give** tile. The keypad pops itself as the bill
  appears (`GiveScreen.onBillPresented`, when `isPushed`), so both flows end on
  `CurrencyInfoScreen` rather than a tab root — the cash link reaches its history from
  there without a second trip through the wallet.
- The three buy/sell tests, rewritten as the convert routes that replaced them and
  renamed for what they now exercise: `CurrencySellRegressionTests` →
  `ConvertToDollarsRegressionTests`, `BuyReservesRegressionTests` →
  `ConvertFromDollarsRegressionTests`, `BuyWithCurrencyRegressionTests` →
  `ConvertBetweenTokensRegressionTests`. `CurrencyPickerSheet` rows gained
  `currency-picker-row` / `currency-picker-row-usdf`; `SellConfirmationScreen` went with
  the v1 sell sheet.
