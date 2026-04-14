# Hero Animation Handoff — What the Next Session Needs to Know

Recorded 2026-04-13 after a long session that made progress but hit a wall on hero positioning.

## CRITICAL: Fix Root Causes, Never Patch Symptoms

This session repeatedly violated the user's most important rule: **find and fix root causes, don't paper over symptoms.** Every hack — `DispatchQueue.main.async` delays, `.animation(nil, value:)`, hardcoded pixel offsets, separate boolean state flags timed to animation durations — was a symptom patch that created new problems.

The two root causes are clear:
1. **Keyboard avoidance shifts the hero's coordinate space.** Root fix: put heroes in a coordinate space that doesn't shift with the keyboard.
2. **AnyLayout ties circle and name positions together.** Root fix: position them independently with layout-driven coordinates (anchor preferences), not grouped in a shared container.

Do NOT reach for timing hacks, animation suppressors, or hardcoded values. If the architecture doesn't support the behavior, change the architecture.

## Current State

**Branch:** `feat/currency-creation`
**Last clean commit:** `93c5ef7a` — slide transitions, keyboard dismiss fix, back button
**Stash:** `hero-independent-positioning-wip` — broken attempt at independent positioning, DO NOT POP

The committed code at `93c5ef7a` uses **AnyLayout** (VStack ↔ HStack) to group the circle and name as children. This mostly works but has two unsolved problems.

## What Works (at commit 93c5ef7a)

- Single-view wizard with step-driven state (no NavigationStack for internal steps)
- Step content slides left/right with direction-aware transitions
- Hero name text + icon circle morph between icon ↔ description ↔ confirmation via AnyLayout
- Description step scrolls (GeometryReader binding tracks offset, hero moves with it)
- Hero hidden on billCreation, "Done" button in toolbar
- Progress bar animates in toolbar
- Sticky bottom bar with single-identity Next button (no cross-fade)
- `.clipped()` on ZStack for toolbar-under effect
- `.interactiveDismissDisabled()` prevents sheet swipe
- Back button with `goBack()`, direction-aware slide transitions
- TextField ↔ hero Text swap on name step using `heroNameRevealed` flag + `.transition(.identity)`

## The Two Unsolved Problems

### 1. Keyboard position jump (name → icon transition)

**Root cause:** SwiftUI keyboard avoidance shifts the entire GeometryReader up when the keyboard is visible. The hero elements are positioned relative to the GeometryReader. When the keyboard dismisses (as part of transitioning away from the name step), the GeometryReader shifts back down by ~300pt. The hero's starting position in screen coordinates doesn't match where the TextField was visually.

**What was tried:**
- `DispatchQueue.main.async` to defer animation after keyboard dismiss — partial fix, the keyboard hasn't fully settled in one run loop tick
- `.ignoresSafeArea(.keyboard)` on the whole ZStack — fixes hero position but breaks the bottom bar (Next button goes behind keyboard)
- `.ignoresSafeArea(.keyboard)` on an overlay containing just the heroes — overlay sizing/positioning broke, heroes ended up at wrong positions
- `.ignoresSafeArea(.keyboard)` on individual hero views as direct ZStack children — untested at stash time, may or may not work
- Separate `@State heroGroupVisible` flags set outside `withAnimation` — instant hide/show but doesn't solve the position mismatch

**The correct fix (not yet implemented):** The hero overlay needs to be in a coordinate space that does NOT shift with the keyboard, while the step content + bottom bar remain in a keyboard-aware coordinate space. This requires either:
- A separate `UIHostingController` / `UIViewRepresentable` layer for the heroes that opts out of keyboard avoidance
- Or: restructure so the heroes use a coordinate space anchored to the window/screen, not the GeometryReader
- Or: capture the TextField's screen-space position BEFORE dismissing the keyboard, then position the hero at that captured position

### 2. Circle flies to wrong position (name ↔ icon transition)

**Root cause:** The circle and name are children of the same AnyLayout VStack. The VStack's offset changes between name step (93pt) and icon step (h\*0.28). ALL children move together. The circle flies from the icon center to the name-step offset and back, which looks wrong — the circle should grow/shrink in place at the icon center.

**What was tried:**
- `.animation(nil, value: step == .name)` on the circle — kills ALL animation on the circle (size too), making it pop in/out with zero animation
- Independent positioning (separate `.offset()` per element, no AnyLayout) — conceptually correct but the implementation had bugs (overlay sizing, `.ignoresSafeArea` placement) and hardcoded offsets that don't scale across device sizes

**The correct fix:** Separate the circle and name into independently positioned elements. Each needs its own offset per step. But offsets must be **layout-driven** (from anchor preferences or geometry readers), not hardcoded pixel values. The approach:

1. Each step content places invisible placeholder views where heroes should land
2. Placeholders report their bounds via `PreferenceKey` (anchor preferences)
3. Heroes in a keyboard-ignoring layer read those bounds and position themselves
4. When step changes, new anchors → heroes animate to new positions

This avoids hardcoded offsets entirely — positions come from the actual layout. It also handles device size differences automatically.

## Desired Behavior (from the user)

### Name step → Icon step (forward)
- TextField hides instantly (`.transition(.identity)`)
- Name text flies from TextField position to below the circle on icon step
- Circle grows from 0 to 150pt **in place** at the icon center (no flying)
- Icon step content slides in from the right

### Icon step → Name step (back)
- Name text flies back to TextField position
- Circle shrinks in place (no flying)
- Name step content slides in from the left
- After animation settles, `heroNameRevealed = false` → TextField takes over

### Icon step → Description step (forward)
- Both circle and name fly up to header position (left-aligned HStack)
- Description content slides in from right
- Hero scrolls with description ScrollView content

### Description step → Icon step (back)
- Both circle and name fly back to center
- Description content slides out to right

### Bill creation
- Heroes hidden, "Done" in toolbar, no bottom bar

### Confirmation
- Heroes visible, centered

## Files

- `CurrencyCreationWizardScreen.swift` — the entire wizard (all hero logic, step content, bottom bar)
- `CurrencyCreationScreen.swift` — `CurrencyCreationState`, `CurrencyCreationStep`, `CurrencyCreationFlow` modifier
- `CurrencyCreationSummaryScreen.swift` — intro screen before wizard

## Key Architectural Decisions Already Made

1. **Single view, not NavigationStack** — wizard uses `@State step` not navigation pushes
2. **Hero elements always in the view tree** — no conditional insertion/removal for heroes
3. **Step content in conditional branches with slide transitions** — non-hero content uses `if step == .foo { ... }.transition(slideTransition)`
4. **TextField/Text swap for name step** — `heroNameRevealed` flag controls which is visible; TextField uses `.transition(.identity)` for instant swap
5. **Description scroll tracking** — GeometryReader binding reports ScrollView offset, applied to hero Y position
6. **`.clipped()` on main ZStack** — heroes clip under toolbar when scrolling

## What NOT to Retry

- AnyLayout for grouping circle + name (ties their positions together)
- Hardcoded pixel offsets for hero positions (device-dependent)
- `.position()` modifier on heroes (causes views to consume all available space, breaks layout)
- `.ignoresSafeArea(.keyboard)` on the whole ZStack or an overlay wrapping heroes (breaks bottom bar or overlay sizing)
- `.animation(nil, value:)` on the circle (kills size animation too)
- Setting `heroNameRevealed` inside `withAnimation` (causes fade instead of instant swap)
- `DispatchQueue.main.async` with zero delay for keyboard settle (one tick isn't enough)
