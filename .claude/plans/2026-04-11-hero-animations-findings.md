# Hero Animations for Currency Creation Wizard — Findings

Recorded 2026-04-11 after a long debugging session exploring SwiftUI hero
animations (`matchedGeometryEffect`) for the currency creation flow.

## Goal

Build a wizard-style currency creation flow where hero elements (currency
name text, currency icon circle) fly between positions as the user
progresses through steps. Requirements as stated by the user:

- **Sticky progress bar** across all steps.
- **Proper transitions** between screens (can be faked).
- **Name and icon flying** between screens via hero animation.

## Critical Learning: `matchedGeometryEffect` Modifier Order

**`.matchedGeometryEffect` must come BEFORE `.frame` in the modifier
chain.** This is the only case verified through testing. The same rule
MAY apply to `.fixedSize` and `.scaleEffect` but was not confirmed —
moving them around did not measurably change behavior during testing,
suggesting the text cross-fade issues were caused by something else
(likely the inherent conditional-branch cross-fade, see below).

```swift
// ❌ WRONG — silent failure: two separate views fade in/out at their
//    own static positions. No morph. Paul Hudson's hackingwithswift
//    example uses this order and does NOT work on iOS 26.
Rectangle()
    .fill(.red)
    .frame(width: 100, height: 100)
    .matchedGeometryEffect(id: "x", in: ns)

// ✅ RIGHT — matched geometry captures the raw flexible view, then
//    the frame wraps it externally. Morph works.
Rectangle()
    .fill(.red)
    .matchedGeometryEffect(id: "x", in: ns)
    .frame(width: 100, height: 100)
```

Same rule for Text:

```swift
// ❌ WRONG
Text("Hero").font(.largeTitle).scaleEffect(0.7).matchedGeometryEffect(id:in:)

// ✅ RIGHT
Text("Hero").font(.largeTitle).matchedGeometryEffect(id:in:).scaleEffect(0.7)
```

This rule is now in `CLAUDE.md` Common Pitfalls (not yet committed — see
"Current State" below).

## Other Things That Do NOT Work (wasted hours on each)

1. **`.transition(.identity)` on matched views to stop fading.** When
   applied to the PARENT container (the VStack inside an `if` block),
   it kills matched geometry entirely because views need to coexist
   briefly during the animation for interpolation — `.identity` pops
   them in/out instantly, leaving no time window.

2. **Wrapping matched elements in separate `View` structs** (like
   `NameStep`, `IconStep`) with their own `.transition(.opacity)`.
   The struct's transition carries the matched children with it as a
   fade, so you get double-transforms: matched-geometry morph + parent
   fade. Put matched elements inline in the parent's body as direct
   children of the conditional.

3. **Nested `NavigationStack`s** (one in `CurrencyDiscoveryScreen`, one
   in `CurrencyCreationScreen`). Causes the pushed view to animate
   into itself or break back-navigation. Don't nest.

4. **`navigationDestination(for:)` inside a pushed view.** SwiftUI only
   uses destinations declared at the ROOT of the enclosing stack —
   destinations declared on a pushed view are ignored with an error
   message: *"declared earlier on the stack"*. Register all
   destinations at the stack root.

5. **`navigationTransition(.zoom)` (iOS 18+).** Not granular enough —
   it zooms the whole destination view from a source area, not
   specific elements morphing independently.

## Inherent SwiftUI Limitation (not fixable within the conditional-branch pattern)

When `matchedGeometryEffect` is used across `if/else` branches, SwiftUI
creates TWO view instances during the transition (the exiting and
entering views). Both are rendered briefly. The result is an
unavoidable slight cross-fade at the midpoint — even when:

- The matched elements are visually identical.
- `properties: .position` is used (size matched is skipped).
- The parent has no explicit transition.

For Rectangle with same color, this is barely noticeable. For Text with
different fonts across steps, it's very visible: two texts at
different font sizes briefly overlap.

### The escape hatch (not yet tried)

To eliminate the cross-fade entirely, **abandon conditional branches for
hero elements**. Have ONE `Text` and ONE `Rectangle` that are always
present in the view tree, with properties (position, scale, size)
driven by state:

```swift
ZStack {
    // Non-hero content per step (can use conditionals + fade)
    if step == 0 { NameStepBackground() }
    if step == 1 { IconStepBackground() }
    if step == 2 { DescriptionStepBackground() }

    // Hero elements — always present, only properties change
    Rectangle()
        .fill(.red)
        .frame(
            width: boxSize(for: step),
            height: boxSize(for: step)
        )
        .position(boxPosition(for: step, in: geometry))

    Text("Hero")
        .font(.largeTitle)
        .scaleEffect(textScale(for: step))
        .position(textPosition(for: step, in: geometry))
}
```

`withAnimation` interpolates the property changes on a single view
instance. No cross-fade possible because there's literally only one
view. Trade-off: manual positioning math via `GeometryReader`.

**This is the recommended path for the next session.**

## Current State of the Code

### Stashed

All of the prior wizard work is in a git stash:

```
stash@{0}: currency-creation-wizard-wip
```

Contains the full `CurrencyCreationScreen` + `CurrencyCreationFlow`
modifier + `CurrencyCreationState` @Observable class + the wizard
navigation restructure. This was working navigation-wise before the
hero animation exploration began.

### Uncommitted changes (need to be reverted before proceeding)

1. **`Flipcash/Core/FlipcashApp.swift`** — temporarily has
   `HeroAnimationDemo()` as the `WindowGroup` root instead of
   `ContainerScreen`. Must be reverted.

2. **`Flipcash/Core/Screens/Main/Currency Discovery/CurrencyDiscoveryScreen.swift`** —
   has a temporary `.fullScreenCover(isPresented: $isShowingHeroDemo)`
   and a "Hero Animation Demo" button in `CurrencyInfoFooter`. Must be
   reverted.

3. **`Flipcash/Core/Screens/Main/Currency Creation/HeroAnimationDemo.swift`** —
   new file, currently contains a 3-step demo with matched geometry.
   Not part of the real app — should either be deleted or kept as a
   reference for the techniques.

4. **`CLAUDE.md`** — added a Common Pitfalls entry about
   `matchedGeometryEffect` modifier order. Should be kept (already
   good) but not yet committed.

### Committed (on `feat/currency-creation` branch)

Everything up to commit `5c3df3bc` (feat: make description screen
scrollable as text grows). This is the "real" wizard state minus the
hero animation attempts.

## Recommendations for the Next Session

1. **Start with a clean slate.** Revert the temporary `FlipcashApp`
   and `CurrencyDiscoveryScreen` changes. Delete `HeroAnimationDemo.swift`
   or move it to a dedicated debug location.

2. **Pop the stash** to get the wizard work back:
   `git stash pop` (check conflicts with uncommitted `CLAUDE.md`).

3. **Commit the CLAUDE.md pitfall entry separately** so the rule
   survives regardless of what happens to the wizard code.

4. **For the wizard hero animations**, use the single-view approach:
   - Create a `CurrencyCreationWizard` view that is its own NavigationStack
     root (or presented via sheet/fullScreenCover from `CurrencyDiscoveryScreen`).
   - Inside, use a `ZStack` + `GeometryReader`.
   - Hero elements (currency name text, currency icon circle) live
     OUTSIDE the step-specific conditionals, always present.
   - Position, scale, and size driven by `step` via computed
     properties and `withAnimation`.
   - Non-hero content (step titles, buttons, text fields) can use
     conditional branches with normal transitions.

5. **For the sticky progress bar**, declare it ONCE at the wizard's
   root (not in any step's content). It's always present, its value
   animates from state. This solves the "sticky progress bar" problem
   without needing `matchedGeometryEffect`.

6. **Re-introduce step state management** using the `CurrencyCreationState`
   `@Observable` class from the stashed work.

## Files Involved

- `Flipcash/Core/FlipcashApp.swift` — temp root replacement
- `Flipcash/Core/ContainerScreen.swift` — the real root (has
  `.animation(_:value:)` on state changes — not a problem but noted)
- `Flipcash/Core/AppDelegate.swift` — `UIView.setAnimationsEnabled(false)`
  only runs in UI testing mode, no impact
- `Flipcash/Core/Screens/Main/Currency Creation/HeroAnimationDemo.swift` —
  the demo file (current contents have the working modifier order)
- `Flipcash/Core/Screens/Main/Currency Discovery/CurrencyDiscoveryScreen.swift` —
  temp fullScreenCover for accessing the demo
- `CLAUDE.md` — added modifier order pitfall (uncommitted)

## What NOT to retry

- Paul Hudson's hackingwithswift example verbatim — its modifier order
  is WRONG for modern iOS. You'll chase your tail.
- `.transition(.identity)` on matched elements or their parents.
- Nested NavigationStacks.
- `matchedGeometryEffect` overlay pattern with `isSource: false` — too
  complex for this use case.
- `navigationTransition(.zoom)` — not granular enough.
- Changing the `Background` wrapper, `NavigationStack`, or
  `fullScreenCover` thinking they're the bug — none of them were.

## Unresolved Question

**Why does the Text cross-fade look worse than the Rectangle cross-fade?**
Rectangles with the same fill at the same interpolated position look
visually identical; cross-fade is barely noticeable. Text with
different fonts renders at different intrinsic sizes, so even at the
same matched position you see two differently-sized texts briefly.
`scaleEffect` with a shared base font was tried but each conditional
branch has its own scale value hardcoded, so during the transition
they're at different scales anyway.

The single-view approach from the recommendations section would fix
this definitively — one Text, one scale value, no branch duplication.
