# "Finish Your Profile" Tutorial Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a two-item "Finish Your Profile" checklist card to the top of the You tab, wiring only the profile-picture row.

**Architecture:** The Wallet's existing tutorial card is generalized over its item type via a `TutorialItemPresentable` protocol and moved to `Flipcash/Views/`, so the Wallet and the You tab each keep an exhaustive switch over their own enum. Card visibility on the You tab is derived from `Profile` (picture present, minimum-fee present) with no local dismissal flag. The profile-picture row pushes a new `.changeProfilePicture` destination that reuses `ProfilePhotoScreen` through a `Completion` fork, mirroring `ProfileNameScreen` / `ChangeDisplayNameScreen`.

**Tech Stack:** Swift 6.1, SwiftUI, Swift Testing (`import Testing`, `@Suite`/`@Test`, `#expect`). Design tokens from `FlipcashUI` (`Font.app*`, `Color.*`, `Metrics.*`). Tests run via `./Scripts/test.sh <Target>/<Suite>`.

**Design spec:** `docs/superpowers/specs/2026-08-27-you-tab-profile-tutorial-design.md`

---

## Conventions for every task

- **Hard rules that apply throughout:** Swift Testing only, never XCTest. Non-private API gets a one-sentence `///` contract doc saying *what*, never *how*. Prefer exhaustive `switch` over `if case` so the compiler flags new cases. Never add a `Co-Authored-By` or `Claude-Session` trailer to a commit.
- **Xcode targets use file-system-synchronized groups**, so a new `.swift` file under an existing source directory is picked up automatically. No `project.pbxproj` editing is needed.
- **Never run the full `AllTargets` suite.** Run only the targeted suites each task names.
- **Do not cite Figma URLs** in code comments or commit messages. Cite node ids (e.g. `9544:18140`).

## File structure

| File | Responsibility |
|---|---|
| Create `Flipcash/Views/TutorialChecklistCard.swift` | The shared card: the `TutorialItemPresentable` protocol and the generic view that renders a title, an `n/m` count, and a panel of tappable rows. |
| Modify `Flipcash/Core/Screens/Main/Home/NewUserTutorial.swift` | Keeps the Wallet's `TutorialItem` and `NewUserTutorialState`; loses the view. `TutorialItem` gains a `TutorialItemPresentable` conformance. |
| Modify `Flipcash/Core/Screens/Main/Home/WalletScreen.swift:483` | Renames the view it renders. |
| Create `Flipcash/Core/Screens/Main/You/ProfileTutorial.swift` | The You tab's `ProfileTutorialItem` and `ProfileTutorialState`. |
| Modify `Flipcash/Core/Screens/Main/You/YouScreen.swift` | Renders the card above `TipCardLinkRow` and routes its taps. |
| Modify `Flipcash/Core/Navigation/AppRouter+Destination.swift` | Adds `.changeProfilePicture`. |
| Modify `Flipcash/Core/Navigation/AppRouter+DestinationView.swift` | Maps it to `ChangeProfilePictureScreen`. |
| Create `Flipcash/Core/Screens/Settings/ChangeProfilePictureScreen.swift` | Seeds a `ProfileCreationState` and mounts `ProfilePhotoScreen(completion: .back)`. |
| Modify `Flipcash/Core/Screens/Main/Profile/ProfilePhotoScreen.swift` | Gains the `Completion` fork, the Figma metrics, and `ButtonStateLabel`. |
| Create two imagesets under `FlipcashUI/Sources/FlipcashUI/Assets/UI.xcassets/icons/` | `IconPeopleCircle`, `IconCoins`. |
| Modify `FlipcashUI/Sources/FlipcashUI/Theme/Image+Symbols.swift` | Adds the two `Asset` cases. |
| Create `FlipcashTests/ProfileTutorialStateTests.swift` | Visibility and derivation tests. |
| Modify `FlipcashTests/Navigation/YouTabRoutingTests.swift` | A `.changeProfilePicture` routing test. |

---

## Task 1: Export the two row icons

**Files:**
- Create: `FlipcashUI/Sources/FlipcashUI/Assets/UI.xcassets/icons/IconPeopleCircle.imageset/IconPeopleCircle.svg`
- Create: `FlipcashUI/Sources/FlipcashUI/Assets/UI.xcassets/icons/IconPeopleCircle.imageset/Contents.json`
- Create: `FlipcashUI/Sources/FlipcashUI/Assets/UI.xcassets/icons/IconCoins.imageset/IconCoins.svg`
- Create: `FlipcashUI/Sources/FlipcashUI/Assets/UI.xcassets/icons/IconCoins.imageset/Contents.json`
- Modify: `FlipcashUI/Sources/FlipcashUI/Theme/Image+Symbols.swift:187-200`

These are exported Figma artwork. Do **not** hand-author or redraw them. The
`opacity="0.5"` group attribute Figma emits is dropped — the 50% is applied at
the call site via `Color.textSecondary` so template tinting works.

- [ ] **Step 1: Write the `IconPeopleCircle` SVG** (Figma node `9544:18148`)

```xml
<svg width="24" height="24" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
<g id="IconPeopleCircle">
<path d="M15.25 10C15.25 11.7949 13.7949 13.25 12 13.25C10.2051 13.25 8.75 11.7949 8.75 10C8.75 8.20507 10.2051 6.75 12 6.75C13.7949 6.75 15.25 8.20507 15.25 10Z" stroke="white" stroke-width="1.5" stroke-linejoin="round"/>
<path d="M18.143 18.9157C16.8294 16.9968 14.668 15.75 12 15.75C9.33203 15.75 7.17056 16.9968 5.85697 18.9157M18.143 18.9157C20.0491 17.2214 21.25 14.7509 21.25 12C21.25 6.89137 17.1086 2.75 12 2.75C6.89137 2.75 2.75 6.89137 2.75 12C2.75 14.7509 3.95086 17.2214 5.85697 18.9157M18.143 18.9157C16.5094 20.3679 14.3577 21.25 12 21.25C9.6423 21.25 7.49061 20.3679 5.85697 18.9157" stroke="white" stroke-width="1.5" stroke-linejoin="round"/>
</g>
</svg>
```

- [ ] **Step 2: Write the `IconCoins` SVG** (Figma node `9541:9922`)

```xml
<svg width="24" height="24" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
<g id="IconCoins">
<path d="M14.6766 7.38126C13.686 5.23749 11.5167 3.75 9 3.75C5.54822 3.75 2.75 6.54822 2.75 10C2.75 13.3961 5.45873 16.1596 8.83359 16.2478M21.25 14C21.25 17.4518 18.4518 20.25 15 20.25C12.3406 20.25 10.0691 18.589 9.16641 16.2478C8.89745 15.5503 8.75 14.7924 8.75 14C8.75 10.6039 11.4587 7.84038 14.8336 7.75217C14.8889 7.75073 14.9444 7.75 15 7.75C18.4518 7.75 21.25 10.5482 21.25 14Z" stroke="white" stroke-width="1.5" stroke-linecap="square"/>
</g>
</svg>
```

- [ ] **Step 3: Write both `Contents.json` files**

`IconPeopleCircle.imageset/Contents.json` (identical shape to the existing `IconChecklist.imageset`):

```json
{
  "images" : [
    {
      "filename" : "IconPeopleCircle.svg",
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  },
  "properties" : {
    "preserves-vector-representation" : true,
    "template-rendering-intent" : "template"
  }
}
```

`IconCoins.imageset/Contents.json` — the same, with `"filename" : "IconCoins.svg"`.

- [ ] **Step 4: Add the `Asset` cases**

In `Image+Symbols.swift`, in the `// Icons` group, after `case peopleGear = "IconPeopleGear"`:

```swift
    case peopleCircle = "IconPeopleCircle"
    case coins = "IconCoins"
```

- [ ] **Step 5: Build to confirm the assets compile**

Run: `./Scripts/build.sh`
Expected: BUILD SUCCEEDED. An asset-catalog error here means a malformed `Contents.json` or a filename that does not match.

- [ ] **Step 6: Commit**

```bash
git add FlipcashUI/Sources/FlipcashUI/Assets/UI.xcassets/icons/IconPeopleCircle.imageset \
        FlipcashUI/Sources/FlipcashUI/Assets/UI.xcassets/icons/IconCoins.imageset \
        FlipcashUI/Sources/FlipcashUI/Theme/Image+Symbols.swift
git commit -m "feat(ui): add the profile-checklist row icons"
```

---

## Task 2: Generalize the tutorial card

**Files:**
- Create: `Flipcash/Views/TutorialChecklistCard.swift`
- Modify: `Flipcash/Core/Screens/Main/Home/NewUserTutorial.swift:72-160` (delete `NewUserTutorialView`, add the conformance)
- Modify: `Flipcash/Core/Screens/Main/Home/WalletScreen.swift:483`

This task carries the Figma metric changes, which land on the Wallet's card as
well as the new one. That is intended — it is one component in the design.

- [ ] **Step 1: Create the shared card**

Create `Flipcash/Views/TutorialChecklistCard.swift`:

```swift
//
//  TutorialChecklistCard.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

/// A step in a checklist card: what it says, whether it is done, and the glyph
/// it carries while it is not.
protocol TutorialItemPresentable: Identifiable, Equatable {
    var title: String { get }
    var subtitle: String { get }
    var isCompleted: Bool { get }
    /// The glyph for an unfinished step. A finished one is drawn by the card as
    /// a checkmark, so conformers never describe the completed state.
    var icon: Image { get }
}

/// A titled checklist of tappable steps with a completed count — the Wallet's
/// "Send Your First Tip" and the You tab's "Finish Your Profile" (Figma node
/// 9544:18140). Completed steps show a green check, dim, and stop responding to
/// taps.
struct TutorialChecklistCard<Item: TutorialItemPresentable>: View {

    let title: String
    let items: [Item]
    let onTap: (Item) -> Void

    private var completedCount: Int { items.filter(\.isCompleted).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title)
                    .font(.appBarButton)
                    .foregroundStyle(Color.textMain)
                Spacer()
                Text("\(completedCount)/\(items.count)")
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(16)

            VStack(spacing: 16) {
                ForEach(items) { item in
                    row(item)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.backgroundRow)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.buttonRadius, style: .continuous))
        }
    }

    private func row(_ item: Item) -> some View {
        Button {
            onTap(item)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                icon(item)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.appTextMedium)
                        .foregroundStyle(Color.textMain)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(item.subtitle)
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .opacity(item.isCompleted ? 0.38 : 1)

                Image.system(.chevronRight)
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxHeight: .infinity, alignment: .center)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(item.isCompleted)
    }

    @ViewBuilder private func icon(_ item: Item) -> some View {
        if item.isCompleted {
            Image(systemName: "checkmark.circle.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.Sentiment.positive)
        } else {
            item.icon
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.textSecondary)
        }
    }
}
```

- [ ] **Step 2: Trim `NewUserTutorial.swift` to the Wallet's own types**

Delete everything from `/// The "Send Your First Tip" new-user tutorial...` (line 72) to the end of the file, and add the conformance to `TutorialItem`. The file's `TutorialItem` declaration becomes:

```swift
/// A step in the wallet's new-user tutorial (Figma frame 8966:1516, ported from
/// Android's `TutorialItem`).
enum TutorialItem: TutorialItemPresentable {
    case addMoney(isCompleted: Bool)
    case scanTipCard(isCompleted: Bool)

    var id: String { title }

    var isCompleted: Bool {
        switch self {
        case .addMoney(let done), .scanTipCard(let done): return done
        }
    }

    var title: String {
        switch self {
        case .addMoney:    return "Add Money"
        case .scanTipCard: return "Scan a Tip Card"
        }
    }

    var subtitle: String {
        switch self {
        case .addMoney:    return "Add money to your account"
        case .scanTipCard: return "Give your first tip"
        }
    }

    var icon: Image {
        switch self {
        case .addMoney:    return Image(systemName: "plus.circle")
        case .scanTipCard: return Image("NavScan")
        }
    }
}
```

`NewUserTutorialState` is untouched. Add `import SwiftUI` if it is not already the first import (it is — line 6).

- [ ] **Step 3: Rename the view at the Wallet's call site**

In `WalletScreen.swift` around line 483, change `NewUserTutorialView(` to `TutorialChecklistCard(`. Nothing else in that call changes.

- [ ] **Step 4: Build**

Run: `./Scripts/build.sh`
Expected: BUILD SUCCEEDED. A "cannot infer generic parameter `Item`" error means the call site lost its `items:` argument; a "does not conform to `TutorialItemPresentable`" error means Step 2's conformance is incomplete.

- [ ] **Step 5: Run the existing Wallet tutorial tests to prove nothing regressed**

Run: `./Scripts/test.sh FlipcashTests/NewUserTutorialStateTests`
Expected: PASS, 6 tests. These cover `NewUserTutorialState`, which this task does not touch — they are the regression guard for Step 2's edit.

- [ ] **Step 6: Commit**

```bash
git add Flipcash/Views/TutorialChecklistCard.swift \
        Flipcash/Core/Screens/Main/Home/NewUserTutorial.swift \
        Flipcash/Core/Screens/Main/Home/WalletScreen.swift
git commit -m "refactor(tutorial): share the checklist card between the wallet and the you tab

Generalizes the card over its item type so each screen keeps an exhaustive
switch over its own enum, and matches the metrics in node 9544:18140 — 18pt
title, 6pt panel radius, padding on the panel rather than the rows, and a
no-space count."
```

---

## Task 3: The You tab's checklist state

**Files:**
- Create: `Flipcash/Core/Screens/Main/You/ProfileTutorial.swift`
- Test: `FlipcashTests/ProfileTutorialStateTests.swift`

- [ ] **Step 1: Write the failing test**

Create `FlipcashTests/ProfileTutorialStateTests.swift`:

```swift
//
//  ProfileTutorialStateTests.swift
//  FlipcashTests
//

import Foundation
import Testing
@testable import Flipcash

/// The checklist is derived from the profile rather than from a dismissal flag,
/// so it must stay silent until a profile has loaded and must disappear on its
/// own once both chores are done.
@Suite
@MainActor
struct ProfileTutorialStateTests {

    private static func state(
        hasProfile: Bool = true,
        picture: Bool = false,
        minimumTip: Bool = false
    ) -> ProfileTutorialState {
        ProfileTutorialState(
            hasProfile: hasProfile,
            hasProfilePicture: picture,
            hasMinimumTipAmount: minimumTip
        )
    }

    @Test("The checklist is withheld until a profile has loaded")
    func withheldWithoutProfile() {
        #expect(!Self.state(hasProfile: false).isVisible)
    }

    @Test("The checklist shows while either chore is outstanding")
    func shownWhileIncomplete() {
        #expect(Self.state().isVisible)
        #expect(Self.state(picture: true).isVisible)
        #expect(Self.state(minimumTip: true).isVisible)
    }

    @Test("A finished checklist disappears without needing a dismissal")
    func hiddenWhenComplete() {
        let state = Self.state(picture: true, minimumTip: true)
        #expect(state.isComplete)
        #expect(!state.isVisible)
    }

    @Test("Profile fields drive the step completion the card renders")
    func itemsCarryProfileState() {
        let state = Self.state(picture: true)
        #expect(state.items == [
            .profilePicture(isCompleted: true),
            .minimumTipAmount(isCompleted: false),
        ])
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `./Scripts/test.sh FlipcashTests/ProfileTutorialStateTests`
Expected: FAIL to compile — "cannot find 'ProfileTutorialState' in scope".

- [ ] **Step 3: Write the implementation**

Create `Flipcash/Core/Screens/Main/You/ProfileTutorial.swift`:

```swift
//
//  ProfileTutorial.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// A chore in the You tab's "Finish Your Profile" checklist (Figma node
/// 9544:18140).
enum ProfileTutorialItem: TutorialItemPresentable {
    case profilePicture(isCompleted: Bool)
    case minimumTipAmount(isCompleted: Bool)

    var id: String { title }

    var isCompleted: Bool {
        switch self {
        case .profilePicture(let done), .minimumTipAmount(let done): return done
        }
    }

    var title: String {
        switch self {
        case .profilePicture:   return "Add a profile picture"
        case .minimumTipAmount: return "Set your minimum tip amount"
        }
    }

    var subtitle: String {
        switch self {
        case .profilePicture:   return "Select a photo from your gallery"
        case .minimumTipAmount: return "Decide what size tip matters to you"
        }
    }

    var icon: Image {
        switch self {
        case .profilePicture:   return .asset(.peopleCircle)
        case .minimumTipAmount: return .asset(.coins)
        }
    }
}

/// Whether the You tab draws the profile checklist, and with which chores
/// checked off.
///
/// Both chores are read straight off the profile rather than from a local
/// dismissal flag, so a picture or fee that disappears across a profile refresh
/// puts the card back on its own.
struct ProfileTutorialState: Equatable {

    /// Withholds the card until a profile has loaded, so a session that has not
    /// fetched one yet does not flash an all-incomplete checklist.
    let hasProfile: Bool
    let hasProfilePicture: Bool
    let hasMinimumTipAmount: Bool

    init(hasProfile: Bool, hasProfilePicture: Bool, hasMinimumTipAmount: Bool) {
        self.hasProfile = hasProfile
        self.hasProfilePicture = hasProfilePicture
        self.hasMinimumTipAmount = hasMinimumTipAmount
    }

    init(profile: Profile?) {
        self.init(
            hasProfile: profile != nil,
            hasProfilePicture: profile?.profilePicture != nil,
            hasMinimumTipAmount: profile?.minDmChatInitFee != nil
        )
    }

    var items: [ProfileTutorialItem] {
        [
            .profilePicture(isCompleted: hasProfilePicture),
            .minimumTipAmount(isCompleted: hasMinimumTipAmount),
        ]
    }

    var isComplete: Bool { hasProfilePicture && hasMinimumTipAmount }

    var isVisible: Bool { hasProfile && !isComplete }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `./Scripts/test.sh FlipcashTests/ProfileTutorialStateTests`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add Flipcash/Core/Screens/Main/You/ProfileTutorial.swift \
        FlipcashTests/ProfileTutorialStateTests.swift
git commit -m "feat(you): derive the profile checklist from the profile"
```

---

## Task 4: The `.changeProfilePicture` destination

**Files:**
- Modify: `Flipcash/Core/Navigation/AppRouter+Destination.swift:56, 108-110, 139-140, 186-189`
- Modify: `Flipcash/Core/Navigation/AppRouter+DestinationView.swift:73-74`
- Create: `Flipcash/Core/Screens/Settings/ChangeProfilePictureScreen.swift`
- Test: `FlipcashTests/Navigation/YouTabRoutingTests.swift`

The destination belongs to the settings group, not the Tips group, so
`owningStack` is `.you` — the card pushes onto the You tab's own stack. The
existing `.profilePhoto` case stays on `.tips` for the setup flow.

- [ ] **Step 1: Write the failing test**

Append to `FlipcashTests/Navigation/YouTabRoutingTests.swift`, inside the `struct`, after `changeDisplayName_pushesAndPopsOnYouStack`:

```swift
    @Test("changing the profile picture belongs to the You tab, not the setup flow's stack")
    func changeProfilePicture_ownsTheYouStack() {
        #expect(AppRouter.Destination.changeProfilePicture.owningStack == .you)
        // The setup flow's own photo step keeps its Tips stack.
        #expect(AppRouter.Destination.profilePhoto.owningStack == .tips)
    }

    @Test("changing the profile picture pushes onto the You tab, and saving pops back")
    func changeProfilePicture_pushesAndPopsOnYouStack() {
        let router = AppRouter()
        router.activeTabStack = .you
        router.push(.changeProfilePicture)
        #expect(router[.you] == AppRouter.navigationPath(.changeProfilePicture))

        // What `ProfilePhotoScreen(completion: .back)` runs once the photo uploads.
        router.popTopmost()
        #expect(router[.you].isEmpty)
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `./Scripts/test.sh FlipcashTests/YouTabRoutingTests`
Expected: FAIL to compile — "type 'AppRouter.Destination' has no member 'changeProfilePicture'".

- [ ] **Step 3: Add the destination case**

In `AppRouter+Destination.swift`, four edits.

After `case changeDisplayName` (line 56), add:

```swift
        /// The profile picture on its own, changed from the You tab's checklist.
        /// The full profile-setup flow uses `.profilePhoto`, which carries on to
        /// the tip card; this one returns to the screen that opened it.
        case changeProfilePicture
```

In `owningStack`, add it to the settings list:

```swift
            case .settingsMyAccount, .changeDisplayName, .changeProfilePicture, .username,
                 .settingsAdvancedFeatures,
                 .settingsAdvancedBetaFeatures, .settingsAppSettings, .settingsAccountSelection,
                 .settingsApplicationLogs, .blockedUsers, .accessKey, .withdraw:
                return .you
```

In `description`, after the `changeDisplayName` line:

```swift
            case .changeProfilePicture:         "changeProfilePicture"
```

In `payload`, add it to the nil-returning list:

```swift
                 .settingsMyAccount, .changeDisplayName, .changeProfilePicture,
                 .settingsAdvancedFeatures,
```

- [ ] **Step 4: Create the wrapper screen**

Create `Flipcash/Core/Screens/Settings/ChangeProfilePictureScreen.swift`:

```swift
//
//  ChangeProfilePictureScreen.swift
//  Flipcash
//

import SwiftUI

/// Changing the profile picture on its own, reached from the You tab's
/// "Finish Your Profile" checklist (node 9541:10186). Hosts the profile-setup
/// photo step, which returns here once the photo uploads instead of carrying on
/// to the tip card.
struct ChangeProfilePictureScreen: View {

    /// The photo step reads the name from the environment: profile setup owns
    /// that state at its sheet root. A lone edit has no preceding step, so it
    /// owns the state itself, seeded with the name already on the profile.
    @State private var creationState: ProfileCreationState

    init(currentName: String) {
        let state = ProfileCreationState()
        state.displayName = currentName
        _creationState = State(initialValue: state)
    }

    var body: some View {
        ProfilePhotoScreen(completion: .back)
            .environment(creationState)
    }
}
```

- [ ] **Step 5: Map the destination to the screen**

In `AppRouter+DestinationView.swift`, after the `case .changeDisplayName:` block (lines 73-74):

```swift
        case .changeProfilePicture:
            ChangeProfilePictureScreen(currentName: sessionContainer.session.profile?.displayName ?? "")
```

`ProfilePhotoScreen` has no `Completion` yet, so this does not compile until Step 6 below adds it.

- [ ] **Step 6: Add the completion parameter this task depends on**

Add the enum and the stored property to `ProfilePhotoScreen.swift` now, so this task compiles on its own. Task 5 acts on them; the default keeps the existing setup flow behaving exactly as it does today:

```swift
    /// Where a saved photo leads.
    enum Completion {
        /// Profile setup: on to the tip card the profile was made for.
        case tipcard
        /// A lone edit: back to the screen that opened this one.
        case back
    }

    var completion: Completion = .tipcard
```

Place both immediately after `struct ProfilePhotoScreen: View {`, before the `@Environment` properties.

- [ ] **Step 7: Run the test to verify it passes**

Run: `./Scripts/test.sh FlipcashTests/YouTabRoutingTests`
Expected: PASS, 8 tests.

- [ ] **Step 8: Commit**

```bash
git add Flipcash/Core/Navigation/AppRouter+Destination.swift \
        Flipcash/Core/Navigation/AppRouter+DestinationView.swift \
        Flipcash/Core/Screens/Settings/ChangeProfilePictureScreen.swift \
        Flipcash/Core/Screens/Main/Profile/ProfilePhotoScreen.swift \
        FlipcashTests/Navigation/YouTabRoutingTests.swift
git commit -m "feat(navigation): route changing the profile picture onto the you tab"
```

---

## Task 5: Fork `ProfilePhotoScreen` on its completion

**Files:**
- Modify: `Flipcash/Core/Screens/Main/Profile/ProfilePhotoScreen.swift`

Three changes, all applied to both completions except where the table in the
spec forks them: the `.back` presentation, the Figma metrics from node
`9541:10186`, and `ButtonStateLabel` in place of the bare `ProgressView`.

**This changes the existing setup flow's screen too** — the avatar grows from
150 to 158, the name from `.appDisplaySmall` to `.appDisplayCompact`, and the
button gains a checkmark before it navigates. That is deliberate and matches the
spec.

- [ ] **Step 1: Add the button state and the metric constants**

`Completion` and `var completion` already exist from Task 4 Step 6. Below `@State private var errorDialog: DialogItem?` (line 22), add:

```swift
    /// Drives the submit button: spinner while uploading, then the checkmark the
    /// rest of the app shows on a completed action.
    @State private var buttonState: ButtonState = .normal
```

Replace `private static let avatarSize: CGFloat = 150` with:

```swift
    private static let avatarSize: CGFloat = 158
    private static let plusSize: CGFloat = 64
```

- [ ] **Step 2: Fork the heading and apply the metrics**

Replace the two `Text` views at the top of the `VStack` (the "Upload Your Photo" heading and its subtitle) with:

```swift
                if completion == .tipcard {
                    Text("Upload Your Photo")
                        .font(.appTextLarge)
                        .foregroundStyle(Color.textMain)
                        .padding(.top, 20)

                    Text("This photo will be shown when receiving tips")
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                        .padding(.horizontal, 20)
                }
```

`completion == .tipcard` compiles as written — a payload-free enum is `Equatable` without declaring the conformance, exactly as `ProfileNameScreen.Completion` is today.

Change the `CircleImage` call to use the new constant:

```swift
                    CircleImage(image: state.selectedImage, size: Self.avatarSize, plusSize: Self.plusSize)
```

Change the name's font and its gap:

```swift
                if let name = state.validatedDisplayName {
                    Text(name)
                        .font(.appDisplayCompact)
                        .foregroundStyle(Color.textMain)
                        .lineLimit(1)
                        .padding(.top, 21)
                }
```

- [ ] **Step 3: Fork the button title and adopt `ButtonStateLabel`**

Replace the whole `Button(action: state.beginUpload) { ... }` block with:

```swift
                Button(action: state.beginUpload) {
                    ButtonStateLabel(completion == .tipcard ? "Next" : "Save", state: buttonState)
                }
                .buttonStyle(.filled)
                .disabled(!state.canSubmitPhoto)
                .accessibilityIdentifier("profile-photo-next-button")
                .padding(.bottom, 20)
```

- [ ] **Step 4: Give the `.back` fork a navigation title**

On the outer `Background` view, alongside `.navigationBarTitleDisplayMode(.inline)`, add:

```swift
        .navigationTitle(completion == .tipcard ? "" : "Set Profile Picture")
```

- [ ] **Step 5: Drive the button state and fork the destination**

In `upload()`, replace the body of the `do` block's success path. The whole `do` becomes:

```swift
        buttonState = .loading
        do {
            try await state.uploadPhoto(
                with: SessionProfilePictureUploader(
                    session: sessionContainer.session,
                    flipClient: container.flipClient
                )
            )

            buttonState = .success
            // Same beat onboarding holds its checkmark for, so the confirmation
            // is seen before the screen changes.
            try? await Task.delay(milliseconds: 500)

            guard !Task.isCancelled else { return }

            switch completion {
            case .tipcard:
                // Creation lands on the tipcard — the thing the profile was made
                // for — with the conversation list beneath it as the Tips root.
                router.popToRoot(on: .tips)
                router.push(.tipcard)
            case .back:
                router.popTopmost()
            }
```

Each of the three `catch` blocks gains `buttonState = .normal` as its first statement, so a failed upload returns the button to a retryable state. The `ErrorBlob` catch becomes:

```swift
        } catch let error as ErrorBlob {
            buttonState = .normal
            guard !Task.isCancelled else { return }
            logger.info("Profile picture upload failed", metadata: ["error": "\(error)"])
            ErrorReporting.captureError(error, reason: "Profile picture upload failed")
            errorDialog = .profilePictureFailed(error)
```

Do the same for the `ImageEncoderError` catch and the final `catch`.

- [ ] **Step 6: Build**

Run: `./Scripts/build.sh`
Expected: BUILD SUCCEEDED. A "binary operator '==' cannot be applied" error means `Completion` is missing its `Equatable` conformance from Step 2.

- [ ] **Step 7: Run the routing test again**

Run: `./Scripts/test.sh FlipcashTests/YouTabRoutingTests`
Expected: PASS, 8 tests.

- [ ] **Step 8: Commit**

```bash
git add Flipcash/Core/Screens/Main/Profile/ProfilePhotoScreen.swift
git commit -m "feat(profile): let the photo step return to where it was opened

Adds the Completion fork ProfileNameScreen already has, so changing a picture
from the You tab pops back instead of pushing the tip card, and applies the
metrics in node 9541:10186 — a 158pt avatar, a 30pt name, and the spinner-then-
checkmark button the rest of the app confirms an action with."
```

---

## Task 6: Render the card on the You tab

**Files:**
- Modify: `Flipcash/Core/Screens/Main/You/YouScreen.swift:331-355` (`pageContent`), plus a computed property and a tap handler

- [ ] **Step 1: Add the state and the tap handler**

In the `// MARK: - Content -` section, after `private var profilePicture: ProfilePicture? { profile?.profilePicture }` (line 456):

```swift
    private var profileTutorialState: ProfileTutorialState { .init(profile: profile) }
```

Next to `handleTutorialTap`'s counterpart on the Wallet — that is, in the actions section near `beginUsernameClaim` — add:

```swift
    private func handleProfileTutorialTap(_ item: ProfileTutorialItem) {
        switch item {
        case .profilePicture:
            router.push(.changeProfilePicture)
        case .minimumTipAmount:
            // Stubbed: setting the minimum tip is separate work. The row still
            // renders and counts, and checks itself off if the profile already
            // carries a fee.
            break
        }
    }
```

- [ ] **Step 2: Insert the card into `pageContent`**

Replace the `TipCardLinkRow(url: url).padding(.top, 70)` at the head of the `if displayName != nil` branch with:

```swift
                if profileTutorialState.isVisible {
                    TutorialChecklistCard(
                        title: "Finish Your Profile",
                        items: profileTutorialState.items,
                        onTap: handleProfileTutorialTap
                    )
                    .padding(.top, 70)
                    .accessibilityIdentifier("you-profile-tutorial-card")

                    TipCardLinkRow(url: url)
                        .padding(.top, 19)
                } else {
                    TipCardLinkRow(url: url)
                        .padding(.top, 70)
                }
```

The card takes the 70pt gap the link row holds today, so nothing below it shifts when the card is absent.

- [ ] **Step 3: Build**

Run: `./Scripts/build.sh`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Run both affected suites**

Run: `./Scripts/test.sh FlipcashTests/ProfileTutorialStateTests FlipcashTests/YouTabRoutingTests FlipcashTests/NewUserTutorialStateTests`
Expected: PASS, 18 tests total.

- [ ] **Step 5: Commit**

```bash
git add Flipcash/Core/Screens/Main/You/YouScreen.swift
git commit -m "feat(you): show the Finish Your Profile checklist above the tipcard link

Implements node 9641:16758. The profile-picture row opens the photo step; the
minimum-tip row renders and counts toward the 0/2 but its tap is stubbed until
that flow is built."
```

---

## Task 7: Verify on the simulator

**Files:** none

The checklist's visibility is derived from server state, so it needs a look
rather than only a test.

- [ ] **Step 1: Build and run**

Run: `./Scripts/build.sh`, then launch on the iPhone 17 simulator.

- [ ] **Step 2: Check the You tab against node `9544:18140`**

On a signed-in account with a display name and no profile picture, confirm: the card sits above the tip-card link row, reads "Finish Your Profile" with `0/2` or `1/2` on the right, both rows render their exported icons at 50% white, and the panel corners are visibly tighter than the username card's.

- [ ] **Step 3: Check the row's destination against node `9541:10186`**

Tap "Add a profile picture". Confirm the pushed screen is titled "Set Profile Picture", shows no heading or subtitle, and its button reads "Save". Pick a photo, save, and confirm the button shows a spinner then a checkmark before popping back to the You tab — and that the card now reads `1/2` with the first row checked and dimmed.

- [ ] **Step 4: Check the Wallet card did not regress**

On the Wallet tab, confirm "Send Your First Tip" still renders with both rows, now with the tighter corners and the 16pt gap between rows.

- [ ] **Step 5: Report**

Report what was seen. If anything diverges from the Figma frames, raise it rather than adjusting the design.

---

## Out of scope

- The minimum-tip flow. Its row is a stub that returns without navigating.
- The Figma note "Tip card itself is updated (color, drop shadows, and outlining stroke)", which is a `TipcardView` restyle.
