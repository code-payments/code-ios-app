# Design implementation notes: iOS

How the shared design standard maps to this codebase. The rules themselves live in the
`flipcash-design` plugin (`docs/design-standard.md`, `docs/design-decisions.md`, `docs/lenses/`);
this file keeps only the SwiftUI side: the token, modifier or component for each rule, the file
each rule cites as evidence, the code patterns to flag, and the commands the plugin's agents run
here. Section and rule numbers match the plugin's. Install the plugin as `CLAUDE.md` describes.

Paths below: `UI/` is `FlipcashUI/Sources/FlipcashUI/`, `Screens/` is `Flipcash/Core/Screens/`.

## Design standard

The standard's sections, mapped to the iOS code.

### What Flipcash is

- The amount rolls with `.contentTransition(.numericText())`.
- `FontBook` maps the tokens' bold to Semibold, medium to Medium, the rest to Regular. The Semibold text tokens are `appTextLarge`, `appTextMedium`, `appTextSmall`; the Medium one is `appTextMessage`; Regular is `appTextBody`. The one true Bold is `ShellTabTitle.swift`.

### Principles

- A new component lives in `FlipcashUI` with a `///` contract doc and a `#Preview`.
- Tokens come from `Colors.swift` (colour), `AppFonts.swift` (type) and `Metrics.swift` (sizes).

### Materials: where each lives

| Material | File | Names |
|---|---|---|
| Colour tokens | `FlipcashUI/Sources/FlipcashUI/Theme/Colors.swift` | 23 semantic tokens plus `Color.Sentiment`. The unnamed washes are `Color.white` (106 sites) and `.white.opacity` (66). |
| Per-person colour | `Theme/ComplementaryPalette.swift` | |
| Type tokens | `Theme/AppFonts.swift`, `Theme/FontBook.swift` | `appDisplay*`, `appTitle*`, `appText*`, `appBarButton`, `appKeyboard` |
| Metrics | `FlipcashUI/Sources/FlipcashUI/Metrics.swift` | `buttonHeight` 54, `buttonHeightThin` 44, `buttonGap` 12, `buttonRadius` 6, `boxRadius` 12, `buttonPadding` 20, `buttonLineWidth` 1; `buttonPressScale` 0.95, `buttonPressDim` 0.7, `buttonPressAnimation`. `buttonPaddingUnderTextLink` 32 lives in `Views/ButtonStyles/BottomEdgePadding.swift`. |
| Motion | `FlipcashUI/Sources/FlipcashUI/Chat/ChatMotion.swift` | One `ChatSpring(duration:bounce:)` vends the SwiftUI, UIKit and Core Animation forms; every preset carries its intent in a `///` comment. `Transitions/Animations.swift` is legacy. |
| Haptics | `FlipcashUI/Sources/FlipcashUI/Haptics/Haptics.swift` | |
| Symbols and assets | `Theme/Image+Symbols.swift` | SF Symbols through `Image.system`, the brand set through `Image.asset`. |
| Components | `.claude/docs/design/components.md` | |

### Patterns: the names

- **Presentation.** The shared dialog slot is `session.dialogItem`; the toast controller is `ToastController`. "Never a nested navigation stack" means never a nested `NavigationStack`. The two surviving overlays are the bill's `Session.toast` and the conversation's reaction toast.
- **Buttons.** Styles are `.filled`, `.filledCompact`, `.subtle`, `.subtleCompact`, `.textLink`, `.icon`. The gap is `Metrics.buttonGap`. Bottom actions use `.bottomEdgePadding()`; a screen that ends in a text link uses `.bottomEdgePaddingUnderTextLink()`. Progress is `ButtonStateLabel` (`.loading → .success`). The press is `ButtonPress` (`.pressable` for a label that draws its own capsule). The no-feedback style is `.buttonStyle(.plain)` on a tappable card, row or tile (44 sites).
- **Rows.** `Row(accessory:)` in a stack, `SettingsRow` in Settings; inside a `List`, `.listRowInsets` at 20 and `.listRowSeparatorTint(.rowSeparator)`; a conversation row is `RecipientRowScaffold`.
- **Tiles and cards.** Copy `TipCardActionButton` for a tile and `TutorialChecklistCard` for a card.
- **Amount entry.** `KeyPadView` into `AmountField` inside `EnterAmountView`, parsed only through `AmountValidator`.
- **Confirmation.** The swipe-to-confirm control is `SwipeControl`.
- **Glass.** `glassBackground`, `capsuleGlassBackground`, `GlassContainer` and `liquidGlassButtonStyle`.
- **Sheets.** Root and nested sheets go through `AppRouter`; a local picker sheet is a `NavigationStack` with a plain `CloseButton`; a short choice is a `PartialSheet`.
- **Empty states.** The model is `NoChatsView` in `TipConversationsScreen.swift`; a search miss uses `SearchResultsUnavailableView`.
- **Loading and failure.** The whole-surface loader is `Loadable`; the in-control spinner is a `ProgressView` tinted `.textSecondary`.

### Motion vocabulary

- The named presets are `ChatMotion`'s.
- A changed `ChatMotion` spring updates its row in `FlipcashTests/Chat/ChatMotionTests.swift` and its `///` intent.
- The chat replay is `--motion-sandbox`.

### Load-bearing walls

Money, amounts and affordability: `Session.hasSufficientFunds(for:)`, `TokenAmount`, `FiatAmount`, `ExchangedFiat`. Navigation structure: `AppRouter`. The cash bill chain: `showCashBill`, `SendCashOperation`. Configuration and tooling: `Configurations/`, `Scripts/`, `.github/`, `project.pbxproj`, entitlements.

## Decision log: the iOS files

The plugin's `docs/design-decisions.md` keeps each call and its why; these are the iOS files each one touched.

| Date | Decision | iOS files |
|---|---|---|
| 2026-11-19 | Every button is a capsule | `Metrics.swift` (`buttonHeight`, `buttonHeightThin`, `buttonRadius`), `TrayMetrics.swift` (`actionHeight`), `FilledButtonStyle`, `SubtleButtonStyle`, `IconButtonStyle`, `DialogButton`, `AmountPresetButton.swift`; the tray's red capsule is `TrayAction` `.destructive` |
| 2026-11-19 | One secondary button | `SubtleButtonStyle.swift`, `FilledButtonStyle.swift`, `Colors.swift` (`Color.actionSecondary`) |
| 2026-11-19 | Help and escape links are text links | `TextLinkButtonStyle.swift`, `LoginScreen.swift`, `AccessKeyScreen.swift`, `TipCardDownloadSheet.swift` |
| 2026-11-19 | One press | `ButtonPress.swift` (`.pressable`), `PressButtonStyle.swift`, `Metrics.swift` (`buttonPressAnimation`), `TrayMetrics.swift` |
| 2026-11-19 | Two buttons 12 pt apart | `Metrics.swift` (`buttonGap`), `TrayMetrics.swift` (`actionGap`), `Dialog.swift` |
| 2026-11-19 | Button title on one line at large text | `FilledButtonStyle.swift`, `SubtleButtonStyle.swift` |
| 2026-11-19 | A status is a text line | `ChatProfileScreen.swift`, `PrivateGroupCopy.swift`, `GroupInviteScreen.swift` |
| 2026-11-19 | A screen keeps its primary | `NotificationStatusScreen.swift` |
| 2026-11-19 | Leave ends the scroll | `ChatProfileScreen.swift`, `PublicGroupProfileView.swift` |
| 2026-10-27 | A tray is one view on one spring | One SwiftUI view on `TrayMotion.resize`, inside a system sheet made invisible with `.presentationBackground(.clear)` plus a clear detent `backgroundEffect` (iOS 26.1+), glass drawn with `.glassEffect`. `TrayMotion.swift` |
| 2026-10-26 | Trays through the system sheet | A UIKit seam, `animateChanges { invalidateDetents() }`. `TraySheetDriver.swift` |
| 2026-10-14 | System fonts | `AppFonts.swift`, `FontBook.swift`; the open rename is `.bold` → `.demi` in `AppFonts` |
| 2026-10-05 | iOS 18 floor | `GlassContainer`, `liquidGlassButtonStyle`, the glass helpers, corner shapes |
| 2026-10-05 | Where the design docs live | the shared docs moved to the `flipcash-design` plugin; this repo keeps `components.md` and this file |
| 2026-08-26 | Chat motion | `ChatSpring(duration:bounce:)` in `ChatMotion.swift`, pinned by `ChatMotionTests` |
| ◇ open | Caption token and semibold mapping | `appTextCaption`, `.semibold` |
| ◇ open | One sheet title bar | `CloseButton` (plain in a toolbar, glass in an inline header) |
| ◇ open | One tile recipe | `.card(icon:)` and `LargeButton` are the dead ones; `components.md` Gaps |
| ◇ open | White-alpha washes | `Color.white`, `.white.opacity` |
| ◇ open | Tabular digits | `.monospacedDigit()`, `.contentTransition(.numericText())` |
| ◇ open | Display Field | `appDisplayMedium`, `.focused` |
| ◇ open | Reduce-Motion helper | `accessibilityReduceMotion` |
| ◇ open | Toast placement | `.claude/docs/architecture.md` |
| ◇ open | UIKit corner style | SwiftUI's `RoundedRectangle(cornerRadius:)`, `UnevenRoundedRectangle` and `.rect(cornerRadius:)` default to `.continuous`, and no code passes `.circular`; the UIKit sites are `layer.cornerRadius`, the fix is `cornerCurve = .continuous` |

## Layout and hierarchy lens

### Rules: the code and the evidence

1. `.buttonStyle(.filled)` is the primary; others are `.subtle`, `.textLink`, `.filled05`, `.icon(_:)`. `Screens/Settings/Withdraw/WithdrawIntroScreen.swift:38-39`; the ladder is `UI/Views/ButtonStyles/FilledButtonStyle.swift:82-113`, `SubtleButtonStyle.swift:64-71` and `TextLinkButtonStyle.swift`.
2. Other text at `.appDisplaySmall` (24) or below. `Screens/Main/Home/BalanceHeaderButton.swift:30` (`.appDisplayLarge`, 55).
3. Section headings are `.appTextHeading` in `.textSecondary`. `Screens/Settings/SettingsAdvancedBetaFeaturesScreen.swift:124-134`.
4. `Screens/Settings/SettingsMyAccountScreen.swift:43-71` (icon, title, separator; nothing else).
5. A FlipcashUI component that mirrors an Android spec value states that in its `///` doc; otherwise the rhythm binds components too. `Screens/Main/Home/WalletScreen.swift:549,557,582,590`.
6. Space siblings with the stack's `spacing:`, never with `.padding(.bottom, n)` on each child. `Screens/Main/Home/WalletScreen.swift:589-611`.
7. A `Spacer()` above the actions, 20 pt at the sides and top, and `.bottomEdgePadding()` for the bottom; a screen that ends in a `.textLink` takes `.bottomEdgePaddingUnderTextLink()`. Two buttons sit `Metrics.buttonGap` (12) apart. The 2026-11-19 revision replaced `.safeAreaInset` plus 20 pt bottom padding. `Screens/Main/DownloadAppScreen.swift:46-53`; `Screens/Settings/Withdraw/WithdrawIntroScreen.swift:36-42`; `Screens/Onboarding/NotificationPermissionScreen.swift:52-57`.
8. `Screens/Main/Home/WalletScreen.swift:129-140`.
9. `Screens/Settings/SettingsMyAccountScreen.swift:43`; `Screens/Settings/Withdraw/WithdrawIntroScreen.swift:31-34`.
10. `Screens/Settings/SettingsRow.swift:38`.
11. Wrapping labels take `.fixedSize(horizontal: false, vertical: true)`; a pushing `Spacer` takes a `minLength`. `Screens/Main/Home/WalletScreen.swift:632-637`.
12. A card is `.backgroundRow`; the ring is `.rowSeparator` at 1 pt via `strokeBorder`. `Screens/Main/Home/TokenCardView.swift:98-101`; `Flipcash/Views/TutorialChecklistCard.swift:59-60`.
13. No `.shadow(` on a card, row, tile or sheet; the one lift is `UI/Chat/BubbleBackgroundView.swift:222-240`.
14. `vSeparator` in `.rowSeparator`. `UI/Modifiers/Separator.swift:68-73`; `UI/Views/Containers/Row.swift:52`.
15. `Capsule` for buttons; `Metrics.buttonRadius` (6), `Metrics.boxRadius` (12). `UI/Metrics.swift:23-24`; `UI/Chat/BubbleBackgroundView.swift:31-32,279-287`.
16. SwiftUI's `RoundedRectangle(cornerRadius:)`, `UnevenRoundedRectangle` and `.rect(cornerRadius:)` default to `.continuous` (iOS SDK interface), so `style: .continuous` is optional and `style: .circular` is a finding (none today). In UIKit, `layer.cornerRadius` draws a circular corner unless `layer.cornerCurve = .continuous` sits beside it. `Screens/Main/Home/TokenCardView.swift:90-99`; `FlipcashUI/Chat/BubbleBackgroundView.swift:22`.
17. `UI/Metrics.swift:23-24`.
18. Glass goes through `glassBackground(cornerRadius:)`, `capsuleGlassBackground()`, or `liquidGlassButtonStyle(shape:)`, grouped in a `GlassContainer` when two pieces sit together. `UI/Views/Containers/GlassBackground.swift:12-18`; `Screens/Main/Home/WalletScreen.swift:815-823`.
19. The fallback is `.ultraThinMaterial` in the same shape, `.thinMaterial` for a clear sheet. `UI/Views/Containers/GlassBackground.swift:16,44`; `UI/Views/Containers/PartialSheet.swift:55-66`.
20. Partial-height sheets use `PartialSheet`, whose fill is `.backgroundSecondary`. `UI/Views/Containers/PartialSheet.swift:20`.
21. The house press is `ButtonPress`: 0.95 on `Metrics.buttonPressAnimation`, 0.7 under Reduce Motion. `UI/Views/ButtonStyles/ButtonPress.swift:24-28`; `UI/Views/ButtonStyles/FilledButtonStyle.swift:68`; `UI/Views/ButtonStyles/SubtleButtonStyle.swift:50`.
22. `Metrics.buttonHeight` (54) and `Metrics.buttonHeightThin` (44). `UI/Views/ButtonStyles/FilledButtonStyle.swift:57`.
23. `.frame(minHeight: 44)` and a `.contentShape(...)`. `Screens/Main/Home/WalletScreen.swift:342-345`.
24. A headline in `.appTextLarge`, via `ContentUnavailableView` or `SearchResultsUnavailableView`; a `Spacer()`-only branch is the failure. `UI/Views/SearchResultsUnavailableView.swift:22-36`; `Screens/Settings/SettingsAdvancedBetaFeaturesScreen.swift:39-47`.
25. Skeleton rows use `.redacted(reason: .placeholder)`. `Screens/Main/Currency Discovery/CurrencyDiscoverySkeletonRow.swift:47`; `Screens/Main/Home/WalletScreen.swift:146-149`.
26. `.monospacedDigit()` on a figure that updates in place, `.contentTransition(.numericText())` on one that animates. `Screens/Main/Currency Discovery/CurrencyDiscoveryRow.swift:22`; `Screens/Main/Home/BalanceHeaderButton.swift:32`.
27. `Image.system(_:)` with a `SystemSymbol` case or `Image.asset(_:)` with an `Asset` case, never `Image(systemName: "...")` with a string and never an emoji in a `Text`. `UI/Theme/Image+Symbols.swift:13-19`.
28. `Screens/Settings/SettingsMyAccountScreen.swift:18-22`; `Screens/Main/Home/WalletScreen.swift:592-594`.
29. `Screens/Main/Home/WalletScreen.swift:649-662`.
30. `Font.app*` tokens; `.font(.system(` on a `Text` and `.default(size:)` with a literal are the failures. `UI/Theme/AppFonts.swift:12-37`; `UI/Theme/FontBook.swift:108-110`.
31. `Screens/Main/Home/WalletScreen.swift:496-558`.

### Specifics: the code

- Theme: `UI/Theme/Colors.swift:14-41`.
- Rhythm as practiced in `Screens/`: `.padding(20)` x48, 12 x7, 16 x6, 24 x5; edge padding 20 x116, 12 x34, 8 x26, 40 x21, 16 x19; `spacing:` 12 x38, 8 x31, 4 x21, 20 x15, 16 x12. The stragglers: 10 x22, 15 x13, then 14, 28, 30.
- Radii: buttons never read `Metrics.buttonRadius`. `Metrics.buttonRadius` 6 (40 uses, counted before the 2026-11-19 capsule change) and `Metrics.boxRadius` 12 (5 uses: `TokenCardView`, `ConversationGatePanel`, `CardButtonStyle`); literal 6 ×14 and 12 ×5 across screens and `UI/`. 42 call sites pass `style: .continuous`. `UI/Metrics.swift:23-24`.
- Heights: `Metrics.buttonHeight` 54, `buttonHeightThin` 44, `buttonGap` 12, `buttonPadding` 20, `buttonLineWidth` 1; `buttonPaddingUnderTextLink` 32. `UI/Metrics.swift:18-26`; `UI/Views/ButtonStyles/BottomEdgePadding.swift`.
- Button ladder: `.filled`, `.subtle` (`Color.actionSecondary`), `.textLink`, `.filled05`, `.icon(_:)`, `.card(icon:)`, `.filledCompact`, `.subtleCompact`. `UI/Views/ButtonStyles/FilledButtonStyle.swift:82-113`; `UI/Views/ButtonStyles/ButtonPress.swift`.
- Screen skeleton: `Background(color: .backgroundMain)` > `ScrollView(showsIndicators: false)` > `VStack(spacing: 0)` > `.padding(.horizontal, 20)`. `Screens/Settings/SettingsMyAccountScreen.swift:31-36`; `Screens/Main/Home/WalletScreen.swift:497-557`.
- Rows: `Row(insets:)` lays an `HStack(spacing: 12)` over a bottom `rowSeparator`; settings rows use `EdgeInsets(top: 25, bottom: 25)`, a 45 pt icon slot, and `.appDisplayXS` titles. `UI/Views/Containers/Row.swift:30-53`; `Screens/Settings/SettingsMyAccountScreen.swift:28,72`.
- Cards: `.backgroundRow` fill, `Metrics.buttonRadius` continuous, `.padding(16)` inside; the bill card is `boxRadius`; `BorderedContainer` groups inputs. `Flipcash/Views/TutorialChecklistCard.swift:50-60`; `UI/Views/Containers/BorderedContainer.swift:28-34`.
- Glass: `glassBackground(cornerRadius:)`, `glassBackground(cornerRadius:tint:)`, `capsuleGlassBackground()`, `glassFieldBackground(cornerRadius:)` (text fields; keep it out of a `GlassContainer`), `GlassContainer(spacing:)`, `liquidGlassButtonStyle(shape:)`, `prominentButtonStyle()`. `.glassEffect(.interactive())` goes inside a `ButtonStyle`, never as a modifier on a `Button` (reflection 2026-02-27). `UI/Views/Containers/GlassBackground.swift:8-63`; `UI/Views/ButtonStyles/LiquidGlassCompatibleButtonStyle.swift:15-89`.
- Sheets: `PartialSheet`; `.clear` falls back to `.thinMaterial` on iOS 18. `UI/Views/Containers/PartialSheet.swift:11-47`.
- Hairlines: `vSeparator(color:position:weight:)`; `.regular` is 1 px (`1 / displayScale`), `.medium` is 1 pt. `UI/Modifiers/Separator.swift:64-74`.
- Empty and loading: `SearchResultsUnavailableView`, a themed `ContentUnavailableView`, `CurrencyDiscoverySkeletonRow`, `Loadable`; toasts go through `FloatingToast` and `ToastController`.
- Icons: the `SystemSymbol` and `Asset` enums are the inventory; Android-matched assets (`profilePicture`, `myAccount`, `advanced`, `deposit`, `withdraw`) exist where SF Symbols has no glyph. `UI/Theme/Image+Symbols.swift:46,104`.
- Money: `BalanceHeaderButton` sets the total at `.appDisplayLarge` (55) with `.numericText()`; `AmountText` pairs a flag with an amount. `Screens/Main/Home/BalanceHeaderButton.swift:30-32`; `UI/Views/AmountText.swift:12`.
- Reuse before build: `Row`, `SettingsRow`, `PartialSheet`, `BorderedContainer`, `InputContainer`, `LazyTable`, `Badge`, `BadgedIcon`, `Chip`, `.pill()`, `ImmutableField`, `CapsuleButton`, `ButtonStateLabel`, `FloatingToast` ([components.md](components.md)).

### Flag on sight: the code forms

- Two `.buttonStyle(.filled)` reachable in one rendered state of a body (separate `switch` arms or `if/else` branches are fine): rule 1.
- `.shadow(` on a card, row, tile, sheet, or any view with a `backgroundRow` fill: rule 13.
- `RoundedRectangle(cornerRadius: 12)` or `RoundedRectangle(cornerRadius: Metrics.boxRadius)` without `style: .continuous`: rule 16.
- `cornerRadius: 8`, `10`, `16`, `20`, or any literal other than 6, 12, and 4: rule 15.
- `.padding(13)`, `.padding(.top, 15)`, `spacing: 10`, `spacing: 14`, or any value outside 4, 8, 12, 16, 20, 24, 40 in a screen file or in a component with no documented spec value (the chat transcript's 5/10/15 row gaps are its own rhythm): rule 5.
- `.padding(.bottom, n)` repeated on each child of a `VStack(spacing: 0)`: rule 6.
- `Color(red:`, `Color(hex:`, `Color(r:`, or `Color.white.opacity(0.05)` in a screen file where `.backgroundRow` or another token fits: rule 12.
- `Color.backgroundMain` as the fill of a sheet, card, or tile: rule 20.
- `.glassEffect(` or `glassBackground(` on a view whose only backdrop is `backgroundMain`: rule 18.
- `if #available(iOS 26` around a glass call with no `else` branch: rule 19.
- `.frame(height: 54)`, `.frame(height: 60)` or `.frame(height: 44)` on a button instead of `Metrics.buttonHeight` or `Metrics.buttonHeightThin`: rule 22.
- An icon-only `Button` with no `.frame(width: 44, height: 44)` and no `.contentShape(`: rule 23.
- `if items.isEmpty { Spacer() }`, `EmptyView()`, or a bare `Text("No items")` as the empty branch: rule 24.
- `ProgressView()` as the whole loading state of a list: rule 25.
- `Image(systemName: "...")` with a string literal in a screen file; `Text("🔥")` or any emoji literal standing in for an icon: rule 27.
- `.font(.system(` on a `Text`; `.font(.default(size:` with a literal size in a screen file: rule 30.
- `.scaleEffect(configuration.isPressed` or `.opacity(configuration.isPressed` in a titled button's style instead of `.buttonPress(isPressed:)`: rule 21.
- `RoundedRectangle(cornerRadius: Metrics.buttonRadius)` or `.rect(cornerRadius: 6)` as a button's shape: rule 15.
- `.padding(.bottom, 20)` or `.safeAreaInset(edge: .bottom)` holding a full screen's bottom actions instead of `.bottomEdgePadding()`: rule 7.

### Before / After: the code

| Before | After | Rule |
|---|---|---|
| `Button("Add Money") { }.buttonStyle(.filled)` directly above `Button("Withdraw") { }.buttonStyle(.filled)` | `Button("Add Money") { }.buttonStyle(.filled)` above `Button("Withdraw") { }.buttonStyle(.subtle)` | 1 |
| `.background(Color.white.opacity(0.05)).clipShape(RoundedRectangle(cornerRadius: 12)).shadow(color: .black.opacity(0.3), radius: 8, y: 4)` | `.background(Color.backgroundRow, in: .rect(cornerRadius: Metrics.boxRadius)).overlay(RoundedRectangle(cornerRadius: Metrics.boxRadius, style: .continuous).strokeBorder(Color.rowSeparator, lineWidth: 1))` | 12, 13, 16 |
| `if activities.isEmpty { Spacer() } else { list }` | `if activities.isEmpty { ContentUnavailableView { Text("No activity yet").font(.appTextLarge) } description: { Text("Money you send or receive lands here.").font(.appTextMedium).foregroundStyle(.textSecondary) } actions: { Button("Add Money", action: addMoney).buttonStyle(.filled) } } else { list }` | 24 |

### Needs a device: where to look

- Dynamic Type: `Font.default` is `Font.custom(_:size:)`, so every token scales. `UI/Theme/FontBook.swift:108-110`.
- Longest names: `SettingsRow`, the `TokenCardView` header, a chat bubble; the `Spacer(minLength:)` holds.
- iOS 18 without glass: the `.ultraThinMaterial` open-card chrome, a `.clear` `PartialSheet`, the wallet's legacy pill clearance. `Screens/Main/Home/HomeTabView.swift:261`.
- iOS 26: grouped glass sits in one `GlassContainer`.
- Scroll edges: `Screens/Main/Home/WalletScreen.swift:565-578`.
- Hairlines: a `.regular` separator.
- Landscape and iPad: `TARGETED_DEVICE_FAMILY = 1`, `UISupportedInterfaceOrientations = Portrait` in `Code.xcodeproj/project.pbxproj`.

## Motion lens

### Rules: the code and the evidence

1. `MentionSuggestionList.swift:83-86` turns animation off with `.animation(nil, value:)` where it misled.
2. `NotificationPermissionScreen.swift:60` (0.8 s, bounce 0.4, 0.3 s delay); `ButtonPress.swift:24-28` is the whole budget for a button.
3. `MentionSuggestionList.swift:86`.
4. `.spring(duration:bounce:)`, `UIView.animate(springDuration:bounce:)` and `ChatSpring` share one physics (`dampingRatio = 1 - bounce`, `ChatMotion.swift:40`); `.spring(response:dampingFraction:)` and the `Animations.swift` presets are legacy. `MarketCapSlider.swift:119`, `ToastController.swift:141` (form only; its timing is an open decision).
5. Curves are `.easeOut` or `.smooth` for a fade, `.easeInOut`, `.linear`, never `.easeIn` on an entrance. `YouScreen.swift:616` picks the spring by the gesture's outcome; `WalletScreen.swift:322` fades the deck on `.easeOut`.
6. `ChatMotion.swift:117` (`keyboardScroll`), `:128` (`replySurface`), `ConversationBottomBar.swift:23-28`.
7. `ChatScreenViewController.swift:891-895` builds the options from the notification's curve; `ChatViewController.swift:364-384` pins the transcript inside UIKit's own keyboard block.
8. `ChatMotion.swift:154-157` (`reaction` 0.32 s in, `reactionExit` 0.2 s out).
9. A screen-edge bar or toast may use `.move(edge:)`. `ChatMotion.swift:167-175` and `:238-256` grow a row from the sender's bottom corner; `ConversationBottomBar.swift:672-674` says why the send arrow starts at 0.6.
10. A `.transition` driven by one `.animation(_, value:)` on the view that owns the condition; no `withAnimation` at the dismiss site on top. `ConversationBottomBar.swift:202-204`.
11. `WalletScreen.swift:325-331`; `ChatMotion.swift:158-160` (`reactionReflow = reflow`).
12. Scope `.animation(_, value:)`; never `.animation(.default, value:)` on a container, never `.animation(_)` without `value:`. `ConversationBottomBar.swift:163-166` places the modifier inside the row's padding so the row's own position is left alone.
13. `withAnimation(_:completionCriteria: .removed)` with its `completion:` in SwiftUI, the `completion:` block in UIKit. `WalletScreen.swift:300-316`; `ChatMotion.swift:191-198` is a three-part hold with a stated reason for each part.
14. Pass `options: .allowUserInteraction` to any UIKit spring that moves a view the user may tap mid-flight; UIKit drops touches even though `hitTest` still returns the view. `ReactionPillRowView.swift:351-356`; `common-pitfalls.md:7`.
15. SwiftUI reads `@Environment(\.accessibilityReduceMotion)`, UIKit reads `UIAccessibility.isReduceMotionEnabled`. `ReactionPillRowView.swift:250` (scale 1, alpha still fades); `ReactionPillView.swift:129-137` (a push becomes a fade).
16. `Metrics.buttonPressScale` (0.95) on `Metrics.buttonPressAnimation`, through `ButtonPress`. `ButtonPress.swift:24-28`; `PressButtonStyle.swift`; `TrayCloseButton.swift:69`.
17. `ChatSwipeToReply.swift:178-183`; `HomeTabView.swift:165-169`.
18. `.contentTransition(.numericText())`, `.contentTransition(.symbolEffect(.replace))`, `.id(text)`. `BalanceHeaderButton.swift:32`; `ConversationBottomBar.swift:667`; `ChatMuteStatusLabel.swift:73-81`.
19. Put `.matchedGeometryEffect` before `.frame`, and never `.transition(.identity)` on a matched view's parent. `TokenCardStack.swift:212`; `common-pitfalls.md:15`.
20. `ReactionPillRowView.swift:271-273` (`animatesChanges` is false until the row has drawn once); `ChatMotionTests.swift:182-185`.
21. A programmatic `setContentOffset(animated:)` or `scrollTo`. `TipConversationsScreen.swift:497-545` (the chip row's pull).

### Specifics: the code

- **The model is `ChatMotion`** (`FlipcashUI/Sources/FlipcashUI/Chat/ChatMotion.swift`): one `ChatSpring(duration:bounce:)` vends `.animation` for SwiftUI (`:56`), `.animate {}` for `UIView` (`:62`), and `.layerAnimation(keyPath:)` for a `CAShapeLayer` path (`:82`), run for `settlingDuration` so the travel is never cut short (`:92`). Sixteen named springs, each with a `///` stating its intent; a spring changes there, never at a call site, and its comment stays true. `replyMerge`'s reason is at `:129-131`.
- **Forms outside chat.** Screens write `.spring(duration:bounce:)` and `.smooth(duration:)` (`ConversationBottomBar.swift:93`, `WalletScreen.swift:308`, `ToastController.swift:141`, `EmojiPickerSheet.swift:253`). `.spring(response:dampingFraction:)` survives at 17 sites in `Flipcash/Core/Screens` (`HomeTabBar.swift:56`, `BillOverlayView.swift:141-142`, `YouScreen.swift:75-79`, `ColorEditorControl.swift`) and `usingSpringWithDamping:` at `MessageLiftOverlay.swift:80,229`.
- **Toasts.** `ToastController.swift:141`; the y-scale swell is `FloatingToast.swift:147-172`.
- **`Animations.swift` is frozen** (`FlipcashUI/Sources/FlipcashUI/Transitions/Animations.swift`): `easeOutFastest`, `springFaster`, `springFastestDamped` and `crossFade` serve `AmountField`, `SwipeControl`, `ToastContainer` and `StockChart`, nothing new. A shared value for a new area gets its own `enum` with `///` intents on the `ChatMotion` pattern.
- **A transcript batch update inherits the enclosing spring:** `ChatViewController.swift:448-452` wraps `reload(using:)` in `spring.animate`, `:571-578` picks `insertion` when rows come or go and `reflow` when they only resize, and `:1140-1170` supplies the starting state. That is the only way ChatLayout's insertion gets a spring; no per-cell animation goes on top.
- **Tests pin the physics:** `FlipcashTests/Chat/ChatMotionTests.swift:28-39` holds one row per spring. A changed spring updates its row, a new spring adds one, and the PR says the table moved on purpose. Run `./Scripts/test.sh FlipcashTests/ChatSpringPhysicsTests`. `replySurface`, `replyMerge`, `reaction`, `reactionExit` and `reactionChange` have no row yet.
- **Haptics.** `FlipcashUI/Sources/FlipcashUI/Haptics/Haptics.swift` is the intensity scale: `softest` 0.1, `soft` 0.35, `medium` 0.6, `hard` 0.8, `hardest` and `buttonTap` 0.9, `tap` 1.0, `vibrate` the error notification. SwiftUI views use `.sensoryFeedback(_:trigger:)` with a guard closure: `.impact(weight: .light)` for an arrival (`ConversationScreen.swift:822-829`), `.selection` for a highlight moving (`ChatListChips.swift:81`), `.impact(weight: .heavy)` for a commit (`SwipeControl.swift:74`). A UIKit gesture keeps one generator and prepares it ahead of the threshold (`ChatSwipeToReply.swift:54,154`).
- **Press feedback.** A label that draws its own capsule takes `.pressable`; a custom `ButtonStyle` calls `.buttonPress(isPressed:)`. The keypad's key pop is `KeyPadView.swift:422`.
- **Reduce Motion** is handled in UIKit (`ReactionPillRowView.swift:268`, `ReactionPillView.swift:131`, `ChatTypingIndicatorCell.swift:138`, `LinkCardShimmerView.swift:130`) and, in SwiftUI, by the shared button press (`ButtonPress.swift`); few SwiftUI screens read `accessibilityReduceMotion` themselves, so a new SwiftUI entrance with movement is where a review looks first.
- **Sandbox:** `--motion-sandbox` (and `--motion-sandbox-group`), DEBUG only, replaces the app with `ChatMotionSandboxViewController` (`Flipcash/Core/FlipcashApp.swift:65-83`, `FlipcashUI/Sources/FlipcashUI/Chat/ChatMotionSandbox.swift`): the shipping `ChatViewController` on a scripted send, Delivered, Read, typing, reply, reset. Before/after recordings of chat motion come from it, never from a live send.

### Flag on sight: the code forms

- `.spring(response:` or `.spring(dampingFraction:` in added lines (4).
- A new `static var` in `Animations.swift` (4).
- `withAnimation {` with no curve (5); any `withAnimation` around a `TextField` binding, search results or mention candidates (3).
- `.easeIn(` on an entrance (5).
- `bounce:` above 0.35 (4); any `bounce:` above 0 on a value whose change resizes a bar, an inset or a measured height (6).
- `duration:` above 0.45 outside onboarding (2, 4).
- `.transition(.scale)` with no `scale:`, `.scale(scale: 0)`, `.scaleEffect(0)`, `.scaleEffect(x ? 1 : 0)` (9).
- `if show { View() }` with no `.transition` (10); `.transition(.identity)` near a `matchedGeometryEffect` (19).
- `.animation(.default, value:` on a `ZStack`, `VStack` or screen root; `.animation(.easeOutFastest)` or any `.animation(_)` with no `value:` (12).
- A `.delay(` chain longer than three steps; `Task.sleep` or `asyncAfter` sized to a spring's `duration` standing in for its completion (13).
- `UIView.animate(withDuration:` on a gesture-driven or interruptible view; `usingSpringWithDamping:` in added lines (4, 5).
- `ChatSpring.animate {` or `UIView.animate` moving a tappable view with no `.allowUserInteraction` (14).
- `guard !UIAccessibility.isReduceMotionEnabled else { return }` or `if reduceMotion { return }` (15).
- `.scaleEffect(configuration.isPressed` or `.opacity(configuration.isPressed` inside a titled button's `ButtonStyle` instead of `.buttonPress(isPressed:)`; `.buttonStyle(.plain)` on a titled button (16).
- `Haptics.` or `impactOccurred()` inside a `completion:` block or after a `withAnimation`; `UIImpactFeedbackGenerator(` created inline in a SwiftUI view (17).
- `.onAppear { withAnimation` outside onboarding (20).
- `.matchedGeometryEffect` after `.frame` (19).

### Before / After: the code

| Before | After | Rule |
|---|---|---|
| `withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { isOpen = true }` | `withAnimation(.spring(duration: 0.35, bounce: 0.2)) { isOpen = true }` | 4 |
| `if showsPanel { Panel().transition(.scale) }` under `.animation(.easeIn(duration: 0.5), value: showsPanel)` | `if showsPanel { Panel().transition(.scale(scale: 0.95).combined(with: .opacity)) }` under `.animation(.spring(duration: 0.3, bounce: 0.15), value: showsPanel)` | 9, 5, 10, 2 |
| `guard !reduceMotion else { return }` ahead of `withAnimation(.smooth(duration: 0.25)) { shown = true }` on `.offset(y: shown ? 0 : 12).opacity(shown ? 1 : 0)` | `.offset(y: shown \|\| reduceMotion ? 0 : 12).opacity(shown ? 1 : 0)` with the same `withAnimation` | 15 |

### Needs a device: how to look

- Install the branch on the phone (`device-run.sh` in the design skill's `scripts/`).
- First-frame jumps: Simulator, Debug, Slow Animations (Cmd+T), then the same surface at 1x on the phone.
- Chat motion: launch with `--motion-sandbox` (`device-run.sh -- --motion-sandbox`, or `xcrun simctl launch` with the argument).
- Reduce Motion: Settings, Accessibility, Motion, Reduce Motion.

## States and copy lens

### Rules: the code and the evidence

1. One exhaustive `switch` over loading, failed, empty, loaded. `CurrencyDiscoveryList.swift:17-22,34-62`.
2. Gate on a loaded flag, never on `isEmpty` alone. `BlockedUsersScreen.swift:25`.
3. Not a `Spacer()`-only branch. `TipConversationsScreen.swift:256-280` (`NoChatsView`: icon, headline, one sentence, `.frame(maxWidth: .infinity, maxHeight: .infinity)`).
4. `SearchResultsUnavailableView(searchText:)`. `CurrencySelectionScreen.swift:62-63`.
5. `.redacted(reason: .placeholder)` skeleton rows; no centered `ProgressView()`. `CurrencyDiscoveryList.swift:47-49`; `CurrencyDiscoverySkeletonRow.swift:47`; `Loadable` at `ConfirmPhoneScreen.swift:67`.
6. `ReactorsSheet.swift:162-177`.
7. `ChatItem+Conversation.swift:293` ("Not Delivered. Tap to retry").
8. Seed `@State` from the store in `init`; never render a default and correct it in `.task`. `ActivityHistoryScreen.swift:37-39`; `RatesController.swift:94-116`.
9. Check before `router.present`. The freeze is `.claude/reflections/2026-02-06-give-flow-currency-selection.md`. `DeepLinkController.swift:459-467`.
10. Cross-sheet dialogs go through `session.dialogItem`; a leaf's one-off dialog stays in local `@State`. `.dialog(item:)` is `.sheet(item:)` underneath. `DialogWindow.swift:11-13`; `UsernameEntryScreen.swift:32`.
11. `.lineLimit` plus `.truncationMode(.middle)` for addresses and keys, `.tail` for names; `ExpandableText` for body. `ImmutableField.swift:27`; `TipCardLinkRow.swift:46`; `ExpandableText.swift:10-12`.
12. `.minimumScaleFactor`. `AmountText.swift:43-45`.
13. `.fixedSize(horizontal: false, vertical: true)`. `Font.default` is `.custom(_:size:)`, which scales with Dynamic Type. `Dialog.swift:49`; `PhantomEducationScreen.swift:42`.
14. `ConfirmPhoneScreen.swift:67-70` (blank second line reserved); `CurrencyDiscoveryRow.swift:22` (`.monospacedDigit()`).
15. `UsernameEntryScreen.swift:70,84`; `OnboardingNameViewModel.swift:80-97`.
16. `ButtonStateLabel` through `.loading` then `.success`. `ButtonStyle` cannot see the action's state, and an `if isSubmitting { ProgressView() }` label drops the checkmark. `OnboardingNameViewModel.swift:74-78`.
17. `ToastController.show` (its factories such as `.archivedChat` included), `inPlace: true` for a message that updates; not a screen-level overlay with a `@State` timer. `TipConversationsScreen.swift:195`; `YouScreen.swift:467-470`; `ToastController.swift:67-73`.
18. The confirming button in `.destructive` kind beside `.cancel()`. `DialogItem+ProfileChange.swift:65-83`; `AccountSelectionScreen.swift:111-121`; `ArchivedRow.swift:47-53`.
19. The `Validator` family; submit the validator's `Output`. `UsernameEntryScreen.swift:119-127`; `EnterPhoneScreen.swift:115-116`.
20. `EnterAmountView.swift:99-108`.
21. A keypad string parses only through `AmountValidator`, a money string comes only from `FiatAmount.formatted(...)`, affordability goes only through `Session.hasSufficientFunds(for:)`. `EnterAmountView.swift:100`; `DialogItem+Username.swift:29`; `GiveViewModel.swift:76`.
22. `textError` alone is invisible. `EnterPhoneScreen.swift:115-116`.
23. One complete literal in `Text("...")` or `String(localized:comment:)`; never `Text(verbatim:)`. The repo has no strings catalog, so the literal is the key SwiftUI exports. A FlipcashUI component that shows copy takes `LocalizedStringKey` or `LocalizedStringResource`, never `String`. `HomeTab.swift:55-58`.
24. `UsernameEntryScreen.swift:81`.
25. Gray `.info` for a fixable rejection, red `.error` for a failure that is nobody's fault. `DialogItem+Username.swift:15-21,44-47`.
26. No `print(` or ungated `#if DEBUG` UI; lorem inside `#Preview` is fine. `ExpandableText.swift:164` (preview only); `FlipcashApp.swift:64-73` (DEBUG sandbox gated by a launch argument).
27. Emoji ignore `foregroundStyle`. `TipConversationsScreen.swift:242` (`Image.system(.plus)`).

### States checklist: how to see it on iOS

| State | How to see it |
|---|---|
| Empty, first run | `#Preview` with `.injectingEnvironment(from: .mock)` and empty arrays; a fresh account on device |
| Empty, no results | `SearchResultsUnavailableView` names the query; type `zzzq` |
| Loading, first | Network Link Conditioner "100% Loss", then "3G"; Simulator Debug > Slow Animations |
| Loading, refresh | A footer `ProgressView` only |
| Populated / Long content | Nothing truncates without a `.truncationMode`; `ExpandableText` for body |
| Dynamic Type | `.environment(\.dynamicTypeSize, .accessibility5)` (precedent `LinkUserCardView+Previews.swift:202`); Settings > Accessibility > Larger Text on device |
| In flight | Network Link Conditioner "Very Bad Network"; button `.loading` |
| Success | `.success` checkmark |

### Voice: where each literal lives

- `"Verify Phone Number"` (`navigationTitle`, five screens); `"No Chats Yet"` (`TipConversationsScreen.swift:266`); `"Chat archived"` (`ArchivedRow.swift:49`); drift `"No activity yet"` (`ActivityHistoryScreen.swift:45`), `"No archived chats"` (`ArchivedChatsScreen.swift:22`).
- `"We couldn't create your account. Please try again."` (`OnboardingViewModel.swift:150`).
- `"Couldn't Save Your Username"` / `"Try again"` (`DialogItem+Username.swift:21`); `"Something Went Wrong"` / `"Please try again later"` (32 sites, `Session.swift:1235`); `"Please check your connection and try again"` (`DialogItem+Username.swift:130`).
- `"Too Short"` / `"Usernames must be a minimum of \(UsernameValidator.minimumLength) characters"` (`DialogItem+Username.swift:50-53`); `"\(amount) Minimum Balance Required"` with `minimum.formatted(minimumFractionDigits: 0)` (`DialogItem+Username.swift:29-32`).
- `"Withdrawals are irreversible and cannot be undone once initiated"` (`WithdrawViewModel.swift:370-376`); confirming buttons in `.destructive`, the second `.cancel()`; the bare `.destructive("Yes")` outlier is `Session.swift:1466`.
- `"OK"` is `DialogAction.okay`; `"Next"` / `"Save"` (`UsernameEntryScreen.swift:81`).
- `"Start a new chat, or share your profile"` (`TipConversationsScreen.swift:271`); `"Chat archived"` / `"Undo"` (`ArchivedRow.swift:47-53`).
- `"This is how you'll be uniquely identified on the platform"` (`UsernameEntryScreen.swift:73`).

### Flag on sight: the code forms

- `if is… { ProgressView() } else { Text(` inside a `.buttonStyle(.filled)` label (R16). Live today: `PhantomEducationScreen.swift:49`, `CurrencyCreationWizardScreen.swift:746`.
- `.overlay(` + `Text(` + `Task.sleep` or `asyncAfter` toast in a screen; a `@State private var showToast` (R17).
- `ProgressView()` as a list's whole loading branch; `Spacer()` or `EmptyView()` as its whole empty branch (R3, R5).
- `if items.isEmpty {` with no loaded or loading flag in the condition (R2).
- `@State private var items: [T] = []` filled by `.task` on a screen whose store already has rows (R8).
- `router.present(` on the line after a view-model call that can block, with no `if` around it (R9).
- `.dialog(item:)` bound to the same item from a sheet and its parent (R10).
- A `Button` whose action awaits a network call with no `.disabled(` tied to the in-flight state (R15).
- `Decimal(string:`, `Double(`, or `NumberFormatter().number(from:` on a keypad string; `"$\(`, `String(format: "%.2f"`, or `.value >=` on money (R21).
- `.lineLimit(1)` on a user string with no `.truncationMode`; a fixed `.frame(width:` on a `Text` (R11, R13).
- `Button("Submit"`, `Button("OK"` offered as a choice, `.destructive("Yes")` with nothing after it, a destructive `.alert` whose only button is "OK" (R18, R24).
- `== 1 ? "` pluralization (write `"^[\(count) Contact](inflect: true)"`), `Text(verbatim:`, `Text("\(a) ") + Text(b)` (R23). Live today: `DialogItem+CashFlows.swift:17`.
- `Text("Lorem`, `"John Doe"`, `"test@"`, `"TODO"` outside a `#Preview`; `print(` in a `View`; `#if DEBUG` UI with no launch-argument gate (R26).
- An emoji character inside `Text("` (R27).
- `textError` applied with the same words as the normal state (R22).

### Before / After: the code

| Before | After | Rule |
|---|---|---|
| `Button(action: save) { if isSaving { ProgressView() } else { Text("Save") } }.buttonStyle(.filled)` | `Button(action: save) { ButtonStateLabel("Save", state: buttonState) }.buttonStyle(.filled).disabled(!buttonState.isNormal)`, with `buttonState = .success` held 500 ms before `dismiss()` | R15, R16 |
| `if chats.isEmpty { Spacer() } else { List { ... } }` | `if chats.isEmpty && hasLoaded { NoChatsView() } else { List { ... } }`, where `NoChatsView` is an icon, `"No Chats Yet"`, `"Start a new chat, or share your profile"`, `.frame(maxWidth: .infinity, maxHeight: .infinity)` | R2, R3 |
| `.alert("Delete?", isPresented: $confirm) { Button("OK") { remove() } }` | `dialog = .alert(title: "Remove Account?", subtitle: "Make sure you have a backup of your Access Key before removing this account.") { .destructive("Remove") { remove() }; .cancel() }` | R18, voice |

### Needs a device: iOS settings

- AX5: Settings > Accessibility > Display & Text Size > Larger Text, slider to the end. The UIKit chat transcript uses fixed-size `UIFont.default` and will not scale.
- A toast is announced to VoiceOver at `ToastController.swift:72`.

## Agents: what the plugin's agents read here

The plugin's `design-critic`, `design-surveyor` and `design-carpenter` agents read this section when
they run in this repo.

### Critic

- **No catalog fallback.** If `components.md` is missing, judge reuse against
  `FlipcashUI/Sources/FlipcashUI/Views/` and the app-target views that act as components:
  `Flipcash/Core/Screens/Main/Tips/RecipientRow.swift`, `Settings/SettingsRow.swift`,
  `Flipcash/UI/EnterAmountView.swift`.
- **Engineering rules to flag in design review:** `.claude/docs/common-pitfalls.md` (buttons,
  dialogs, navigation, animation rows) and the Comments, Form validation and Money rules in
  `.claude/docs/hard-rules.md`.
- **Source files** are Swift; a localizability finding includes a FlipcashUI API that takes `String`
  for user-facing copy.

### Surveyor

- **Folders:** screens under `Flipcash/Core/Screens`; the shared UI library is
  `FlipcashUI/Sources/FlipcashUI/Views/`.
- **Tokens:** `Metrics.*`, an `.app*` font, a name from `Theme/Colors.swift`, a `ChatMotion` preset,
  an `Image.system`/`Image.asset` case. **Literals:** `Font.default(size:weight:)`,
  `.font(.system(`, a number, `Color(`, `Color.white.opacity(`.
- **States** to look for: a `switch` over a state enum, `Loadable`, an empty branch, `ButtonState`,
  an error path, pressed feedback, Dynamic Type handling.
- **Previews:** `#Preview` or a `PreviewProvider`, and the mocks used (`Container.mock`,
  `SessionAuthenticator.mock`, `.injectingEnvironment(from: .mock)`).

Quote every `--include='*.swift'`; the shell is zsh and an unquoted glob aborts the grep.

- **Locate:** `grep -rlnE "(struct|enum|class|actor|protocol) <Name>\b" Flipcash FlipcashUI --include='*.swift'`,
  then consumers with `grep -rln "\b<Name>\b"`; follow composed views into
  `FlipcashUI/Sources/FlipcashUI/Views/`.
- **Usage counts:** `grep -rn "\.appTextSmall\b" …`, but
  `grep -rnE "(Color|foregroundStyle\(|fill: )\.success\b" …` for a name that is also an enum case.
- **Range:** `git log <from>..<to> --format='%h %s' -- Flipcash/Core/Screens FlipcashUI/Sources Shared`,
  then `git show --stat --format= <sha>` per commit; group touched files by screen folder.

Value and motion greps:

```bash
grep -nE '\.padding\(|spacing:|Spacer\(minLength|cornerRadius|\.frame\(|\.font\(|Font\.default|\.foregroundStyle\(|\.foregroundColor\(|Color\(|Color\.white|Color\.black|\.opacity\(|\.blur\(|\.shadow\(|Metrics\.|\.buttonStyle\(|\.lineLimit|\.minimumScaleFactor|\.truncationMode|\.contentShape|Image\.system|Image\.asset|Image\(systemName|\.accessibility|label\.font|\.textColor' <files>
grep -nE '\.spring\(|\.bouncy|\.snappy|\.smooth|interpolatingSpring|Spring\(|\.easeInOut|\.easeOut|\.easeIn\(|\.linear\(|withAnimation|\.animation\(|\.contentTransition\(|\.transition\(|matchedGeometryEffect|\.phaseAnimator|\.keyframeAnimator|\.scrollTransition|animatableData|UIView\.animate|CASpringAnimation|ChatMotion\.|\.speed\(' <files>
```

### Carpenter

- **Rule docs:** `.claude/docs/hard-rules.md` and `.claude/docs/common-pitfalls.md`.
- **New shared component:** goes in `FlipcashUI/Sources/FlipcashUI/Views/` with a `///` contract doc
  and a `#Preview` using the repo's mock pattern.
- **Springs:** a changed `ChatMotion` spring updates its row in
  `FlipcashTests/Chat/ChatMotionTests.swift` and its `///` intent.
- **Never touch:** money and amounts, `AppRouter`, the cash bill chain, `Configurations/`,
  `Scripts/`, `.github/`, `.claude/`, `project.pbxproj`, entitlements, `Package.resolved`.
- **Build and test:** `./Scripts/build.sh` (filtered through xcsift; add `-w` only to check for new
  warnings on your lines), then the narrowest test that covers what you touched:
  `./Scripts/test.sh <Target>/<Suite>`.

## Skills: what the plugin's skills read here

### Critique

The lens triggers for this repo:

- `motion.md` when the diff touches `withAnimation`, `.spring(`, `.transition(`, `ChatMotion`,
  `UIView.animate`, `CASpringAnimation`, or `matchedGeometryEffect`.
- `layout-and-hierarchy.md` for any change under `Flipcash/Core/Screens` or
  `FlipcashUI/Sources/FlipcashUI/Views`.
- `states-and-copy.md` for a new screen or flow, a `Loadable`, a `ButtonState`, a toast, a dialog,
  or any string change.
- Untracked files for `this`: untracked Swift files.

### Design spec

- **Code names in the spec note:** map each library component to its FlipcashUI name from
  `components.md`, e.g. `Buttons/Button style=filled` → `.buttonStyle(.filled)`.

### Walkthrough

- **Punch list:** `.claude/plans/<YYYY-MM-DD>-walkthrough.md`. As in `/triage`: no claim without a
  citation.
- **Repo remote:** the one that points at `code-payments/code-ios-app`.
- **Version bump:** `git log <main> --grep 'bump version' -1 --format=%H`.
- **Folders:** `Flipcash/Core/Screens FlipcashUI/Sources Shared`. Squash-merged, so one commit is
  one PR.
- **Defect owner:** `Brandon`.
- **See it:**
  - `./Scripts/build.sh` for the simulator (filtered through xcsift), then install and launch with
    `simctl` as the `verify` skill does, including its test-account login deeplink. If
    `FLIPCASH_UI_TEST_ACCESS_KEY` is absent, ask the user to sign in once on the simulator; app data
    survives reinstalls.
  - Reach each touched screen (loupe per `verify` where it is installed; otherwise the simulator
    control tool; otherwise ask the user to tap through while you capture) and save
    `xcrun simctl io <udid> screenshot <scratchpad>/walkthrough/<Screen>.png`.
