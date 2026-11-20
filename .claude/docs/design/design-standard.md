# The House Standard — Flipcash iOS design

**Owner:** Aiden (design quality). **Status:** v1 draft, 2026-10-05. Lines marked ◇ were drafted from
the code and the team's past decisions; Aiden keeps or strikes them.

Flipcash should feel like one house, not a row of additions. This file is the drawings: what the house
is, what it is built from, and the rules every room follows. `lenses/` turns each dimension into checks a
reviewer or builder can run; `components.md` lists the materials; `design-decisions.md` records why.
Read this before touching UI, motion, or copy, then the lens for the dimension you touch.

## 1. What Flipcash is ◇

- **Dark, calm, quick.** One theme (`backgroundMain` #19191A). There is no light mode to design for.
- **Money is the hero.** The amount is the largest text on any screen that shows one, in a bold display size (SF Semibold), rolling with `.contentTransition(.numericText())` when it changes.
- **SF, Semibold-forward.** The app sets its text in the system face; `FontBook` maps the tokens' bold to Semibold (where Avenir's Demi sat), medium to Medium, and the rest to Regular. Titles, buttons, amounts and the text tokens (`appTextLarge`, `appTextMedium`, `appTextSmall`) are Semibold; `appTextMessage` and captions are Medium; Regular (`appTextBody`) has no use today ◇. Size and `textSecondary` carry the hierarchy more than weight does. The Groups and Money tab titles are the one true Bold (`ShellTabTitle.swift`), since the app's bold weights render a step lighter.
- **Motion settles; it does not bounce.** Springs are short (0.17–0.45 s) with low bounce (0–0.35), exits are quicker than entrances, and the keyboard is never fought.
- **Native first.** System sheets, SF Symbols, Liquid Glass on iOS 26 with an honest material on iOS 18. Nothing on screen should read as a web page.
- **Restraint reads as intent.** One primary action, no decoration that does no work, nothing that could belong to any of ten thousand other apps.

## 2. Principles

1. **One primary action per screen.** One `.filled` button; everything else is `.subtle`, `.textLink` or `.icon`. Two primaries means the screen has not decided. (Revised 2026-11-19: `.filled20` is gone; `.subtle` is the one secondary.)
2. **Reuse before build.** A catalogued component (`components.md`) before a hand-rolled stack; a variant of it before a new one; a new component only when nothing fits, and then it lives in `FlipcashUI` with a `///` contract doc and a `#Preview`.
3. **Tokens, not literals.** Colours from `Colors.swift`, type from `AppFonts.swift`, sizes from `Metrics.swift`, springs as duration + bounce. A value the system lacks is a question for a system PR, not a literal in a screen.
4. **Every state is designed.** Empty, loading, error, populated, long content, Dynamic Type at accessibility sizes, iOS 18 without glass, Reduce Motion on. A state nobody has seen is a state that is wrong.
5. **Frequency decides elaboration; exits are quieter than entrances.** Something done a hundred times a day gets press feedback and nothing more. First-time moments may be elaborate.
6. **Feel it on the device.** Motion and touch are judged on a 120 Hz iPhone before they ship. The simulator is for layout and states.
7. **Shared values change in their own PR.** A token, preset or component change lists every screen it affects. A screen-local value stays local to the screen.
8. **Code wins; Figma mirrors it.** The Figma library is built from the code's values. When they drift, the code is the truth and the library is corrected, or a decision is recorded.

## 3. Materials

| Material | File | Rule |
|---|---|---|
| Colour tokens | `FlipcashUI/Sources/FlipcashUI/Theme/Colors.swift` | 23 semantic tokens (`textMain`, `textSecondary`, `textTertiary`, `action`, `backgroundRow`, `rowSeparator`…) plus `Color.Sentiment`. Nothing else exists; a literal colour in a screen is a finding. The white-alpha washes the app leans on (`Color.white` 106 sites, `.white.opacity` 66) need names ◇. |
| Per-person colour | `Theme/ComplementaryPalette.swift` | Derived from the user id; identical on Android. Never hand-pick a person colour. |
| Type tokens | `Theme/AppFonts.swift`, `Theme/FontBook.swift` | `appDisplay*`, `appTitle*`, `appText*`, `appBarButton`, `appKeyboard`. A new size or weight is a new token. |
| Metrics | `FlipcashUI/Sources/FlipcashUI/Metrics.swift` | `buttonHeight` 54, `buttonHeightThin` 44, `buttonGap` 12, `buttonRadius` 6 (fields, containers and cards; buttons are capsules and never read it), `boxRadius` 12, `buttonPadding` 20, `buttonLineWidth` 1; the press is `buttonPressScale` 0.95, `buttonPressDim` 0.7 and `buttonPressAnimation` (spring 0.2 s, bounce 0). `buttonPaddingUnderTextLink` 32 lives in `Views/ButtonStyles/BottomEdgePadding.swift`. |
| Spacing rhythm ◇ | no scale yet | 20 for screen gutters and button insets; 12 and 8 inside groups; 16, 24, 40 as occasional steps. Corners are continuous. A scale is a system decision (`design-decisions.md`, open). |
| Motion | `FlipcashUI/Sources/FlipcashUI/Chat/ChatMotion.swift` | The model: one `ChatSpring(duration:bounce:)` vends the SwiftUI, UIKit and Core Animation forms, and every preset carries its intent in a `///` comment. `Transitions/Animations.swift` is legacy; nothing new goes there. |
| Haptics | `FlipcashUI/Sources/FlipcashUI/Haptics/Haptics.swift` | Named intensities; one haptic per event, fired on the event, not on the animation. |
| Symbols and assets | `Theme/Image+Symbols.swift` | SF Symbols through `Image.system`, the brand set through `Image.asset`. Emoji are never icons. |
| Components | `components.md` | What exists, when to use it, and what to use instead. An unlisted variant is a bug in the catalog or in the code. |
| Device screens in Figma | `figma-screens.md` | The Screen Kit: every Figma screen is a `Screen/iOS` or `Screen/Android` instance filled through slots. System chrome comes only from Apple's iOS 27 and Material 3 kits; it is never drawn. |

## 4. Patterns ◇

- **Presentation.** Push for a step inside a flow; a sheet for a task that returns; a partial sheet for a short choice; a dialog through `session.dialogItem` when it must cross a sheet; a toast through `ToastController` for a confirmation that needs no answer. Never a nested `NavigationStack`; never a screen-level toast overlay. Two overlays survive today (the bill's `Session.toast`, the conversation's reaction toast) and are findings until routed or recorded as exceptions. Where a toast lands on a pushed screen with its own bottom bar is undecided ◇.
- **Buttons.** Every button is a capsule; an icon-only button is a circle. The primary is `.filled` at 54 pt (`.filledCompact` 44). The one secondary is `.subtle`, a white 10% capsule (`.subtleCompact` 44). A help or escape link is `.textLink`: no fill, 60% text, a 44 pt box. On a full screen the secondary under a primary is a `.textLink`; a lone secondary stays `.subtle`, and trays keep the capsule secondary. `.icon` is for a glyph with an accessibility label. Two buttons together sit `Metrics.buttonGap` (12) apart, in trays too. A title stays on one line: it shrinks to 0.8, then truncates. On a full screen the bottom actions sit 20 pt from the device's bottom edge through `.bottomEdgePadding()`; a screen that ends in a text link uses `.bottomEdgePaddingUnderTextLink()` (32 pt under the link's box). Progress goes through `ButtonStateLabel` (`.loading → .success`, success held about 500 ms before moving on). Pressed is one press everywhere: a shrink to 0.95, or a dim to 0.7 under Reduce Motion, through `ButtonPress` (`.pressable` for a label that draws its own capsule). Tiles, rows and cards keep their own press, icon circles keep a dim, picker segments take none, and keypad keys are keys, not buttons, and keep their pop. Every tappable surface takes a library style or a style that gives feedback; `.buttonStyle(.plain)` on a tappable card, row or tile is a finding, because it gives no feedback at all (44 sites today). (Revised 2026-11-19: capsules, 54 pt, one secondary, and the shrink replaces the opacity drop.)
- **Rows.** `Row(accessory:)` for a tappable list item in a stack (chevron or loader), `SettingsRow` in Settings; inside a `List`, every row takes 20 pt `.listRowInsets`, `.listRowSeparatorTint(.rowSeparator)` and a 44 pt minimum hit area, and a conversation row is `RecipientRowScaffold`; `backgroundRow` fills and `rowSeparator` hairlines; the whole row, insets included, is the hit area. One chevron, `Row`'s, not a seventh size.
- **Tiles and cards ◇.** An icon-over-caption tile and a `backgroundRow` card are each one recipe once decided (today: five tile recipes and fifteen hand-rolled cards). Until then, copy `TipCardActionButton` for a tile and `TutorialChecklistCard` for a card, and say so in the PR.
- **Amount entry.** `KeyPadView` into `AmountField` inside `EnterAmountView`; parsed only through `AmountValidator`; shown at a display size; the empty amount and the flag-to-amount gap are one treatment, not a per-screen one ◇; the available balance stays frozen through send and dismiss.
- **Confirmation.** The amount first, breakdown rows under it, one primary action; the irreversible step behind `SwipeControl` or a dialog, never a plain tap.
- **Glass.** `glassBackground`, `capsuleGlassBackground`, `GlassContainer` and `liquidGlassButtonStyle`, only over content that moves behind them; on iOS 18 the fallback is a material, not a flat fill pretending, and never a private re-roll with its own fallback (four exist today).
- **Sheets.** A root or nested sheet goes through `AppRouter`; a local picker sheet is a `NavigationStack` with a plain `CloseButton`; a short choice is a `PartialSheet` on `backgroundSecondary`. One sheet title bar shape ◇ (today: toolbar with plain close at 14 sites, inline header with glass close at 4).
- **Empty states.** Sized like the populated state, gated on a loaded flag, with a headline and the next action inside them (`NoChatsView` in `TipConversationsScreen.swift` is the model). A search miss uses `SearchResultsUnavailableView` and names the query.
- **Loading and failure.** Skeleton rows that hold the shape, `Loadable` for a whole surface, `ProgressView` only inside the control that is working and tinted `.textSecondary`; a failed load shows a message and a retry.
- **Copy.** Title Case for navigation titles, dialog titles, empty-state headlines and buttons; sentence case for subtitles, hints, toasts and placeholders. Buttons name the outcome; an error title names what failed and its subtitle names the fix; a destructive confirmation's button names the outcome beside Cancel. The voice section of `lenses/states-and-copy.md` has the exemplars.

## 5. Motion vocabulary

- Written as duration + bounce. `ChatMotion`'s ranges are the house ranges: 0.17–0.45 s, bounce 0–0.35.
- Bounce 0 wherever an inset tracks the keyboard or a bar (`keyboardScroll`, `replySurface`): overshoot drags content past its resting place.
- Entrances start at scale 0.9–0.95 plus opacity, anchored at the edge they come from; a glyph, pill or toast no taller than 44 pt may start at 0.4–0.6, and a bar or toast that belongs to an edge may slide from it; nothing starts at 0. Exits run 20–30% quicker, with bounce 0 and less travel.
- Regrouping and reflow are the slowest motions (`corner`, 0.45/0.32) so they read as settling.
- Reduce Motion keeps opacity and colour changes and drops movement and scale. Removing all feedback is a finding.
- A changed `ChatMotion` spring updates its row in `FlipcashTests/Chat/ChatMotionTests.swift` and its `///` intent, and the PR says so.
- Replay: `--motion-sandbox` for chat; a local tuner panel for everything else while tuning (never committed).

## 6. Load-bearing walls

Never touched in design work, whoever is doing it: money, amounts and affordability (`Session.hasSufficientFunds(for:)`, `TokenAmount`, `FiatAmount`, `ExchangedFiat`); navigation structure (`AppRouter`); the cash bill chain (`showCashBill`, `SendCashOperation`); `Configurations/`, `Scripts/`, `.github/`, `project.pbxproj`, entitlements. A design change that needs one of these stops and becomes a conversation with Brandon.

## 7. Taste calls reserved for Aiden

Agents and teammates present the options and the rule that applies; they do not decide these: how something feels on the device; which of two defensible options ships; the tone of a line of copy; any value this standard does not cover. "The standard is silent here" is a valid finding and a request for a decision, which is then recorded in `design-decisions.md`.

## 8. Keeping this true

Every name above traces to a file. When a file moves or a value changes, this file changes in the same PR. When Aiden makes a call that generalises, it goes in `design-decisions.md` with its why; when it is a rule, it comes here. Verify by prompting: when an agent invents a variant, hard-codes a colour, or picks the wrong component, the hole is in these docs. Fix the docs, not just the output.
