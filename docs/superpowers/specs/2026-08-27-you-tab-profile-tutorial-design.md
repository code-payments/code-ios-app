# Design: "Finish Your Profile" tutorial on the You tab

**Platform:** iOS (`code-ios-app`)
**Date:** 2026-08-27
**Figma:** node `9641:16758` (page), card `9544:18140`, Set Profile Picture `9541:10186`
**Status:** approved design → ready for implementation plan

## Summary

Add a two-item checklist card to the top of the You tab that prompts a user to
finish their profile: add a profile picture, and set a minimum tip amount. The
card is the same component the Wallet already renders as "Send Your First Tip",
generalized so it can carry either screen's items.

Only the profile-picture row is wired. The minimum-tip row renders, counts
toward the `0/2`, and self-checks if the server already holds a fee, but its tap
does nothing — that flow is separate work.

## Scope decisions (confirmed)

| Decision | Choice |
|---|---|
| Which card to reuse | `NewUserTutorialView` from the Wallet screen, generalized over its item type. Not a new component. |
| Coexistence with `UsernameProgressCard` | Both render, both unchanged in behaviour. The checklist sits above the link row; the username card stays below Share/Download. |
| Dismissal | None. Visibility is derived from `Profile` and the card disappears at 2/2, so it self-corrects on a profile refresh. |
| Minimum-tip row | Renders and counts. Tap is a no-op stub. |
| Figma metrics | Matched exactly using existing tokens, applied globally to both call sites — it is one component. |

## Current state (reference)

- **The card:** `Flipcash/Core/Screens/Main/Home/NewUserTutorial.swift` holds
  three things — `TutorialItem` (an enum of the Wallet's two items),
  `NewUserTutorialState` (visibility, derived from history-sync state), and
  `NewUserTutorialView` (the rendering).
- **Its only consumer:** `WalletScreen.swift` — `tutorialState` (~line 153),
  the render (~line 483), `handleTutorialTap` (~line 645).
- **Insertion point:** `YouScreen.pageContent` (~line 331), whose
  `if displayName != nil` branch currently starts with
  `TipCardLinkRow(url:).padding(.top, 70)`.
- **Profile fields:** `Profile.profilePicture` and `Profile.minDmChatInitFee`
  in `FlipcashCore/Sources/FlipcashCore/Models/Profile.swift`. Both are the
  completion sources; `setMinDmChatInitFee` exists on the client with no UI
  consumer yet.
- **Photo upload:** `ProfilePhotoScreen` + `ProfileCreationState` already own
  the picker, the blob reservation, the upload, and the error dialogs.
- **The precedents to mirror:** `ProfileNameScreen.Completion` (a `.tipcard`
  vs `.back` fork on the same screen) and `ChangeDisplayNameScreen` (a settings
  wrapper that seeds a fresh `ProfileCreationState` and pins the completion).

## The shared component

`NewUserTutorialView` becomes generic over its item, so the Wallet and the You
tab each keep an exhaustive switch over their own enum:

```swift
protocol TutorialItemPresentable: Identifiable, Equatable {
    var title: String { get }
    var subtitle: String { get }
    var isCompleted: Bool { get }
    /// The glyph for an unfinished item. A finished one is drawn by the card
    /// as a checkmark, so conformers never render the completed state.
    var icon: Image { get }
}

struct TutorialChecklistCard<Item: TutorialItemPresentable>: View {
    let title: String
    let items: [Item]
    let onTap: (Item) -> Void
}
```

The view and the protocol move to `Flipcash/Views/TutorialChecklistCard.swift`
and the view is renamed, because "new user tutorial" no longer describes a card
that also lists profile chores. `TutorialItem` and `NewUserTutorialState` stay
in `Home/NewUserTutorial.swift` — they are the Wallet's, not shared — and
`TutorialItem` gains a `TutorialItemPresentable` conformance whose `icon`
returns what `NewUserTutorialView.icon(_:)` returns today for an incomplete
item.

The alternative considered was adding profile cases to `TutorialItem`. Rejected:
it leaves dead cases in `WalletScreen.handleTutorialTap` and couples the Wallet
to the You tab.

## Metrics

Matched to Figma using existing tokens. Every change lands on the Wallet's card
too, which is intended — it is the same component in the design.

| Figma (`9544:18140`) | Token | Change from today |
|---|---|---|
| Header title 18 Demi | `Font.appBarButton` | was `.appTextLarge` (20) |
| Header padding 16 all round, 0 gap to panel | — | was `.padding(.horizontal, 16)` + a 16 `VStack` gap |
| Count 14, white @50% | `.appTextSmall` + `Color.textSecondary` | none |
| Count text `0/2` | — | was `"\(a) / \(b)"` |
| Panel fill white @5% | `Color.backgroundRow` | was a `Color.white.opacity(0.05)` literal |
| Panel radius 6 | `Metrics.buttonRadius` | was `Metrics.boxRadius` (12) |
| Panel padding 16, rows gapped 16 | — | was rows padded 16 inside an unpadded panel |
| Row: 12 gap, icon 24×24, text gap 4, top-aligned | — | none, except alignment moves to `.top` |
| Incomplete row icon, white @50% | `Color.textSecondary` | was `Color.textMain` |
| Chevron 16×16, vertically centred | `.appTextMedium` on `Image.system(.chevronRight)` | was `.appTextSmall` (14) |
| Row title 16 Demi | `.appTextMedium` | none |
| Row subtitle 14 @50% | `.appTextSmall` + `Color.textSecondary` | none |

Two notes on the mapping. `Color.textSecondary` is rgb(123,123,123), which is
white @50% flattened onto the near-black `background` — it is the token for
Figma's 50% white. And Figma labels the 14pt text Medium while every 14pt token
in the app is Demi; the codebase already renders Figma's 14-Medium as
`.appTextSmall` throughout, so no new token is added for one card.

Moving the padding from the row to the panel shrinks each row's hit area to its
own bounds, leaving the 16pt gap between rows dead. The row keeps
`.contentShape(Rectangle())`; a row is still taller than the 44pt minimum.

## Icons

Both row icons are exported from Figma into
`FlipcashUI/Sources/FlipcashUI/Assets/UI.xcassets/icons/` as template SVGs, with
`Asset` cases added alongside the existing `IconChecklist` / `IconPeople` entries.

- **`IconPeopleCircle`** (node `9544:18148`) — a bust inside a ring. SF's
  `person.circle` is close but not the same glyph, and pairing an SF symbol with
  an exported stroke icon in adjacent rows would show two different line weights.
- **`IconCoins`** (node `9541:9922`) — two overlapping outlined coins. No SF
  equivalent, and not the existing `coinsAdd` asset.

Both are drawn at 1.5pt stroke in white at 50% opacity; the opacity is dropped
from the exported artwork and expressed as `Color.textSecondary` at the call
site, so a template tint still works.

The **completed** state is unchanged — `checkmark.circle.fill` in
`Color.Sentiment.positive`. The frame shows no completed row, so there is
nothing in the design to match it against.

## Visibility

```swift
struct ProfileTutorialState: Equatable {
    /// Withholds the card until a profile exists, so a session that has not
    /// loaded one yet does not flash an all-incomplete checklist.
    let hasProfile: Bool
    let hasProfilePicture: Bool
    let hasMinimumTipAmount: Bool

    var items: [ProfileTutorialItem]
    var isComplete: Bool          // every item completed
    var isVisible: Bool           // hasProfile && !isComplete
}
```

Built from `Profile?`: `hasProfilePicture` is `profilePicture != nil`,
`hasMinimumTipAmount` is `minDmChatInitFee != nil`. Both live in
`Flipcash/Core/Screens/Main/You/ProfileTutorial.swift` alongside
`ProfileTutorialItem` (`.profilePicture(isCompleted:)`,
`.minimumTipAmount(isCompleted:)`).

## Placement

Inside `YouScreen.pageContent`'s `if displayName != nil` branch, above
`TipCardLinkRow`:

```swift
if profileTutorialState.isVisible {
    TutorialChecklistCard(
        title: "Finish Your Profile",
        items: profileTutorialState.items,
        onTap: handleProfileTutorialTap
    )
    .padding(.top, 70)
    .accessibilityIdentifier("you-profile-tutorial-card")

    TipCardLinkRow(url: url).padding(.top, 19)
} else {
    TipCardLinkRow(url: url).padding(.top, 70)
}
```

The card takes the 70pt gap the link row holds today so the block below it does
not move up when the card is absent. `UsernameProgressCard` is untouched.

`handleProfileTutorialTap` switches exhaustively:

```swift
case .profilePicture:    router.push(.changeProfilePicture)
case .minimumTipAmount:  break   // Stubbed: the fee flow is separate work.
```

## Changing the profile picture

A new destination and a wrapper, mirroring `changeDisplayName` /
`ChangeDisplayNameScreen`:

- `AppRouter.Destination.changeProfilePicture`, listed under the settings group
  so `owningStack` is `.you`, with a `description` of `"changeProfilePicture"`
  and a place in `payload`'s nil-returning list.
- `AppRouter+DestinationView` renders `ChangeProfilePictureScreen`.
- `ChangeProfilePictureScreen` seeds a fresh `ProfileCreationState` with the
  current display name and mounts `ProfilePhotoScreen(completion: .back)`.

`ProfilePhotoScreen` gains the same `Completion` fork `ProfileNameScreen` has:

| | `.tipcard` (setup, today's behaviour) | `.back` (new) |
|---|---|---|
| Nav title | none | "Set Profile Picture", inline |
| Heading + subtitle | "Upload Your Photo" / "This photo will be shown when receiving tips" | omitted |
| Button | "Next" | "Save" |
| On success | `popToRoot(on: .tips)` then `push(.tipcard)` | `popTopmost()` |

Its metrics come from node `9541:10186`, and like the card they apply to both
completions rather than forking:

| Figma | Token / value | Change from today |
|---|---|---|
| Nav title "Set Profile Picture", 20 Demi, inline | `.navigationTitle` + `.toolbarTitleDisplayMode(.inline)` | new; `.tipcard` keeps no title |
| Avatar 158×158 | — | was 150 |
| Plus glyph 64 | — | was 40 |
| Avatar → name gap 21 | — | was 16 |
| Name 32 Demi | `.appDisplayCompact` (30) | was `.appDisplaySmall` (24) |
| Button 60 tall, radius 6, white | `.buttonStyle(.filled)` | none |

The name's 32pt has no token — `.appDisplayCompact` at 30 is the nearest, and no
new token is added for one screen. I could not check the setup flow's own frame
for the avatar and name, so these are applied on the assumption that the two
flows draw the same avatar block; if the setup frame says otherwise, the fix is
to revert those three rows rather than to fork them.

The screen also adopts `ButtonStateLabel` with a `.success` state held for
500ms before navigating, replacing the bare `ProgressView`. This is what the
designer's note asks for ("spinner then checkmark, same timing as saving the
Access Key") and what `ProfileNameScreen.submit()` already does. **It applies to
both completions**, so the existing setup flow's button changes too — the same
reasoning as the card: one button, one behaviour.

## Testing

Swift Testing, alongside the existing suites:

- `FlipcashTests/ProfileTutorialStateTests.swift`, patterned on
  `NewUserTutorialStateTests`: withheld with no profile; visible with a profile
  and neither item done; still visible with one done; hidden at 2/2; the count
  and `isCompleted` flags track the two `Profile` fields.
- `FlipcashTests/Navigation/YouTabRoutingTests.swift`: `.changeProfilePicture`
  resolves to the `.you` stack.

## Out of scope

- The minimum-tip flow itself. The row is a stub.
- The other Figma note on the frame — "Tip card itself is updated (color, drop
  shadows, and outlining stroke)" — which is a `TipcardView` restyle.
