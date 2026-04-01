# Currency Creation Flow — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Currency Creation UI flow (screens 1–6) with geometry-matched transitions, stopping before any real RPC/purchase integration.

**Architecture:** Sheet-presented NavigationStack with self-contained screens. Root screen owns shared `@State` and `@Namespace`. Each child screen receives only its required data via `let` / `@Binding`. No shared ViewModel.

**Tech Stack:** SwiftUI, FlipcashUI (BillView, ColorEditorControl, FundingSelectionSheet, InputContainer, CircularLoadingView), NavigationStack with path enum, matchedGeometryEffect.

**Spec:** `.claude/plans/2026-04-01-currency-creation-flow.md`

---

### Task 1: Scaffold root screen, path enum, and entry point

**Files:**
- Create: `Flipcash/Core/Screens/Main/Currency Creation/CurrencyCreationScreen.swift`
- Modify: `Flipcash/Core/Screens/Main/Currency Discovery/CurrencyDiscoveryScreen.swift`

- [ ] **Step 1: Create `CurrencyCreationScreen.swift`**

This file contains the path enum and root screen. All navigation destinations start as placeholders.

```swift
//
//  CurrencyCreationScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

enum CurrencyCreationPath: Hashable {
    case name
    case icon
    case description
    case billCreation
    case confirmation
}

struct CurrencyCreationScreen: View {
    @State private var path: [CurrencyCreationPath] = []
    @State private var currencyName: String = ""
    @State private var selectedIcon: Int = 0
    @State private var currencyDescription: String = ""
    @State private var backgroundColors: [Color] = [Color(white: 0.1)]
    @Namespace private var animation

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack(path: $path) {
            PlaceholderScreen(title: "Summary")
                .navigationDestination(for: CurrencyCreationPath.self) { step in
                    switch step {
                    case .name:
                        PlaceholderScreen(title: "Name")
                    case .icon:
                        PlaceholderScreen(title: "Icon")
                    case .description:
                        PlaceholderScreen(title: "Description")
                    case .billCreation:
                        PlaceholderScreen(title: "Bill Creation")
                    case .confirmation:
                        PlaceholderScreen(title: "Confirmation")
                    }
                }
        }
    }
}

/// Temporary placeholder — replaced screen-by-screen in subsequent tasks.
private struct PlaceholderScreen: View {
    let title: String

    var body: some View {
        Background(color: .backgroundMain) {
            Text(title)
                .font(.appDisplaySmall)
                .foregroundStyle(Color.textMain)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
```

- [ ] **Step 2: Wire up `CurrencyDiscoveryScreen` to present the sheet**

In `CurrencyDiscoveryScreen.swift`, add state and sheet presentation:

```swift
// Add this @State property alongside the existing ones:
@State private var isShowingCurrencyCreation = false
```

Change the "Create Your Own Currency" button action from no-op:

```swift
// Replace:
Button("Create Your Own Currency") {
    // No-op for now
}
.buttonStyle(.filled)

// With:
Button("Create Your Own Currency") {
    isShowingCurrencyCreation = true
}
.buttonStyle(.filled)
```

Add the sheet modifier to the NavigationStack (after the existing `.navigationDestination`):

```swift
.sheet(isPresented: $isShowingCurrencyCreation) {
    CurrencyCreationScreen()
}
```

- [ ] **Step 3: Build to verify**

Run: `xcodebuild build -scheme Flipcash -destination 'generic/platform=iOS' 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add Flipcash/Core/Screens/Main/Currency\ Creation/CurrencyCreationScreen.swift Flipcash/Core/Screens/Main/Currency\ Discovery/CurrencyDiscoveryScreen.swift
git commit -m "feat: scaffold currency creation flow with root screen and entry point"
```

---

### Task 2: Implement Screen 1 — Summary

**Files:**
- Create: `Flipcash/Core/Screens/Main/Currency Creation/CurrencyCreationSummaryScreen.swift`
- Modify: `Flipcash/Core/Screens/Main/Currency Creation/CurrencyCreationScreen.swift` (replace summary placeholder)

- [ ] **Step 1: Create `CurrencyCreationSummaryScreen.swift`**

```swift
//
//  CurrencyCreationSummaryScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

struct CurrencyCreationSummaryScreen: View {

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Create Your Currency")
                    .font(.appDisplaySmall)
                    .foregroundStyle(Color.textMain)
                    .padding(.top, 20)

                Text("Launch your own currency in minutes.\nReady to use right away.")
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.top, 12)

                CreationStepsList()
                    .padding(.top, 30)

                Spacer()

                NavigationLink(value: CurrencyCreationPath.name) {
                    Text("Get Started")
                }
                .buttonStyle(.filled)
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 20)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.textMain)
                }
            }
        }
    }
}

// MARK: - CreationStepsList

private struct CreationStepsList: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepRow(iconName: "textformat", title: "Name", subtitle: "Pick a name for your currency")
            StepRow(iconName: "photo", title: "Icon", subtitle: "Choose an image")
            StepRow(iconName: "pencil.line", title: "Description", subtitle: "Describe your currency")
            StepRow(iconName: "paintbrush.fill", title: "Cash Design", subtitle: "Customize the look")
            StepRow(iconName: "banknote.fill", title: "Purchase $20 USD", subtitle: "Buy the first $20 of your currency", isLast: true)
        }
    }
}

// MARK: - StepRow

private struct StepRow: View {
    let iconName: String
    let title: String
    let subtitle: String
    var isLast: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(white: 0.15))
                    .frame(width: 50, height: 50)
                    .overlay {
                        Image(systemName: iconName)
                            .font(.system(size: 20))
                            .foregroundStyle(Color.textMain)
                    }

                if !isLast {
                    Rectangle()
                        .fill(Color(white: 0.25))
                        .frame(width: 1, height: 30)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textMain)

                Text(subtitle)
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.top, 12)

            Spacer()
        }
    }
}
```

- [ ] **Step 2: Replace summary placeholder in `CurrencyCreationScreen.swift`**

```swift
// Replace:
PlaceholderScreen(title: "Summary")

// With:
CurrencyCreationSummaryScreen()
```

- [ ] **Step 3: Build to verify**

Run: `xcodebuild build -scheme Flipcash -destination 'generic/platform=iOS' 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add Flipcash/Core/Screens/Main/Currency\ Creation/CurrencyCreationSummaryScreen.swift Flipcash/Core/Screens/Main/Currency\ Creation/CurrencyCreationScreen.swift
git commit -m "feat: implement currency creation summary screen"
```

---

### Task 3: Implement Screen 2 — Name Entry

**Files:**
- Create: `Flipcash/Core/Screens/Main/Currency Creation/CurrencyNameScreen.swift`
- Modify: `Flipcash/Core/Screens/Main/Currency Creation/CurrencyCreationScreen.swift` (replace name placeholder)

- [ ] **Step 1: Create `CurrencyNameScreen.swift`**

```swift
//
//  CurrencyNameScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

struct CurrencyNameScreen: View {
    @Binding var currencyName: String
    let namespace: Namespace.ID

    @FocusState private var isFocused: Bool

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Name Your Currency")
                        .font(.appTextLarge)
                        .foregroundStyle(Color.textMain)

                    Text("Pick a name for your currency")
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 20)

                InputContainer(highlighted: isFocused) {
                    TextField("Currency Name", text: $currencyName)
                        .font(.appTextMedium)
                        .foregroundStyle(Color.textMain)
                        .focused($isFocused)
                        .padding(.horizontal, 16)
                }

                Text(currencyName)
                    .font(.appTextLarge)
                    .foregroundStyle(Color.textMain)
                    .matchedGeometryEffect(id: "currencyName", in: namespace)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(currencyName.isEmpty ? 0 : 1)

                Spacer()

                NavigationLink(value: CurrencyCreationPath.icon) {
                    Text("Continue")
                }
                .buttonStyle(.filled)
                .disabled(currencyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 20)
        }
        .navigationTitle("Name")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { isFocused = true }
    }
}
```

- [ ] **Step 2: Replace name placeholder in `CurrencyCreationScreen.swift`**

```swift
// Replace:
case .name:
    PlaceholderScreen(title: "Name")

// With:
case .name:
    CurrencyNameScreen(
        currencyName: $currencyName,
        namespace: animation
    )
```

- [ ] **Step 3: Build to verify**

Run: `xcodebuild build -scheme Flipcash -destination 'generic/platform=iOS' 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add Flipcash/Core/Screens/Main/Currency\ Creation/CurrencyNameScreen.swift Flipcash/Core/Screens/Main/Currency\ Creation/CurrencyCreationScreen.swift
git commit -m "feat: implement currency name entry screen"
```

---

### Task 4: Implement Screen 3 — Icon Selection

**Files:**
- Create: `Flipcash/Core/Screens/Main/Currency Creation/CurrencyIconScreen.swift`
- Modify: `Flipcash/Core/Screens/Main/Currency Creation/CurrencyCreationScreen.swift` (replace icon placeholder)

- [ ] **Step 1: Create `CurrencyIconScreen.swift`**

Icon selection with placeholder grid. Currency name animates into its header position via geometry matching.

```swift
//
//  CurrencyIconScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

/// Placeholder icon names used across the creation flow.
/// The user will replace these with real assets later.
enum CurrencyCreationIcons {
    static let placeholders = ["star.fill", "heart.fill", "bolt.fill", "flame.fill", "leaf.fill", "diamond.fill", "crown.fill", "globe"]

    static func name(for index: Int) -> String {
        placeholders[index % placeholders.count]
    }
}

struct CurrencyIconScreen: View {
    let currencyName: String
    @Binding var selectedIcon: Int
    let namespace: Namespace.ID

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 4)

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 20) {
                // Geometry-matched currency name
                Text(currencyName)
                    .font(.appTextLarge)
                    .foregroundStyle(Color.textMain)
                    .matchedGeometryEffect(id: "currencyName", in: namespace)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 20)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Choose an Icon")
                        .font(.appTextLarge)
                        .foregroundStyle(Color.textMain)

                    Text("Select an image for your currency")
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Placeholder icon grid
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(0..<8, id: \.self) { index in
                        IconTile(
                            index: index,
                            iconName: CurrencyCreationIcons.name(for: index),
                            isSelected: selectedIcon == index,
                            namespace: namespace,
                            onSelect: { selectedIcon = index }
                        )
                    }
                }

                Spacer()

                NavigationLink(value: CurrencyCreationPath.description) {
                    Text("Continue")
                }
                .buttonStyle(.filled)
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 20)
        }
        .navigationTitle("Icon")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - IconTile

private struct IconTile: View {
    let index: Int
    let iconName: String
    let isSelected: Bool
    let namespace: Namespace.ID
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(white: 0.15))
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    Image(systemName: iconName)
                        .font(.system(size: 24))
                        .foregroundStyle(Color.textMain)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white, lineWidth: 2)
                        .opacity(isSelected ? 1 : 0)
                }
        }
        .buttonStyle(.plain)
        .matchedGeometryEffect(
            id: isSelected ? "currencyIcon" : "icon-\(index)",
            in: namespace
        )
    }
}
```

- [ ] **Step 2: Replace icon placeholder in `CurrencyCreationScreen.swift`**

```swift
// Replace:
case .icon:
    PlaceholderScreen(title: "Icon")

// With:
case .icon:
    CurrencyIconScreen(
        currencyName: currencyName,
        selectedIcon: $selectedIcon,
        namespace: animation
    )
```

- [ ] **Step 3: Build to verify**

Run: `xcodebuild build -scheme Flipcash -destination 'generic/platform=iOS' 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add Flipcash/Core/Screens/Main/Currency\ Creation/CurrencyIconScreen.swift Flipcash/Core/Screens/Main/Currency\ Creation/CurrencyCreationScreen.swift
git commit -m "feat: implement currency icon selection screen with geometry matching"
```

---

### Task 5: Implement Screen 4 — Description

**Files:**
- Create: `Flipcash/Core/Screens/Main/Currency Creation/CurrencyDescriptionScreen.swift`
- Modify: `Flipcash/Core/Screens/Main/Currency Creation/CurrencyCreationScreen.swift` (replace description placeholder)

- [ ] **Step 1: Create `CurrencyDescriptionScreen.swift`**

Both currency name and icon animate into their header positions via geometry matching.

```swift
//
//  CurrencyDescriptionScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

struct CurrencyDescriptionScreen: View {
    let currencyName: String
    let selectedIcon: Int
    @Binding var currencyDescription: String
    let namespace: Namespace.ID

    @FocusState private var isFocused: Bool

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 20) {
                // Geometry-matched header
                CurrencyHeader(
                    currencyName: currencyName,
                    iconName: CurrencyCreationIcons.name(for: selectedIcon),
                    namespace: namespace
                )
                .padding(.top, 20)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Describe Your Currency")
                        .font(.appTextLarge)
                        .foregroundStyle(Color.textMain)

                    Text("Tell people what your currency is about")
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Description input
                InputContainer(size: .custom(120)) {
                    TextEditor(text: $currencyDescription)
                        .font(.appTextBody)
                        .foregroundStyle(Color.textMain)
                        .scrollContentBackground(.hidden)
                        .focused($isFocused)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }

                Spacer()

                NavigationLink(value: CurrencyCreationPath.billCreation) {
                    Text("Continue")
                }
                .buttonStyle(.filled)
                .disabled(currencyDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 20)
        }
        .navigationTitle("Description")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { isFocused = true }
    }
}

// MARK: - CurrencyHeader

/// Reusable header showing the currency icon + name with geometry matching.
/// Used on screens 4+ where both icon and name are displayed.
private struct CurrencyHeader: View {
    let currencyName: String
    let iconName: String
    let namespace: Namespace.ID

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(white: 0.15))
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: iconName)
                        .font(.system(size: 18))
                        .foregroundStyle(Color.textMain)
                }
                .matchedGeometryEffect(id: "currencyIcon", in: namespace)

            Text(currencyName)
                .font(.appTextLarge)
                .foregroundStyle(Color.textMain)
                .matchedGeometryEffect(id: "currencyName", in: namespace)

            Spacer()
        }
    }
}
```

- [ ] **Step 2: Replace description placeholder in `CurrencyCreationScreen.swift`**

```swift
// Replace:
case .description:
    PlaceholderScreen(title: "Description")

// With:
case .description:
    CurrencyDescriptionScreen(
        currencyName: currencyName,
        selectedIcon: selectedIcon,
        currencyDescription: $currencyDescription,
        namespace: animation
    )
```

- [ ] **Step 3: Build to verify**

Run: `xcodebuild build -scheme Flipcash -destination 'generic/platform=iOS' 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add Flipcash/Core/Screens/Main/Currency\ Creation/CurrencyDescriptionScreen.swift Flipcash/Core/Screens/Main/Currency\ Creation/CurrencyCreationScreen.swift
git commit -m "feat: implement currency description screen with geometry matching"
```

---

### Task 6: Implement Screen 5 — Bill Creation

**Files:**
- Create: `Flipcash/Core/Screens/Main/Currency Creation/CurrencyBillCreationScreen.swift`
- Modify: `Flipcash/Core/Screens/Main/Currency Creation/CurrencyCreationScreen.swift` (replace billCreation placeholder)

- [ ] **Step 1: Create `CurrencyBillCreationScreen.swift`**

First time the bill appears. Reuses `BillView` and `ColorEditorControl` from the existing `BillEditor` pattern.

```swift
//
//  CurrencyBillCreationScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

struct CurrencyBillCreationScreen: View {
    let currencyName: String
    @Binding var backgroundColors: [Color]

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 0) {
                GeometryReader { geometry in
                    BillView(
                        fiat: try! Quarks(fiatDecimal: 20, currencyCode: .usd, decimals: 6),
                        data: .placeholder35,
                        canvasSize: CGSize(
                            width: geometry.size.width,
                            height: geometry.size.height
                        ),
                        backgroundColors: backgroundColors
                    )
                    .frame(maxWidth: .infinity)
                }
                .padding(.top, 20)

                ColorEditorControl(colors: $backgroundColors)
                    .frame(maxHeight: .infinity)
                    .padding(.bottom, 20)
                    .fixedSize(horizontal: false, vertical: true)

                NavigationLink(value: CurrencyCreationPath.confirmation) {
                    Text("Continue")
                }
                .buttonStyle(.filled)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .navigationTitle(currencyName)
        .navigationBarTitleDisplayMode(.inline)
    }
}
```

- [ ] **Step 2: Replace billCreation placeholder in `CurrencyCreationScreen.swift`**

Add `import FlipcashCore` to the top of the file if not already present.

```swift
// Replace:
case .billCreation:
    PlaceholderScreen(title: "Bill Creation")

// With:
case .billCreation:
    CurrencyBillCreationScreen(
        currencyName: currencyName,
        backgroundColors: $backgroundColors
    )
```

- [ ] **Step 3: Build to verify**

Run: `xcodebuild build -scheme Flipcash -destination 'generic/platform=iOS' 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add Flipcash/Core/Screens/Main/Currency\ Creation/CurrencyBillCreationScreen.swift Flipcash/Core/Screens/Main/Currency\ Creation/CurrencyCreationScreen.swift
git commit -m "feat: implement bill creation screen with color editor"
```

---

### Task 7: Implement Screen 6 — Confirmation

**Files:**
- Create: `Flipcash/Core/Screens/Main/Currency Creation/CurrencyConfirmationScreen.swift`
- Modify: `Flipcash/Core/Screens/Main/Currency Creation/CurrencyCreationScreen.swift` (replace confirmation placeholder)

- [ ] **Step 1: Create `CurrencyConfirmationScreen.swift`**

Final review with bill preview and purchase button. Reuses `FundingSelectionSheet`. Purchase actions are no-ops for now — they just dismiss the sheet. Real RPC integration comes later.

```swift
//
//  CurrencyConfirmationScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

struct CurrencyConfirmationScreen: View {
    let currencyName: String
    let backgroundColors: [Color]

    @State private var isShowingFundingSheet = false

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 0) {
                GeometryReader { geometry in
                    BillView(
                        fiat: try! Quarks(fiatDecimal: 20, currencyCode: .usd, decimals: 6),
                        data: .placeholder35,
                        canvasSize: CGSize(
                            width: geometry.size.width,
                            height: geometry.size.height
                        ),
                        backgroundColors: backgroundColors
                    )
                    .frame(maxWidth: .infinity)
                }
                .padding(.top, 20)

                Spacer()

                Button("Buy $20 to Create Your Currency") {
                    isShowingFundingSheet = true
                }
                .buttonStyle(.filled)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .navigationTitle(currencyName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingFundingSheet) {
            FundingSelectionSheet(
                reserveBalance: nil,
                onSelectReserves: {
                    isShowingFundingSheet = false
                    // TODO: RPC integration
                },
                onSelectPhantom: {
                    isShowingFundingSheet = false
                    // TODO: Phantom integration
                },
                onDismiss: {
                    isShowingFundingSheet = false
                }
            )
            .presentationDetents([.medium])
        }
    }
}
```

- [ ] **Step 2: Replace confirmation placeholder in `CurrencyCreationScreen.swift`**

```swift
// Replace:
case .confirmation:
    PlaceholderScreen(title: "Confirmation")

// With:
case .confirmation:
    CurrencyConfirmationScreen(
        currencyName: currencyName,
        backgroundColors: backgroundColors
    )
```

- [ ] **Step 3: Build to verify**

Run: `xcodebuild build -scheme Flipcash -destination 'generic/platform=iOS' 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add Flipcash/Core/Screens/Main/Currency\ Creation/CurrencyConfirmationScreen.swift Flipcash/Core/Screens/Main/Currency\ Creation/CurrencyCreationScreen.swift
git commit -m "feat: implement currency confirmation screen with funding selection"
```

---

### Task 8: Full build verification and cleanup

**Files:**
- Verify: all `Flipcash/Core/Screens/Main/Currency Creation/*.swift`
- Verify: `Flipcash/Core/Screens/Main/Currency Discovery/CurrencyDiscoveryScreen.swift`

- [ ] **Step 1: Clean build**

Run: `xcodebuild clean build -scheme Flipcash -destination 'generic/platform=iOS' 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 2: Verify no import violations**

Check that no file in `Currency Creation/` imports `CodeServices`:

Run: `grep -r "import CodeServices" Flipcash/Core/Screens/Main/Currency\ Creation/`
Expected: No output (no matches)

- [ ] **Step 3: Remove the `PlaceholderScreen` struct from `CurrencyCreationScreen.swift`**

The `PlaceholderScreen` struct is no longer needed since all screens are implemented. Remove it.

- [ ] **Step 4: Final build**

Run: `xcodebuild build -scheme Flipcash -destination 'generic/platform=iOS' 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
git add Flipcash/Core/Screens/Main/Currency\ Creation/CurrencyCreationScreen.swift
git commit -m "chore: remove PlaceholderScreen from currency creation root"
```

---

## Verification Checkpoint

**STOP HERE.** All 6 screens are built. Before proceeding to processing screen (screen 7) or RPC integration:

1. Run the app and navigate: Currency Discovery → Create Your Own Currency → full flow
2. Verify geometry matching on screens 2 → 3 → 4 (currency name and icon animate between positions)
3. Verify bill preview renders correctly on screens 5 and 6
4. Verify color editor works on screen 5
5. Verify FundingSelectionSheet appears on screen 6
6. Verify back navigation works on all screens
7. Verify sheet dismiss works from screen 1

Report findings before continuing to screen 7 (processing) and RPC integration.
