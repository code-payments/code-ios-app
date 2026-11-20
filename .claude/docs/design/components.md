# Components: the Flipcash catalog
What exists in `FlipcashUI`, plus the app-target views that act as library pieces: when to use each, and what to use instead. Generated from the code on 2026-10-05; every name traces to a file, and every count is a call site outside tests and previews. An unlisted variant is a bug here or in the code; read this with `design-standard.md` and the Figma library "Components – Flipcash", which holds only its Cover page today, so its build spec (`.claude/plans/2026-09-29-figma-component-library.md`) follows this file on names and values.

## How to choose
```
I need a button (first match wins)
├── It closes a sheet or cover → CloseButton: .plain in a toolbar, .glass in an inline header
├── It commits money or another irreversible step → SwipeControl, or a dialog with a .destructive action (the tray's red capsule)
├── It sits in a dialog → DialogAction (.standard, .outline, .subtle, .destructive), never a Button; it draws as a TrayAction
├── It sits in a tray → a TrayAction in the tray's actions: (.primary, .secondary, .destructive), never a .filled or .subtle
├── It is the screen's one next step → .filled (54 pt capsule); in a card or bar row → .filledCompact (44 pt)
│   └── It loads or succeeds → label it ButtonStateLabel(_:state:); .disabled() while the state is not .normal
├── It is the secondary, beside or under the primary → .subtle (.subtleCompact at 44 pt); there is one secondary
│   └── It sits under the primary on a full screen → .textLink (a lone secondary stays .subtle; trays keep the capsule)
│   └── Its translucent fill sits over scrolling content → .backed(by:) (.backgroundMain, or a material)
├── It is a help or escape link (Can't Find Your Access Key?, TipCard Cancel) → .textLink, never a capsule
├── It is an action that reads as a row → .filled05
├── It is an 18 pt asset with a short label → .icon(_:)
├── It floats as glass over moving content → CapsuleButton (titled) or .liquidGlassButtonStyle(shape: .circle)
├── It confirms from the top-trailing toolbar (Next, Create) → .prominentButtonStyle()
├── It filters a list → .selectableChip(isSelected:)
├── Its label draws its own capsule (a chip, a pill, a preset) → .pressable; the label sets the hit shape
├── It is an icon-over-caption tile → copy TipCardActionButton, say so in the PR (.card(icon:), LargeButton: 0 uses)
└── Anything else → the Buttons table; never .buttonStyle(.plain) on a tappable surface (it gives no feedback)

I need to present something (first match wins)
├── The next step of this flow → router.push(.destination); a sub-flow path → router.pushAny(_:)
│   └── The destination lives on another tab or in a sheet → router.navigate(to:)
├── A task that returns (give, tips, add money, send) → router.present(_:), presentAddMoney, presentSendAmount
│   └── A sheet is already open → router.presentNested(_:)
├── It needs a new Destination or SheetPresentation case → stop: AppRouter is a load-bearing wall (standard §6)
├── A picker or short local flow (currency, region, token) → .sheet { NavigationStack + plain CloseButton }
├── A short choice or note sized to its content → .sheet { PartialSheet(background: .backgroundSecondary) }
├── A scrolling list over the screen (reactors, emoji) → .presentationDetents([.medium, .large]); no component
├── A question or error that needs an answer
│   ├── It must show over any sheet → session.dialogItem = .error / .alert / .info / .success
│   └── It belongs to this screen → @State var dialogItem + .dialog(item:)
├── A confirmation that needs no answer → toasts.show(_:) through ToastController
├── A photo picker, the report flow or a launch sequence → .fullScreenCover
└── Never: a system .alert, a nested NavigationStack, a screen-level toast overlay

I need a list item (first match wins)
├── A currency or token with its balance → CurrencyBalanceRow(accessory: .chevron / .check(isSelected:) / .loader)
├── A transaction → ActivityRow(activity:), which pushes its own details
├── A conversation in the chat list → RecipientRowScaffold + RecipientRowAccessory
├── A label and value on a confirmation → ConfirmationBreakdownRow, under a ConfirmationAmountRow
├── A Settings or You-tab action with an icon → SettingsRow
│   └── It needs a chevron, loader or disabled look → Row with the 45 pt icon slot and 25 pt top and bottom insets
├── Any other tappable item → Row(insets:accessory:): .chevron when it pushes, .loader(.textMain) while it works
├── A read-only line → never an action-less Row: VoiceOver still announces a button (see Gaps)
└── A card or tile on a backgroundRow fill → the only hand-roll: copy TutorialChecklistCard or TipCardActionButton, say so in the PR
```

## Catalog
`UI/` = `FlipcashUI/Sources/FlipcashUI/`; `Screens/` = `Flipcash/Core/Screens/`; a bare file name is unique in the repo. Uses = call sites outside tests and previews on 2026-10-05. Preview = a `#Preview` macro; a legacy `PreviewProvider` counts as no.
### Buttons
| Component | File | Use when | Instead of | Variants and states | Preview | Uses |
|---|---|---|---|---|---|---|
| `.buttonStyle(.filled)`, `.filledCompact` | `UI/Views/ButtonStyles/FilledButtonStyle.swift` | the screen's one next step, 20 pt in from the sides and from the device's bottom edge (`.bottomEdgePadding()`); `.filledCompact` in a card or bar row | a hand-built `.action` fill | capsule, 54 pt (`Metrics.buttonHeight`; `.filledCompact` 44, `buttonHeightThin`), white fill, black text; one-line title 20 pt in from the ends (`buttonPadding`) that shrinks to 0.8, then truncates, at a fixed height; disabled: fill 10%, text 20%; `ButtonPress`; `.backed(by:)`; loading and success only through `ButtonStateLabel` | no | 77 / 4 (2026-11-19) |
| `.buttonStyle(.filled05)` | `UI/Views/ButtonStyles/FilledButtonStyle.swift` | an action that reads as a row | a `backgroundRow` box in `.plain` | white 5% capsule (the `backgroundRow` value), 54 pt; disabled dims the text only; `ButtonPress` | no | 3 (2026-11-19) |
| `.buttonStyle(.subtle)`, `.subtleCompact` | `UI/Views/ButtonStyles/SubtleButtonStyle.swift` | the one secondary: the alternative beside or under the primary | a second `.filled`; `.filled20` (deleted 2026-11-19) | the tray secondary's look: `Color.actionSecondary` (white 10%) capsule, `textMain` text; disabled keeps the fill, text 20%; 54 pt (`.subtleCompact` 44); one-line title as on `.filled`; `ButtonPress`; `.backed(by:)` | no | 17 / 3 (2026-11-19) |
| `.buttonStyle(.textLink)` | `UI/Views/ButtonStyles/TextLinkButtonStyle.swift` | a help or escape link under the actions: Login's "Can't Find Your Access Key?", Access Key's "Wrote the 12 Words Down Instead?", TipCard Cancel; on a full screen, the secondary under a primary (Notification Permission's Not Now, Intro's Log In); trays keep the capsule secondary | a `.subtle` capsule; `Text` at 50 or 60% in `.plain` | no fill; `appTextMedium`, `textMain` 60%, disabled 30%; 44 pt (`buttonHeightThin`) with a full-width rectangular hit area; `ButtonPress`; no line limit; a screen that ends in one takes `.bottomEdgePaddingUnderTextLink()` | yes | 8 (2026-11-20) |
| `.bottomEdgePadding(_:)`, `.bottomEdgePaddingUnderTextLink()` | `UI/Views/ButtonStyles/BottomEdgePadding.swift` | the view that holds a full screen's bottom actions, in place of its bottom padding | `.padding(.bottom, 20)` above the home-indicator safe area; `.safeAreaInset(edge: .bottom)` with its own padding | pads from the device's bottom edge, not the safe area: `Metrics.buttonPadding` (20) by default, so the last button sits as far from the bottom as from the sides; `UnderTextLink` pads 32 (`Metrics.buttonPaddingUnderTextLink`) under a screen-ending `.textLink`'s 44 pt box; the keyboard still lifts the actions | no | 53 files (2026-11-20) |
| `.backed(by:)` on `.filled` and `.subtle` | `UI/Views/ButtonStyles/FilledButtonStyle.swift`, `SubtleButtonStyle.swift` | a translucent fill (any `.subtle`, a disabled `.filled`) over scrolling content | a call-site `.background(…, in: Capsule())`, which stays put while the button shrinks | any `ShapeStyle` under the fill, inside the press, so it scales with it: `.backgroundMain`, or a material, the iOS 18 stand-in for glass (`.ultraThinMaterial` at `CurrencySendFlow.swift:201`) | no | 4 (2026-11-19) |
| `ButtonPress`, `.buttonPress(isPressed:)` | `UI/Views/ButtonStyles/ButtonPress.swift` | the press inside a custom `ButtonStyle` for a titled button | `.scaleEffect` or `.opacity` on `configuration.isPressed`; a private press modifier | shrinks to 0.95 while held (`Metrics.buttonPressScale`), or dims to 0.7 under Reduce Motion (`buttonPressDim`), on `Metrics.buttonPressAnimation` (0.2 s, bounce 0) scoped to the scale and dim; the tray CTA reads the same values | yes | 13 (2026-11-19) |
| `.buttonStyle(.pressable)` (`PressButtonStyle`) | `UI/Views/ButtonStyles/PressButtonStyle.swift` | a titled button whose label draws its own capsule: a chip, a pill, a preset, the toast's action | `.plain`, which gives no press; a private press style | `ButtonPress`, and a disabled label dims to 0.5 (what `.plain` drew); draws nothing and sets no hit shape, so the label sets it, `.rect` on a capsule under 44 pt | yes | 11 (2026-11-19) |
| `.buttonStyle(.icon(_:))` | `UI/Views/ButtonStyles/IconButtonStyle.swift` | an 18 pt asset with a short label | a hand-built icon chip | `Color.actionSecondary` (white 10%) capsule, padding 12 by 10; `ButtonPress` on the whole chip; no disabled look | no | 0 (2026-11-19) |
| `ButtonStateLabel(_:state:)` | `UI/Views/Buttons/ButtonStateLabel.swift` | the label of a `.filled` or `.subtle` button that loads or succeeds | a `ProgressView` placed in the label | `ButtonState` `.normal`, `.loading` (system spinner in `textSecondary`), `.success` (white check), `.successText(String)`; disable the button while not `.normal` or the check is white on white | yes | 45 (2026-11-19) |
| `TrayAction(_:role:state:isEnabled:action:)` | `UI/Tray/TrayAction.swift` | each button in a tray, in its `actions:`; dialogs get theirs from `.dialog(item:)` | a `.filled` or `.subtle` inside a tray | capsule at least 54 pt (`TrayMetrics.actionHeight` reads `Metrics.buttonHeight`); `Role` `.primary` white, `.secondary` `actionSecondary`, `.destructive` solid `bannerError` red with white text; two sit side by side at equal widths `buttonGap` apart, or stack primary on top when a title won't fit; one-line title that shrinks to 0.8; the house press values; disabled: fill 10% (the secondary keeps its), text 20%; `state:` through `ButtonStateLabel` | no | 3 (2026-11-19) |
| `CapsuleButton` | `UI/Views/Buttons/CapsuleButton.swift` | a glass action over the bill | `Button { ButtonIcon }` with a glass style | circle without a title, capsule with one; `binding:` inits toggle; loading `LoadingView` 25 pt; success green check 15 pt; disabled while not `.normal`; no pressed state on iOS 18 | no | 2 |
| `.liquidGlassButtonStyle(shape:)` | `UI/Views/ButtonStyles/LiquidGlassCompatibleButtonStyle.swift` | any other `Button` drawn as glass | `.glassEffect(.interactive())` on a `Button`; private circle-glass modifiers | `.capsule`, `.circle`; iOS 26 system glass press and disabled; iOS 18 material capsule or white 7% circle, no pressed or disabled look | no | 4 |
| `.prominentButtonStyle()` | `UI/Views/ButtonStyles/LiquidGlassCompatibleButtonStyle.swift` | a top-trailing toolbar confirm (Next, Create) | a `.filled` in a toolbar | `.glassProminent` on iOS 26, `.borderedProminent` below; system blue tint | no | 2 |
| `SwipeControl(text:action:completion:)` | `UI/Views/Controls/SwipeControl.swift` | the irreversible money commit | a plain tap on `.filled` | 64 pt capsule with an 84 pt thumb; on iOS 26 the idle thumb is a clear-glass lens that bends and magnifies the label (composer glass while sending, material thumb on iOS 18); label shimmers while idle and fades with travel; publishes `SwipeControlProgressKey` for the dim around it; commits past 70% of the track, or 50% at a release velocity over 200; parks and shows a `textSecondary` spinner, then a check held 2 s; throw `SwipeControlFailure` for a `bannerError` tint, shake and error haptic, any other error resets silently; disabled 0.4; soft tap at touch-down, light rigid tap on a release that doesn't commit, heavy haptic on commit | yes | 2 |
| `.buttonStyle(.selectableChip(isSelected:))` | `UI/Views/ButtonStyles/Chip.swift` | one filter in a chip row | a hand-built capsule toggle | selected: white 16% capsule, `textMain`; else clear, `textSecondary`; white 10% hairline; `ButtonPress`; no disabled look | no | 2 (2026-11-19) |
| `BubbleButton(font:text:action:)` | `UI/Views/Buttons/BubbleButton.swift` | a small white capsule action in a prompt card | a hand-built white capsule | one look, `TextBubble(.filled)`; `.pressable`, so the house press and a 0.5 disabled dim; rectangular hit area (the bubble is under 44 pt); no loading | no | 3 |
| `.buttonStyle(.card(icon:))` | `UI/Views/ButtonStyles/CardButtonStyle.swift` | never: see Dead | n/a | 110 pt, white 10%, radius 12, pressed 0.6 | no | 0 (dead) |
| `LargeButton` | `UI/Views/Buttons/LargeButton.swift` | never: see Dead | n/a | 40 pt icon over caption; badge with a punched ring | yes | 0 (dead) |

- **Shape:** every button is a capsule, and an icon-only button a circle. `Metrics.buttonRadius` (6) is for fields, containers, cards, and the tiles and rows that keep card corners; no button reads it (`Metrics.swift:22-23`). A capsule inside a card needn't be concentric with it.
- **Pairs:** two buttons together, stacked or side by side, sit `Metrics.buttonGap` (12) apart; `Dialog` and the tray's `actionGap` read it.
- **Press exceptions:** icon-only circles keep a dim (the tray's close and back, 0.6 at `TrayCloseButton.swift:69`); picker segments (`SlidingChipPicker`, `ChartRangePicker`) take none, the sliding selection is the feedback; tiles, rows and cards keep their corners and their own press (tray rows and tiles 0.98 with a selection haptic, `TrayOptionRow.swift:67`); the public group's buttons add a soft haptic on touch-down (`PublicGroupProfileView.swift:321`).
- **Right:** `Screens/Main/Profile/ProfileNameScreen.swift:80`: `ButtonStateLabel` inside `.filled`, disabled while it submits.
- **Wrong:** `Screens/Invite Links/GroupInviteScreen.swift:201`: a pending join request drawn as a disabled `.filled`; a status is a text line, as on the private profile (`Screens/Profile/ChatProfileScreen.swift:720-726`).
### Inputs and keypad
| Component | File | Use when | Instead of | Variants and states | Preview | Uses |
|---|---|---|---|---|---|---|
| `InputContainer(size:highlighted:content:)` | `UI/Views/Containers/InputContainer.swift` | a boxed text field (email, phone, address, recovery phrase) | a `TextField` in a hand-built `backgroundRow` box | `.small` 45, `.regular` 56, `.custom(CGFloat)`; `highlighted` (a caller Bool): 2 pt stroke at 70% plus a white 5% wash, else 1 pt at 30%; no disabled, error or focus state | no | 4 (+2 in `UI/`) |
| `ImmutableField(_:leadingIcon:state:)` | `UI/Views/ImmutableField.swift` | a read-only value to copy (deposit address) | a `Text` inside `InputContainer` | `.success(Image)` green trailing icon, `.default(Image)` gray; middle truncation | no | 1 |
| `TwoFactorCodeView(digitCount:content:)` | `UI/Views/TwoFactorCodeView.swift` | a one-time code typed into a hidden `TextField` | one field per digit | 6 cells, 35 by 45; the next empty cell highlighted; no error state | no | 1 |
| `AmountField` | `UI/Views/AmountField.swift` | inside `EnterAmountView` and `EnterAmountHeader` only | a `Text` of the keypad string | `Prefix` `.none`, `.flagStyle(_)`, `.prefix(String)`; `DefaultValue` `.none`, `.number`, `.string`; ghost decimals at 20%; `appDisplayLarge` at height 70 by default | no | 2 |
| `KeyPadView(content:configuration:rules:)` | `UI/Views/KeyPadView.swift` | inside `EnterAmountView` only | a custom keypad (none exist) | `.decimal()`, `.number()`, `.default()` (0 uses); `CurrencyRules` defaults to 6 integer and 2 decimal digits; a pressed key scales 1.35 (see Gaps); no disabled look | no | 1 |
| `CheckView(active:)` | `UI/Views/CheckView.swift` | the selection mark in a pickable row | an SF `checkmark` | active: white disc with a check; inactive: 1 pt white ring; 24 pt; the row owns the tap | no | 5 |

- **Right:** `Screens/EmailVerification/EnterEmailScreen.swift:30`: the email field inside `InputContainer(size: .regular)`.
- **Wrong:** `Screens/Main/Tips/New Group/NewPublicGroupScreen.swift:136`: a `TextField` in a hand-built `backgroundRow` box with no stroke and no highlighted state.
### Rows and lists
| Component | File | Use when | Instead of | Variants and states | Preview | Uses |
|---|---|---|---|---|---|---|
| `Row(insets:disabled:accessory:content:action:)` | `UI/Views/Containers/Row.swift` | a tappable list item over a hairline | `Button { HStack { …; Spacer(); chevron } }` | `RowAccessory` `.chevron`, `.loader(Color)`; `disabled` turns the text `textSecondary`; spacing 12; 1 px `rowSeparator`; system press dim; its chevron inherits white | no | 11 |
| `SettingsRow(image:title:badge:insets:action:)` | `Screens/Settings/SettingsRow.swift` | a Settings or You-tab action; `asset:` and `systemImage:` inits too | `Row` + `Image().frame(minWidth: 45)` + `Text` + `Spacer()` | 45 pt icon slot; title inherits `appDisplayXS`; `Badge.beta`; no accessory, no disabled; insets 25/0/25/0 at every site | no | 13 |
| `CurrencyBalanceRow` | `Screens/Main/SelectCurrencyScreen.swift` | a currency with its balance in a picker or list | coin, name and amount HStacks | `CurrencyRowAccessory` `.chevron`, `.check(isSelected:)`, `.loader`; `CurrencyLabel.AmountStyle` `.plain`, `.pill`; disabled when `action` is nil, dimmed to 0.4 by the caller | no | 4 |
| `ActivityRow(activity:)` | `Screens/Main/Home/ActivityRow.swift` | a transaction in activity or history | a hand-built avatar and amount row | swap and peer layouts; 40 pt avatar; one line per text; pushes `transactionDetails`; no horizontal padding (the list pads) | no | 3 |
| `RecipientRowScaffold`, `RecipientRowAccessory` | `Screens/Main/Tips/RecipientRow.swift` | a conversation in the chat list | a hand-built avatar, title and time row | placement `.trailingColumn`, `.titleLine`; unread (blue time, dot or count pill); unknown contact (`.pill()`); muted (`MuteBell`); 44 pt avatar | no | 1 / 1 |
| `ContactAvatarView(id:displayName:imageData:blurhash:size:)` | `UI/Views/Contacts/ContactAvatarView.swift` | any person's avatar | `RemoteImage` clipped to a circle for a person | image, then blurhash, then monogram, then silhouette; 44 pt default | yes | 19 |
| `ListHeader(_:)` | `UI/List/ListHeader.swift` | a section title in a grouped `List` | an inline `Text` at 15 pt semibold, white 50% | `appTextSmall`, `textSecondary`, no uppercase | no | 3 |
| `.vSeparator(color:position:weight:alignment:insets:)` | `UI/Modifiers/Separator.swift` | a hairline outside `Row` | `Divider()`, a 1 pt `Rectangle` | `.regular` 1 px, `.medium` 1 pt; `.top`, `.bottom`; pass `.rowSeparator` | no | 5 |
| `LazyTable` | `UI/Views/Containers/LazyTable.swift` | a scrolling stack of `Row`s with an optional parallax header | a `ScrollView` with a hand-built parallax header | no visuals of its own; the header stays hidden unless `headerHeight` is set | no | 2 |

- **Right:** `Screens/Profile/Edit Group/EditGroupScreen.swift:31`: `Row(insets:accessory: .chevron)` with the 45 pt icon slot.
- **Wrong:** `Screens/Main/Tips/ArchivedRow.swift:18`: the 45 pt icon column, `Spacer` and a 9 by 12 chevron rebuilt in a `Button` without `Row`.
### Containers, surfaces and sheets
| Component | File | Use when | Instead of | Variants and states | Preview | Uses |
|---|---|---|---|---|---|---|
| `Background(color:)` | `UI/Views/Containers/Background.swift` | every screen's root fill | `.background(Color.backgroundMain)`, which duplicates toolbar items on iOS 26 | one parameter; fills under the safe area; no hit testing | no | 78 |
| `BorderedContainer` | `UI/Views/Containers/BorderedContainer.swift` | a confirmation summary | a `backgroundRow` box with a hand-drawn stroke | radius 12, 1 pt `textSecondary` 30% stroke over `backgroundRow`; continuous corners; no states | no | 4 |
| `.glassBackground(cornerRadius:)`, `(cornerRadius:tint:)`, `.capsuleGlassBackground()` | `UI/Views/Containers/GlassBackground.swift` | a static glass surface over moving content; the capsule form for a bar or pill | a direct `.glassEffect` with a private fallback | iOS 26 interactive glass (tinted: not interactive); iOS 18 `.ultraThinMaterial` in the same shape, tint at 60% over it | no | 5 / 4 |
| `.glassFieldBackground(cornerRadius:)` | `UI/Views/Containers/GlassBackground.swift` | glass behind a text field | `.glassEffect` on the field, which kills its selection grabbers | glass as a background layer; keep it out of a `GlassContainer` | no | 5 |
| `GlassContainer(spacing:)` | `UI/Views/Containers/GlassContainer.swift` | two or more glass pieces that sample together | glass views placed side by side | iOS 26 `GlassEffectContainer`; iOS 18 passes the content through | no | 1 |
| `PartialSheet(background:canDismiss:canAccessBackground:)` | `UI/Views/Containers/PartialSheet.swift` | a sheet sized to its content | `.presentationDetents([.medium])` for short content | detent = measured height; `.backgroundSecondary` default; `.clear` turns `.thinMaterial` on every OS; radius and dim are the system's | no | 6 |
| `DialogItem`, `.dialog(item:)` | `UI/Dialog/DialogItem.swift` | an error, alert, info or success that needs an answer | SwiftUI `.alert`, `.confirmationDialog` | `.error` (tracked), `.alert`, `.info`, `.success` (not dismissable by default); `Dialog.Style` `.standard` and `.success` both gray, `.destructive` red #BC3434; app-wide through `session.dialogItem` | no | 38 hosts, 152 constructions (2026-10-26) |
| `DialogAction` | `UI/Dialog/DialogAction.swift` | each button in a dialog | a `Button` or a bare `DialogButton` | `.standard`, `.outline`, `.subtle`, `.destructive`; presets `.okay`, `.dismiss`, `.cancel`, `.notNow`; every in-app dialog draws as a tray (`View+Dialog.swift:90-113`): `.standard` is a `TrayAction` `.primary`, `.destructive` its red `.destructive` capsule, `.subtle` and `.outline` its `.secondary`, and a lone action the primary; `DialogButton` (capsules with `ButtonPress`) draws only in a `#Preview` | no | 30 |
| `.softScrollEdge(for:)`, `.scrollEdgeBar(_:_:)` | `UI/Modifiers/ScrollEdge.swift` | content scrolling under a bar; a bar pinned to a scroll edge | gradient overlays; a private `topBar` | iOS 26 soft edge and `safeAreaBar`; iOS 18 none and `safeAreaInset` | no | 4 / 2 |
| `SafariView(url:)` | `UI/View Controllers/SafariView.swift` | a read-only web page (Terms, Privacy) in a sheet | a hand-built `WKWebView` | `barCollapsingEnabled`, `entersReaderIfAvailable` | no | 2 |

- **Right:** `Screens/Main/You/TipCardDownloadSheet.swift:52`: `PartialSheet(background: .backgroundSecondary)` for a short choice.
- **Wrong:** `Screens/Main/Currency Info/CurrencyInfoScreen.swift:527`: private `CircleGlass` calls `.glassEffect` directly and draws nothing on iOS 18.
### Feedback
| Component | File | Use when | Instead of | Variants and states | Preview | Uses |
|---|---|---|---|---|---|---|
| `ToastController`, `toasts.show(_:inPlace:)` | `UI/Views/Containers/ToastController.swift` | a confirmation that needs no answer | an overlay drawn by the screen; `ToastLabel` | `Toast(_:systemImage:action:width:duration:)`, 4 s default; `.fill`, `.fit`; `inPlace:` swaps the text without replaying the entrance; dropped while a sheet, dialog or bill covers the host; bottom only; draws `FloatingToast` (`UI/Views/Containers/FloatingToast.swift`, with a `#Preview`): optional icon and white 12% action pill, min height 44, 14 pt medium text (a literal), emerging from the tab bar | no | 2 (2 hosts) |
| `LoadingView(color:style:)` | `UI/Views/LoadingView.swift` | a spinner inside the control or row that is working | a bare `ProgressView()` (13 screen sites) | always pass `color` (the `.black` default vanishes on `backgroundMain`); `.medium` or `.large` | no | 8 |
| `Loadable(isLoading:hideContent:color:)` | `UI/Views/Containers/Loadable.swift` | a whole surface that waits, layout held | `if isLoading { ProgressView() }` | spinner always `textSecondary` (`color` is ignored); no empty or error state | no | 2 |
| `CircularLoadingView(lineWidth:ringColor:highlightColor:duration:)` | `UI/Views/CircularLoadingView.swift` | a timed processing ring (swap, launch) | `LoadingView` for a timed wait | fills over `duration` from appear and restarts on appear; no completion; shows time, not work | yes | 2 |
| `CurrencyDiscoverySkeletonRow` | `Screens/Main/Currency Discovery/CurrencyDiscoverySkeletonRow.swift` | the skeleton recipe to copy for a loading list | a spinner as a list's whole loading state | `.redacted(reason: .placeholder)` over the row's shape; white 8% coin | no | 1 |
| `Badge(decoration:text:)` | `UI/Views/Badge.swift` | a status label with a dot or check (Beta, Not Found) | a colored `Text` | `.none`, `.bubble(Color)`, `.circle(Color)`, `.checkmark`; only `.circle` ships | no | 2 |
| `Bubble(size:count:color:)` | `UI/Views/Bubble.swift` | an unread count on an icon or tab | a hand-built count capsule | `.regular` 16, `.large` 22, `.extraLarge` 24; 99+; always pass `.unreadIndicator` | no | 3 |
| `.chip(_:)` | `UI/Views/ButtonStyles/Chip.swift` | a status chip inside a tappable row | a hand-built capsule | every `ChipStyle` is a capsule; `ChipStyle.tinted(_:on:)` ships; `.standard` and `.prominent` have 0 uses | no | 1 |
| `.pill()` | `UI/Views/ButtonStyles/Pill.swift` | a quiet tag (Unknown Contact) | a hand-built capsule | `backgroundRow` capsule, `appTextSmall`, `textSecondary`, padding 8 by 4 | no | 1 |
| `TextBubble(style:font:text:)` | `UI/Views/TextBubble.swift` | a white word chip (recovery phrase) | a hand-built white capsule | `.filled`; `.outline` has 0 uses; caller padding adds to a 5 pt vertical, 10 pt horizontal base | no | 2 |
| `SearchResultsUnavailableView(searchText:)` | `UI/Views/SearchResultsUnavailableView.swift` | a search with no results; it names the query | a `Text("No results")` | one state | no | 1 |
| `ExpandableText(_:collapsedLineLimit:)` | `UI/Views/ExpandableText.swift` | long body text that collapses | a `lineLimit` with no toggle | 5 lines default; fade mask; Show More and Show Less; the toggle hides when the text fits | yes | 1 |
| `MuteBell(_:leadingGap:)` | `UI/Views/MuteBell.swift` | the muted mark beside a conversation name | an SF bell placed by hand | hidden when unmuted or lapsed; expires itself | no | 2 |
| `BadgedIcon(icon:badge:)` | `UI/Views/BadgedIcon.swift` | a 100 pt hero glyph with a corner badge | two stacked images | badge 38 pt at offset 8 | yes | 3 |

- **Right:** `Screens/Main/Tips/TipConversationsScreen.swift:195`: `toasts.show(.archivedChat { … })`, "Chat archived" with Undo.
- **Wrong:** `Screens/Conversation/ConversationScreen.swift:569`: a `ToastLabel` overlay with its own timer, the screen-level toast the standard bans.
### Navigation chrome
| Component | File | Use when | Instead of | Variants and states | Preview | Uses |
|---|---|---|---|---|---|---|
| `router.push(_:)`, `pushAny(_:)`, `navigate(to:)` | `Flipcash/Core/Navigation/AppRouter.swift` | the next step of a flow; a jump to another stack | a nested `NavigationStack` | 44 `Destination` cases; back is a chevron with no title; sheet stacks swipe back only from the 30 pt leading edge | no | 58 / 8 / 4 |
| `router.present(_:)`, `presentNested(_:)`, `presentAddMoney`, `presentSendAmount`, `dismissSheet()` | `Flipcash/Core/Navigation/AppRouter.swift` | a task that returns | a local `.sheet` for a router-owned flow | `SheetPresentation` `.give`, `.buy(mint)` (nested only), `.addMoney`, `.downloadApp`, `.sendAmount`, `.tips`, `.switchAccount`; every root carries a plain `CloseButton` | no | 3 / 1 / 10 / 1 / 9 |
| `CloseButton(style:action:)`, `(style:binding:)` | `UI/Views/Toolbar Buttons/CloseButton.swift` | closing any sheet or cover | an `xmark` `Button` with a glass style | `.plain` (toolbar, padding 5); `.glass` (32 pt platter inside system glass on iOS 26, 44 pt on iOS 18, no pressed state on iOS 18); label "Close" | yes | 18 (14 `.plain`, 4 `.glass`) |
| Navigation bar appearance | `Flipcash/Core/AppDelegate.swift` | every pushed screen: `.navigationTitle` with `.toolbarTitleDisplayMode(.inline)` | a custom bar under `.toolbar(.hidden)` | iOS 26 system glass bar, `appTitle` title, `appBarButton` buttons; iOS 18 opaque `backgroundMain` | no | global |
| `HomeTabView` | `Screens/Main/Home/HomeTabView.swift` | the post-login root; no screen draws a tab bar | a tab bar inside a screen | iOS 26 native `TabView`: inset 21, tint `textMain`, unselected `textSecondary`; hidden while a bill shows, a screen is pushed or a card is expanded | no | 1 |
| `HomeTabBar` | `Screens/Main/Home/HomeTabBar.swift` | iOS 18 to 25 only; `HomeTabView` picks it | n/a | 318 by 58 glass pill; white 20% selection; unselected 50%; `Bubble` badge; long press 0.5 s | no | 1 |

- **Right:** `Flipcash/Core/Navigation/RootSheetHost.swift:28`: the sheet root's `ToolbarItem(placement: .topBarTrailing) { CloseButton(action: router.dismissSheet) }`.
- **Wrong:** `Screens/Main/Bill Designer/BillDesignerOverlay.swift:27`: an `xmark` glass circle rebuilt with `ButtonIcon` instead of `CloseButton(style: .glass)`.
### Money and domain
| Component | File | Use when | Instead of | Variants and states | Preview | Uses |
|---|---|---|---|---|---|---|
| `EnterAmountView` | `Flipcash/UI/EnterAmountView.swift` | every amount-entry screen | a screen-built keypad, amount and CTA | `Mode` 8 cases that differ only in the CTA title; `Subtitle` `.singleTransactionLimit`, `.balanceWithLimit`, `.error`, `.hidden`; `header:` and `accessory:` slots; a second init takes `actionContent` (`SwipeControl`); the CTA is a `.filled` with `ButtonStateLabel`; the preview cannot render (no `Session`) | yes | 8 |
| `EnterAmountHeader` | `Flipcash/UI/EnterAmountHeader.swift` | the `header:` of `EnterAmountView` | the centered default (Withdraw, Add Money) | `Hint` `.available`, `.caption`, `.description`; `appDisplayExtraLarge`; the empty amount in `textTertiary` | no | 6 |
| `AmountText(flagStyle:flagSize:content:showChevron:canScale:)` | `UI/Views/AmountText.swift` | a static amount with its flag | `Flag` + `Text` in an HStack (gaps 15, 8 and 4 today) | flag 30 or 15 with a gap of 15 or 8; scales to 0.3; font from the caller; add `.contentTransition(.numericText())` at the call site | no | 3 |
| `TokenSelectorButton(selectedBalance:action:)` | `Flipcash/UI/TokenSelectorButton.swift` | choosing the currency an amount spends | a hand-built coin and chevron | `CurrencyLabel` + 12 pt bold chevron; no disabled or loading | no | 3 |
| `ConfirmationAmountRow`, `ConfirmationBreakdownRow` | `Flipcash/UI/ConfirmationRows.swift` | the amount, then each line, of a confirmation | private `ReceiptRow`; label and value HStacks | amount `appDisplaySmall` with a 24 pt coin and `numericText`, scales to 0.5; line: `appTextSmall` gray title, `appTextMedium` value | no | 4 / 4 |
| `ValueAppreciation(amount:isPositive:style:)` | `UI/Views/ValueAppreciation.swift` | the appreciation line under a balance | a hand-built change chip | `.pill` ships; `.classic` has 0 uses; bakes in 30 pt of bottom padding | no | 1 |
| `Flag(style:size:)` | `UI/Views/Flag.swift` | a fiat or crypto currency glyph | a `RemoteImage` circle for a fiat currency | `.fiat`, `.crypto`; `.small` 15, `.regular` 30, `.none` | no | 7 |
| `RemoteImage(url:)` | `UI/Images/RemoteImage.swift` | a token coin or remote picture; the caller frames and clips it | `AsyncImage` | black 50% circle placeholder; no size of its own | no | 12 |
| `TutorialChecklistCard(title:items:onTap:)` | `Flipcash/Views/TutorialChecklistCard.swift` | an onboarding checklist; the card recipe to copy | a hand-built `backgroundRow` card | done items: green check, text at 38%, disabled; header outside the card | no | 2 |
| `TipcardView` | `Screens/Main/Tips/TipcardView.swift` | the tip card anywhere it renders | a second card layout | proportional to width, 333:269; tint 0.72; photo off by default | no | 4 |
| `BillView` | `UI/Views/Bill/BillView.swift` | the cash bill | a hand-drawn bill | solid or gradient; proportional geometry; draws `CodeView` and `VerticalContainer` | no | 5 |
| `CodeView(data:)` | `UI/Views/Bill/CodeView.swift` | a Flipcash scan code | `QRCode` | color from `.foregroundStyle`; `svg(data:dimension:background:)` export | no | 4 |
| `QRCode` | `UI/Views/QRCode.swift` | a QR code for an external URL | `CodeView` | black on white; blur binding; optional label and center image; `CorrectionLevel` L, M, Q, H | no | 2 |
| `AccessKey(mnemonic:url:)` | `UI/Views/AccessKey.swift` | the recovery access key card | a hand-built key card | fixed art, max width 255 | yes | 3 |
| `StockChart` | `UI/Views/Chart/StockChart.swift` | a price chart | a hand-built chart | ALL, 1D, 1W, 1M, 1Y through `ChartRangePicker` (the only segmented control); loading, error with Retry, scrubbing; pass `Color.Sentiment` | no | 1 |
| `ConversionGraphic(from:to:)` | `UI/Views/ConversionGraphic.swift` | a from-to coin illustration | two `BadgedIcon`s and an arrow by hand | `.dollars`, `.usdcOnSolana` | yes | 2 |

- **Right:** `Screens/Main/Buy/BuyConfirmationScreen.swift:37`: `ConfirmationAmountRow` leads and the breakdown rows follow.
- **Wrong:** `Screens/Main/Home/TransactionDetailsScreen.swift:184`: flag and amount hand-built at an 8 pt gap instead of `AmountText`.
### Chat
The transcript is its own system: UIKit views in `UI/Chat/`, its own rhythm (row gaps 5, 10 and 15; bubble radius 12 with 4 on grouped corners) and its own spec, the chat pass at `.claude/plans/2026-09-29-figma-component-library.md:132-145`. Build and judge transcript work against that spec and `UI/Chat/ChatMotion.swift`, not this catalog. Already listed above and shared with chat: `ContactAvatarView`, `MuteBell`, `.glassFieldBackground`, `.filledCompact`, `.subtleCompact`. Only these chat pieces cross over:

| Component | File | Use when | Instead of | Variants and states | Preview | Uses |
|---|---|---|---|---|---|---|
| `ChatMotion`, `ChatSpring(duration:bounce:)` | `UI/Chat/ChatMotion.swift` | any chat spring; outside chat, `.spring(duration:bounce:)` within 0.17 to 0.45 s and bounce 0 to 0.35 | `Animations.swift` presets; `.spring(response:)` | 16 springs, each with a `///` intent; one value vends the SwiftUI, UIKit and Core Animation forms; pinned by `ChatMotionTests` | no | 53 (10 files) |
| `BubbleBackgroundView` | `UI/Chat/BubbleBackgroundView.swift` | transcript bubbles and link cards (UIKit) | retyping 12 and 4 | `baseRadius` 12, `groupedRadius` 4, continuous; reference the constants as `ChatQuotePanelView.swift:47` does | no | 29 (16 files) |
| `EmojiPickerSheet` | `UI/Chat/Emoji/EmojiPickerSheet.swift` | any emoji choice | a hand-built grid | search; soft scroll edge; presented at medium and large detents (`ConversationScreen.swift:590`) | no | 1 |

- **Right:** `Screens/Conversation/ConversationBottomBar.swift:28`: `replySpring = ChatMotion.replySurface.animation`.
- **Wrong:** `Screens/Conversation/ConversationBottomBar.swift:93`: `widthSpring = Animation.spring(duration: 0.22, bounce: 0.14)`, tuned at the call site outside `ChatMotion`.

## Hand-rolled patterns to absorb
| Pattern | Where (path:line, count) | Becomes |
|---|---|---|
| Icon-over-caption tile | `WalletScreen.swift:628`, `CurrencyInfoContentV2.swift:330`, `GroupInviteSheet.swift:328`, `TipCardActionButton.swift:19`, `AddMoneyStartScreen.swift:216` (5; heights 88, 95, 96; four fills; radii 6 and 16) | one tile: `.card(icon:)` grown height, fill and radius parameters once decided; copy `TipCardActionButton` until then |
| `backgroundRow` card | `TransactionDetailsScreen.swift:388`, `TutorialChecklistCard.swift:59`, `ChatActionRow.swift:39`, `UsernameProgressCard.swift:89`, `AllCurrenciesCard.swift:45`, `ReportFlowScreen.swift:246` (15; radius 6 or 12; padding 12 to 20) | one card container: `BorderedContainer` with a `stroked:` flag; copy `TutorialChecklistCard` until decided |
| Chevron row without `Row` | `RecentActivitySection.swift:23`, `MarketCapExplainerRow.swift:15`, `ArchivedRow.swift:18`, `RecipientRow.swift:163`, `UsernameProgressCard.swift:70`, `SelectCurrencyScreen.swift:273`, `TutorialChecklistCard.swift:84` (7; six chevron sizes) | `Row(accessory: .chevron)` once its chevron is `textSecondary` at one size (variant) |
| Settings layout rebuilt in `Row` | `ReportRow.swift:28`, `ChatMuteRow.swift:33`, `BlockedUsersScreen.swift:57`, `EditGroupScreen.swift:31`, `SettingsAppSettingsScreen.swift:22`, `UserProfileScreen.swift:162`, `ChatProfileScreen.swift:91` (8 sites in 7 files) | `SettingsRow` with `accessory:`, `disabled:` and a default inset (variant) |
| Display-size bare text field | `ProfileNameScreen.swift:54`, `OnboardingNameScreen.swift:38`, `UsernameEntryScreen.swift:52`, `UsernameLookupScreen.swift:56`, `EditGroupNameScreen.swift:63`, `CurrencyCreationWizardScreen.swift:729` (6) | new `DisplayField` (decision open) |
| Button rebuilt inline | 34 pt primary (`BarMetrics.fieldMinHeight`) with its own font and spinner, on `.pressable`, at `ShareToChatsSheet.swift:514` (1); the two hand-built text buttons became `.textLink` on 2026-11-19 | a 34 pt `.filled` size that takes `ButtonStateLabel` (variant) |
| Circle or capsule glass re-rolled | `WalletScreen.swift:816`, `CurrencyInfoScreen.swift:527`, `:540`, `ConversationGatePanel.swift:71`, `MarketCapSlider.swift:107`, `EmojiPickerSheet.swift:430` (6; four iOS 18 fallbacks) | `.liquidGlassButtonStyle(shape: .circle)` on buttons; a circle shape in the `GlassBackground` family for surfaces (variant) |
| Chip or value pill re-rolled | `ReactorsSheet.swift:129`, `SelectCurrencyScreen.swift:250`, `StockChart.swift:88`, `E2eeLearnMoreSheet.swift:35` (4) | `ChipStyle` with fill, stroke and shape options, absorbing `.pill()` and `Badge.bubble` (variant) |
| Pressed feedback re-rolled or missing | `MentionSuggestionList.swift:141`, `ColorEditorControl.swift:275` (2); `.buttonStyle(.plain)` on tappable surfaces (89 in `Screens/`, 2026-11-19) | `ButtonPress` through a library style or `.pressable` on a titled button; tiles, rows and cards keep their own press until the tile recipe is decided |
| Sheet title bar inline | `E2eeLearnMoreSheet.swift:30`, `MuteChatSheet.swift:122`, `GroupInviteSheet.swift:150`, `ReactorsSheet.swift:88` (4, against 14 toolbar sites) | new `SheetTitleBar` once one shape is chosen (decision open) |
| Medium and large detent sheet | `CurrencyPickerSheet.swift:63`, `ReactorsSheet.swift:43`, `ConversationScreen.swift:590`, `GroupInviteSheet.swift:139` (4) | new `DetentSheet` beside `PartialSheet` |
| System alert | `SettingsAdvancedBetaFeaturesScreen.swift:83`, `:94`, `:105` (3) | `DialogItem` with a `DialogAction.destructive` |
| Toast drawn by the screen | `ConversationScreen.swift:569` (1) | `ToastController` with a top placement (variant) |
| Empty state | `SelectCurrencyScreen.swift:65`, `WithdrawScreen.swift:36`, `ActivityHistoryScreen.swift:45`, `ArchivedChatsScreen.swift:22`, `MarketCapExplainerScreen.swift:31`, `BlockedUsersScreen.swift:26`, `TipConversationsScreen.swift:256`, `SettingsAdvancedBetaFeaturesScreen.swift:39` (8) | new `EmptyStateView(icon:title:description:)` modeled on `NoChatsView`, with `SearchResultsUnavailableView` as its search case (decision open) |
| Bare `ProgressView()` | `TransactionHistoryScreen.swift:41`, `ApplicationLogsScreen.swift:45`, `ReactorsSheet.swift:163`, `ScanScreen.swift:211` (13) | `LoadingView(color: .textSecondary)` in a control; skeleton rows or `Loadable` for a list |
| Section title | `SelectCurrencyScreen.swift:81`, `NewPublicGroupScreen.swift:151`, `TutorialChecklistCard.swift:41` (3, beside `ListHeader`) | `ListHeader` with a second style for the white 50% treatment (decision) |
| Linear progress track | `CurrencyCreationState.swift:12` (`CreationProgressBar`), `UsernameProgressCard.swift:94` (private `ProgressTrack`) (2) | new `ProgressTrack` in `UI/` |

## Dead, deprecated, unused
| Name | Status | Evidence | Replace with |
|---|---|---|---|
| `LargeButton`, `CardButtonStyle` (`.card(icon:)`) | dead | 0 sites (`LargeButton.swift:11`; `CardButtonStyle.swift:50`, unused since 2026-04-30) | the decided tile; keep `LargeButton`'s punched-ring badge |
| `ToastContainer`; `ToastLabel` | dead; legacy | 0 sites; 1 site, the screen-level toast at `ConversationScreen.swift:571` | `ToastController` |
| `Session.toast`, `ToastQueue` | unrendered | no view reads them (`Session.swift:55`, `:716-730`; `Toast.swift:18`) | `ToastController` |
| `AppRouter.replaceTopmostAny(_:)`, `DialogButton.Style.secondary`, `DialogAction.Kind.backgroundColor`, `BillView` `action:` and `mint:`, `.if(_:modify:)` | unused API | 0 callers (`AppRouter.swift:196`); no `Kind` maps to `.secondary` (`DialogAction.swift:103-110`); never read (`DialogAction.swift:130-137`, `BillView.swift:34`, `:46-50`); 0 app sites (`Conditional.swift:14`) | delete |
| `Animation.springFastest`, `.springFaster`; `ChatMotion.swapScale` | unused | 0 sites, `springFaster` only inside dead `ToastContainer` (`Animations.swift:18`, `:24`); 0 sites (`ChatMotion.swift:175`) | `.spring(duration:bounce:)` |
| `ValueAppreciation.Style.classic`, `Badge.Decoration` `.bubble`, `.checkmark`, `.none`, `Bubble.Size` `.large`, `.extraLarge`, `TextBubble.Style.outline`, `ChipStyle.standard`, `.prominent`, `KeyPadView.Configuration.default()` | unused variants | 0 sites each; `ChipStyle` has one doc mention (`ChatMuteStatusLabel.swift:27`) | nothing; build none of them in Figma |
| Defaults no caller keeps: `LoadingView` `.black`, `Bubble` `.textSuccess`, `StockChart` `.green` and `.red` | unused | every caller overrides them | defaults of `.textSecondary`, `.unreadIndicator`, `Color.Sentiment` (variant) |
| Fonts `appTitleLarge`, `appTextBody`, `Font.roboto`; haptics `buttonTap`, `softest`, `soft`, `hard`, `hardest`; color asset `error` | unused tokens | 0 sites (`AppFonts.swift:21`, `:33`; `FontBook.swift:64`; `Haptics.swift:22-42`); 13 direct feedback-generator sites bypass `Haptics` | delete in a system PR; route haptics through `Haptics` |
| `ContactsPermissionScreen`, `PhoneVerificationFlowScreen` | dead screens | no call site in the app or its tests; the second holds 1 of the 18 `CloseButton`s | delete |

## Gaps
| Need | Evidence | Scope |
|---|---|---|
| Destructive full-width button | decided 2026-11-19: the tray's red capsule (`TrayAction` `.destructive`, `bannerError`), which `DialogAction.destructive` draws; none ships outside a tray; two system `role: .destructive` buttons in alerts (`SettingsAdvancedBetaFeaturesScreen.swift:119`, `:130`) | variant, outside trays |
| Disabled primary against secondary | a disabled `.filled` (`action` 10%) and any `.subtle` (`actionSecondary`, white 10%) share one fill (`FilledButtonStyle.swift:87`, `Colors.swift:33`), as the tray's capsules do (`TrayAction.swift:228-230`), so a disabled primary reads as a secondary | decision |
| Apple Pay button | the shipped one is inside the onramp web view (`ApplePayWebView.swift:14`); PassKit's `PayWithApplePayButton` has 0 references | decision: PassKit's button, never a `.filled` variant |
| Tile and card | 5 tile recipes with 0 library uses; 15 hand-rolled `backgroundRow` cards; `BorderedContainer` always strokes | new component for the tile, variant for the card (both decisions open) |
| Linear progress track | `CreationProgressBar` and a private `ProgressTrack`, no library piece | new component |
| Empty state, error with retry | 8 hand-rolled empty states; `MarketCapExplainerScreen.swift:31` and private `ChartErrorView` (`StockChart.swift:185`) | new component (decision open) |
| `Row` gaps | its chevron inherits white (`Row.swift:38`) while every hand-rolled one is `textSecondary`, and the standard allows one chevron (§4 Rows); no subtitle or trailing-value slot; an action-less `Row` is still a `Button` to VoiceOver (`Row.swift:26`, `ContractInfoRow.swift:48`); `SettingsRow` hides `accessory` and `disabled` | variant |
| Disabled and pressed looks | `.icon`, `.card`, `.selectableChip` and iOS 18 glass ignore `isEnabled`; the caller dims `CurrencyBalanceRow` (`SelectCurrencyScreen.swift:106-107`); the iOS 18 glass fallback never reads `isPressed` (`LiquidGlassCompatibleButtonStyle.swift:70-88`), so `CapsuleButton` and `CloseButton(.glass)` give no feedback | variant |
| One spinner, one success check | spinners: `ProgressView` tinted `textSecondary` in `ButtonStateLabel.swift:35-37`, `textMain` (`CapsuleButton.swift:82`), `textSecondary` (`SwipeControl.swift:289`); checks: white (`ButtonStateLabel`, `SwipeControl`), green 15 pt (`CapsuleButton.swift:91-92`), `textSuccess` (`DialogButton.swift:71-79`); `SwipeControl` holds success 2 s against the standard's 500 ms | variant for the spinner, decision for the check |
| Heights without tokens | 56 and 45 (`InputContainer.swift:62-63`), 70 (`AmountField.swift:45`), 88, 95, 96 (tiles), 110 (`CardButtonStyle.swift:40`), 34 (chat bar), 43 and 57 (`CapsuleButton.swift:109-113`), 32 and 44 (`CloseButton.swift:57`) | system PR |
| Surface fill for tiles and chips | white 5, 8, 10, 12 and 20% literals; `.white.opacity(` at 66 sites against 43 `backgroundRow` and `rowSeparator` uses | system PR (decision open) |
| Money rolls when it changes | `numericText` is missing from `ActivityRow`, `AmountText`, `ValueAppreciation`, `TransactionDetailsScreen`; it sits inside `ConfirmationRows` but at the call site for `AmountText` (`BalanceHeaderButton.swift:32`); the standard says amounts roll (§1) | variant |
| One amount-entry treatment | empty amount `textTertiary` (`EnterAmountHeader.swift:81`) or `textMain` (`EnterAmountView.swift:137`); flag gap 15, 8 or 4 (`AmountText.swift:52-54`, `TransactionDetailsScreen.swift:184`, `ActivityRow.swift:102`) | decision (standard §4 Amount entry) |
| Sheets | `PartialSheet(background: .backgroundMain)` at `MuteChatSheet.swift:76` and `E2eeLearnMoreSheet.swift:28`, where the standard says `backgroundSecondary` (§4 Sheets); no component for medium and large sheets; `PartialSheet` sets no radius or dim (`presentationCornerRadius` has 0 uses) | decision for the fill, new component for detent sheets |
| Toast placement | `ToastController` hosts at the bottom only (`ToastController.swift:103`); the chat draws its toast at the top (`ConversationScreen.swift:569`) | variant |
| Library pieces outside `UI/` | `CurrencyBalanceRow` and `CurrencyLabel` live in a screen file that `TokenSelectorButton.swift` depends on; `SettingsRow`, `ConfirmationRows`, `EnterAmountHeader` sit in the app target with no `#Preview` | system PR |

## Drift against the Figma library plan
| Plan says (`:N` is a plan line) | Code says | Evidence |
|---|---|---|
| Glass close button 46 pt (`:123`) | the code platter is 32 pt inside system glass on iOS 26 and 44 pt on iOS 18; 46 is the rendered size | `CloseButton.swift:56-58` |
| Nav bar 54 pt with 45×44 platters (`:123`) | system values; the code sets fonts, background and a chevron-only back; the one app-drawn bar is 44 pt | `AppDelegate.swift:329-386`, `CurrencyInfoScreen.swift:549-552` |
| Partial sheets: 8 pt inset, corners ~36/~52, 96% scale, dim #0D0D0E (`:123`) | all system; `PartialSheet` sets detent, background and interaction only; `.clear` is `.thinMaterial` on iOS 26 too, not glass | `PartialSheet.swift:43-46`, `:59-62` |
| Tab bar 360×62, 98×54 lens, white glyphs (`:123`) | the width holds (402 minus 2 × 21); height and lens are system; native glyphs are `textSecondary` and `textMain`; white at 100 and 50% only on the iOS 18 pill, 318×58 | `HomeTabView.swift:48-49`, `:205-206`; `HomeTabBar.swift:43`, `:78`, `:83` |
| Toast material ≈ white 8%, Feedback/Toast from `ToastLabel`, glass tint ≈ #373739 (`:100`, `:123`) | the shipping toast is `FloatingToast` on `capsuleGlassBackground` with a white 12% action pill, and `ToastLabel` has 1 use; no tint literal exists, and tinted glass appears only at two chat sites, colored by the caller | `FloatingToast.swift:89`, `:102`; `ComposerReplyStrip.swift:167`, `ConversationGatePanel.swift:74-76` |
| Pressed is 0.7 opacity (`:20`) | since 2026-11-19 every titled button shrinks to 0.95 through `ButtonPress`, or dims to 0.7 under Reduce Motion (`.filled*`, `.subtle*`, `.textLink`, `.icon`, `.selectableChip`, `.pressable`, `DialogButton`), and the tray CTA reads the same values; tray rows and tiles 0.98; 0.6 on the tray's close and back circles and on `.card` (dead); scale 1.35 on keys; none on iOS 18 glass or `.plain` | `ButtonPress.swift:24-28`, `TrayMetrics.swift:92`, `:105-107`, `TrayCloseButton.swift:69`, `CardButtonStyle.swift:43`, `KeyPadView.swift:448` |
| One `HomeTabBar` (`:100`) | two bars: the native `TabView` on iOS 26, the `HomeTabBar` pill on iOS 18 to 25 | `HomeTabView.swift:196-228`, `:265-295` |
| Navigation/Sheet Title Bar (`:118`) | no component; two shapes: toolbar with a plain close (14 sites), inline header with a glass close (4) | `RootSheetHost.swift:26-30`, `ReactorsSheet.swift:88-98` |
| `RecipientRow` (`:103`); chat Conversation Row and Unread Count Pill (`:135`) | one row named twice; the types are `RecipientRowScaffold`, `RecipientRowBody`, `RecipientRowAccessory`; the count pill is private `UnreadCountPill` (dark digits), not `Bubble` (white digits) | `RecipientRow.swift:22`, `:59`, `:134`, `:175`; `Bubble.swift:13` |
| `KeyPadView` default/decimal/number; KeyPad Key (`:100`, `:118`) | those are `Configuration` factories and `.default()` has 0 uses; `Style` has only `.borderless`; the key is private `KeyPadButton` | `KeyPadView.swift:139-164`, `:243`, `:343` |
| `InputContainer` small/regular; `liquidGlassButtonStyle` as a style (`:100`) | `InputContainer` also has `.custom(CGFloat)` (120 on Login); `liquidGlassButtonStyle` is a `View` modifier taking `shape:`, and `.prominentButtonStyle()` is missing | `InputContainer.swift:62-65`, `LoginScreen.swift:34`, `LiquidGlassCompatibleButtonStyle.swift:31`, `:57` |
| `ValueAppreciation` classic/pill; `EnterAmountView` with a header property (`:103`) | `.classic` has 0 uses; the header is `EnterAmountHeader` with three `Hint` cases, on 6 of 8 screens | `ValueAppreciation.swift:16`, `EnterAmountHeader.swift:15` |
| Dialog standard/success/destructive (`:100`; rebuild open at `:124`) | `.success` renders the same gray as `.standard`: `bannerSuccess` aliases `backgroundSecondary` | `Dialog.swift:93-102`, `Colors.swift:35-36` |
| Figma names (`:118`) | Buttons/Button = `.filled*` and `.subtle`; Feedback/Loading = `LoadingView`; Inputs/Check = `CheckView`; Rows/Contact Avatar = `ContactAvatarView`; Sheets/Dialog Button = `DialogButton`, reached only through `DialogAction` | the Catalog tables |
| Absent from the plan | `ButtonStateLabel`, `BubbleButton`, `.selectableChip`, `.chip`, `.pill()`, `ImmutableField`, `TwoFactorCodeView`, `AmountField`, `Background`, `BorderedContainer`, `GlassContainer`, the glass modifiers, `Loadable`, `FloatingToast`, `CircularLoadingView`, `ExpandableText`, `SearchResultsUnavailableView`, `MuteBell`, `TextBubble`, `BadgedIcon`, `ListHeader`, `StockChart`, `CurrencyLabel`, `RemoteImage` | the Catalog tables |
