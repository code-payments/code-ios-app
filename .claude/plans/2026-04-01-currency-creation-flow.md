# Currency Creation Flow — Design Spec

**Date:** 2026-04-01
**Status:** Draft

---

## Overview

A multi-step flow for creating a custom launchpad currency. The user enters a name, selects an icon, writes a description, customizes the bill appearance, confirms, and purchases. The flow is presented as a sheet from `CurrencyDiscoveryScreen` and uses a `NavigationStack` with self-contained screens (no shared ViewModel).

---

## Entry Point

`CurrencyDiscoveryScreen` → "Create Your Own Currency" button (already exists, currently no-op, gated behind `BetaFlags.currencyCreation`) → presents sheet containing `CurrencyCreationScreen`.

---

## Architecture

### Root: `CurrencyCreationScreen`

Owns shared state via `@State` and the `@Namespace` for geometry matching. Each child screen receives only what it needs via `let` / `@Binding`.

```swift
@State private var path: [CurrencyCreationPath] = []
@State private var currencyName: String = ""
@State private var selectedIcon: Int = 0
@State private var currencyDescription: String = ""
@State private var backgroundColors: [Color] = [Color(hex: "#19191A")]  // default
@Namespace private var animation
```

### Path Enum

```swift
enum CurrencyCreationPath: Hashable {
    case name
    case icon
    case description
    case billCreation
    case confirmation
    case processing
}
```

---

## Screens

### Screen 1 — Summary (`CurrencyCreationSummaryScreen`)

NavigationStack root. Purely informational overview of the creation steps.

**Layout:**
- Back button (top left) — dismisses the sheet
- Title: "Create Your Currency" (large, `.appDisplaySmall` or similar)
- Subtitle: "Launch your own currency in minutes. Ready to use right away." (secondary text)
- 5 step items in a vertical list, connected by a thin vertical line:
  1. `Aa` icon — **Name** / "Pick a name for your currency"
  2. Image icon — **Icon** / "Choose an image"
  3. Edit icon — **Description** / "Describe your currency"
  4. Card icon — **Cash Design** / "Customize the look"
  5. Receipt icon — **Purchase $20 USD** / "Buy the first $20 of your currency"
- Each icon inside a dark gray rounded square (~50pt)
- Vertical connector line between icon boxes
- **"Get Started"** button (`.filled` style) at bottom → appends `.name` to path

**Receives:** `@Binding path` (to push `.name`)

**Notes:**
- Icons are placeholders (SF Symbols or simple shapes). User will replace with final icons later.
- No bill preview on this screen.

---

### Screen 2 — Name (`CurrencyNameScreen`)

Text input for the currency name.

**Layout:**
- Navigation bar with back button
- Title area for the currency name input
- Text field with `InputContainer` styling
- Continue/Next button → appends `.icon` to path
- Currency name element uses `matchedGeometryEffect(id: "currencyName", in: namespace)` so it animates into its position on the next screen

**Receives:** `@Binding currencyName`, `let namespace: Namespace.ID`, `@Binding path`

**Future:** Network request to validate currency name availability.

---

### Screen 3 — Icon Selection (`CurrencyIconScreen`)

Pick an icon/image for the currency.

**Layout:**
- Navigation bar with back button
- Currency name displayed at top — geometry matched from screen 2 (`matchedGeometryEffect(id: "currencyName", in: namespace)`)
- Icon selection grid/options
- Continue button → appends `.description` to path
- Selected icon uses `matchedGeometryEffect(id: "currencyIcon", in: namespace)` for the next screen

**Receives:** `let currencyName`, `@Binding selectedIcon`, `let namespace: Namespace.ID`, `@Binding path`

---

### Screen 4 — Description (`CurrencyDescriptionScreen`)

Text area for describing the currency.

**Layout:**
- Navigation bar with back button
- Currency name + icon displayed at top — both geometry matched from screen 3
- Multi-line text area for description
- Continue button → appends `.billCreation` to path

**Receives:** `let currencyName`, `let selectedIcon: Int`, `@Binding currencyDescription`, `let namespace: Namespace.ID`, `@Binding path`

---

### Screen 5 — Bill Creation (`CurrencyBillCreationScreen`)

First time the bill appears. User customizes the bill's visual appearance.

**Layout:**
- Navigation bar with back button and "Done" (or just back)
- `BillView` preview showing the currency name + selected colors
- `ColorEditorControl` (reused from `BillEditor`) for color customization
- Continue/Next button → appends `.confirmation` to path

**Receives:** `let currencyName`, `@Binding backgroundColors`, `@Binding path`

**Reuses:** `BillView`, `ColorEditorControl` from existing `BillEditor`

---

### Screen 6 — Confirmation (`CurrencyConfirmationScreen`)

Final review before purchase.

**Layout:**
- Navigation bar with back button
- Final `BillView` preview with all customizations applied
- "Buy $20 to Create Your Currency" button → shows funding selection sheet
- `FundingSelectionSheet` (reused) appears as partial sheet
- Selecting a funding method → appends `.processing` to path

**Receives:** `let currencyName`, `let backgroundColors: [Color]`, `@Binding path`

**Reuses:** `BillView`, `FundingSelectionSheet`

**State:** `@State private var isShowingFundingSheet: Bool = false`

---

### Screen 7 — Processing (`CurrencyProcessingScreen`)

Transaction in progress / success / failure.

**Layout:** Follows `SwapProcessingScreen` pattern:
- `CircularLoadingView` spinner → `IconCircleCheck` on success → `IconExclamationCircle` on failure
- Title: "Creating [Name]" → "Success"
- Subtitle: "This Will Take a Minute..." → "[Name] Is Live"
- Button: "Notify Me When Complete" (processing) → "Receive My [Name]" (success)
- `navigationBarBackButtonHidden(true)` + `interactiveDismissDisabled(true)`
- On success: dismiss the sheet. The existing scan screen / bill display flow handles showing the received bill (screen 8).

**Receives:** `let currencyName`

**Reuses:** `CircularLoadingView`, `SwapProcessingScreen` layout pattern, `dismissParentContainer` environment, push notification flow from `SwapProcessingScreen`

---

### Screen 8 — Back to Scan Screen

Not part of the Currency Creation NavigationStack. After dismissing the sheet, the existing scan screen bill display mechanism shows the created currency's bill. This is the same flow as receiving a bill via scan or cash link — already implemented via `Session.billState`, `Session.presentationState`, and `ModalCashReceived`.

---

## Geometry Matching

A single `@Namespace` declared in `CurrencyCreationScreen` (the root) is passed to screens 2, 3, and 4.

| Element | Matched Between | ID |
|---------|----------------|-----|
| Currency name | Screens 2 → 3 → 4 | `"currencyName"` |
| Currency icon | Screens 3 → 4 | `"currencyIcon"` |

During NavigationStack push/pop transitions, both source and destination views are in the hierarchy simultaneously, allowing `matchedGeometryEffect` to animate elements between their positions.

---

## File Structure

```
Flipcash/Core/Screens/Main/Currency Creation/
├── CurrencyCreationScreen.swift              (root, path enum, shared state)
├── CurrencyCreationSummaryScreen.swift       (screen 1)
├── CurrencyNameScreen.swift                  (screen 2)
├── CurrencyIconScreen.swift                  (screen 3)
├── CurrencyDescriptionScreen.swift           (screen 4)
├── CurrencyBillCreationScreen.swift          (screen 5)
├── CurrencyConfirmationScreen.swift          (screen 6)
└── CurrencyProcessingScreen.swift            (screen 7)
```

---

## Reuse Summary

| Component | Source | Used In |
|-----------|--------|---------|
| `BillView` | `FlipcashUI` | Screens 5, 6 |
| `ColorEditorControl` | `BillEditor` | Screen 5 |
| `FundingSelectionSheet` | `Currency Info` | Screen 6 |
| `CircularLoadingView` | `FlipcashUI` | Screen 7 |
| `IconCircleCheck` image | Assets | Screen 7 |
| `SwapProcessingScreen` pattern | Currency Swap | Screen 7 layout |
| `dismissParentContainer` env | Environment | Screen 7 |
| `InputContainer` | `FlipcashUI` | Screens 2, 4 |
| Bill display on scan screen | `Session.billState` | Screen 8 (existing) |

---

## Scope & Incremental Build

Build screens incrementally, getting approval at each checkpoint:

1. **Phase 1:** Root + Screen 1 (summary) + Screen 2 (name) — basic NavigationStack flow
2. **Phase 2:** Screen 3 (icon) + Screen 4 (description) — geometry matching
3. **Phase 3:** Screen 5 (bill creation) + Screen 6 (confirmation) — bill preview + payment sheet
4. **Phase 4:** Screen 7 (processing) — reuse SwapProcessingScreen pattern
5. **Phase 5:** Screen 8 integration — wire up to existing scan screen bill display

Network requests (name validation, actual currency creation RPC) are deferred — screens are built with placeholder async logic first.
