# Currency Creation Wizard — Multi-Screen Rewrite (Plan C)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the single-view wizard + anchor-preference hero system with a straightforward multi-screen `NavigationStack` flow. Each step is its own `Screen` view pushed/popped natively. A custom top bar (back button + persistent progress bar) lives above the stack. No `matchedGeometryEffect`, no anchor preferences, no hero animations, no custom transitions.

**Why:** Two days of iteration on the hero architecture left us ~95% of the way there but with persistent edge cases: on-device back-nav cancellation glitches hero positions, bill size vs. ColorEditor overflow across device sizes, iOS 18 back-animation divergence from iOS 17. The complexity is not justified for the value of the hero effect. Shipping a clean multi-screen flow now unblocks backend integration.

**Scope guard:** This plan has NO fallback. If something here blocks us, we debug in place rather than pivoting again. The architecture is the simplest possible — there's no further simplification available.

**Reference:**
- `.claude/plans/2026-04-14-hero-anchor-preferences.md` — the hero architecture we're retiring (kept for history)
- `.claude/plans/2026-04-11-hero-animations-findings.md` — historical postmortem of matched geometry attempt
- `.claude/plans/2026-04-13-hero-animation-handoff.md` — historical handoff before hero rewrite
- Commit `38b1394f` — last state of the hero architecture (preserved in git history for reference)

---

## Architecture

### Navigation model

A `NavigationStack` owned by a wrapper view. Step identity is a `CurrencyCreationStep` enum. Push navigation is value-based: `NavigationLink(value: .icon)` or programmatic `path.append(.icon)`. Back navigation is native (system back button, swipe-back).

```swift
enum CurrencyCreationStep: Int, Hashable, CaseIterable {
    case name = 0, icon, description, billCreation, confirmation
}

struct CurrencyCreationFlow: View {
    @Bindable var state: CurrencyCreationState
    @State private var path: [CurrencyCreationStep] = []

    var currentStep: CurrencyCreationStep {
        path.last ?? .name
    }

    var body: some View {
        VStack(spacing: 0) {
            WizardNavigationBar(
                currentStep: currentStep,
                totalSteps: CurrencyCreationStep.allCases.count,
                onBack: { if !path.isEmpty { path.removeLast() } else { dismiss() } }
            )

            NavigationStack(path: $path) {
                CurrencyNameScreen(state: state) {
                    path.append(.icon)
                }
                .navigationDestination(for: CurrencyCreationStep.self) { step in
                    switch step {
                    case .name: CurrencyNameScreen(...) { path.append(.icon) }
                    case .icon: CurrencyIconScreen(...) { path.append(.description) }
                    case .description: CurrencyDescriptionScreen(...) { path.append(.billCreation) }
                    case .billCreation: CurrencyBillCreationScreen(...) { path.append(.confirmation) }
                    case .confirmation: CurrencyConfirmationScreen(...)
                    }
                }
                .toolbar(.hidden, for: .navigationBar)
            }
        }
    }
}
```

### The persistent top bar

`WizardNavigationBar` is a custom top strip rendered ABOVE the `NavigationStack`. It contains:

- **Back button** (leading): chevron.backward. Tapping calls `onBack`, which pops the stack (or dismisses the whole wizard if path is empty).
- **Progress bar** (center): same `CreationProgressBar` we already have, sized for the strip.
- **Optional trailing action**: for `.billCreation` → "Done" that advances (used to be a toolbar item).

Each child screen hides its system navigation bar via `.toolbar(.hidden, for: .navigationBar)`. The only top UI the user sees is our custom strip. The back button is ours; system swipe-back still works because `NavigationStack` handles it.

Progress is derived from `path.count + 1` / total. Animating the bar's value via `.animation(.easeInOut(duration: 0.3), value: currentStep)` gives smooth fill transitions.

### State propagation

`CurrencyCreationState` (existing `@Observable`) stays as the shared source of truth. Each screen takes `@Bindable state` and a `onContinue` closure:

```swift
struct CurrencyNameScreen: View {
    @Bindable var state: CurrencyCreationState
    let onContinue: () -> Void
    // ...
}
```

No `@Namespace`, no `Anchor<CGRect>`, no hero flags.

---

## File Structure

**New files:**
- `Flipcash/Core/Screens/Main/Currency Creation/WizardNavigationBar.swift` — custom top strip (back + progress + optional trailing action).
- `Flipcash/Core/Screens/Main/Currency Creation/CurrencyNameScreen.swift` — name entry step.
- `Flipcash/Core/Screens/Main/Currency Creation/CurrencyIconScreen.swift` — icon upload step.
- `Flipcash/Core/Screens/Main/Currency Creation/CurrencyDescriptionScreen.swift` — description entry step.
- `Flipcash/Core/Screens/Main/Currency Creation/CurrencyBillCreationScreen.swift` — bill + color editor step.
- `Flipcash/Core/Screens/Main/Currency Creation/CurrencyConfirmationScreen.swift` — confirmation + buy button step.

**Modified files:**
- `Flipcash/Core/Screens/Main/Currency Creation/CurrencyCreationScreen.swift` — replaces the wizard entry point with a `CurrencyCreationFlow` wrapper that owns the `NavigationStack` + persistent top bar.

**Deleted files:**
- `Flipcash/Core/Screens/Main/Currency Creation/CurrencyCreationWizardScreen.swift` (the ~540-line single-view wizard)
- `Flipcash/Core/Screens/Main/Currency Creation/CurrencyCreationHeroAnchor.swift`
- `Flipcash/Core/Screens/Main/Currency Creation/CurrencyCreationHeroLayer.swift`
- `FlipcashTests/CurrencyCreation/HeroAnchorKeyTests.swift`

**Recovered content:** the per-step screens roughly match what existed in the codebase before commit `6e5338f6` (the single-view refactor). I'll adapt each one to remove the `namespace: Namespace.ID` parameter and any `matchedGeometryEffect` usage, keeping the layouts and behaviors that worked.

**Unchanged files:**
- `CurrencyCreationSummaryScreen.swift` — the intro screen that links into the wizard. No change required.
- `CurrencyCreationState` (in `CurrencyCreationScreen.swift`) — kept as-is.

---

## Test Strategy

Animation and navigation are visual. The removed `HeroAnchorKeyTests.swift` is no longer relevant — delete it. No new unit tests needed; verification is manual walkthrough of each step (forward + back).

---

## Task 1: Delete the hero architecture

**Files:**
- Delete: `Flipcash/Core/Screens/Main/Currency Creation/CurrencyCreationHeroAnchor.swift`
- Delete: `Flipcash/Core/Screens/Main/Currency Creation/CurrencyCreationHeroLayer.swift`
- Delete: `FlipcashTests/CurrencyCreation/HeroAnchorKeyTests.swift`
- Delete: `Flipcash/Core/Screens/Main/Currency Creation/CurrencyCreationWizardScreen.swift`

- [ ] **Step 1: Remove the files**

```bash
rm "Flipcash/Core/Screens/Main/Currency Creation/CurrencyCreationHeroAnchor.swift"
rm "Flipcash/Core/Screens/Main/Currency Creation/CurrencyCreationHeroLayer.swift"
rm "Flipcash/Core/Screens/Main/Currency Creation/CurrencyCreationWizardScreen.swift"
rm "FlipcashTests/CurrencyCreation/HeroAnchorKeyTests.swift"
rmdir "FlipcashTests/CurrencyCreation" 2>/dev/null || true
```

- [ ] **Step 2: Verify build fails at the wizard entry point**

```bash
xcodebuild build -scheme Flipcash -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | grep -E "error|FAILED" | head -20
```

Expected: errors because `CurrencyCreationScreen.swift` still references `CurrencyCreationWizardScreen`. This is correct — Task 2 fixes it.

---

## Task 2: Add the WizardNavigationBar custom top strip

**Files:**
- Create: `Flipcash/Core/Screens/Main/Currency Creation/WizardNavigationBar.swift`

- [ ] **Step 1: Create the file**

```swift
//
//  WizardNavigationBar.swift
//  Flipcash
//
//  Custom top strip for the currency creation wizard. Lives above the
//  NavigationStack so the progress bar persists across pushes. Each
//  wizard step hides the system navigation bar so only this strip is
//  visible at the top.
//

import SwiftUI
import FlipcashUI

struct WizardNavigationBar: View {
    let currentStep: CurrencyCreationStep
    let totalSteps: Int
    let trailingAction: TrailingAction?
    let onBack: () -> Void

    struct TrailingAction {
        let title: String
        let isEnabled: Bool
        let action: () -> Void
    }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onBack) {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.textMain)
                    .frame(width: 44, height: 44)
            }

            Spacer(minLength: 0)

            CreationProgressBar(
                current: currentStep.rawValue + 1,
                total: totalSteps
            )
            .animation(.easeInOut(duration: 0.3), value: currentStep)

            Spacer(minLength: 0)

            if let trailingAction {
                Button(trailingAction.title, action: trailingAction.action)
                    .disabled(!trailingAction.isEnabled)
                    .foregroundStyle(Color.textMain)
                    .frame(height: 44)
                    .padding(.trailing, 16)
            } else {
                // Reserve symmetric space so progress bar stays centered.
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 8)
    }
}
```

- [ ] **Step 2: Build (still won't fully compile — we're incremental)**

```bash
xcodebuild build -scheme Flipcash -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | grep -E "error|FAILED" | head -20
```

Expected: still errors about `CurrencyCreationFlow` / screen types, but `WizardNavigationBar` itself compiles.

---

## Task 3: Create the five step screens

Each screen is a self-contained `View` that takes `@Bindable state`, an `onContinue` closure, and hides its system navigation bar. None of them use `matchedGeometryEffect`, `@Namespace`, or any hero logic.

**Files:**
- Create: `Flipcash/Core/Screens/Main/Currency Creation/CurrencyNameScreen.swift`
- Create: `Flipcash/Core/Screens/Main/Currency Creation/CurrencyIconScreen.swift`
- Create: `Flipcash/Core/Screens/Main/Currency Creation/CurrencyDescriptionScreen.swift`
- Create: `Flipcash/Core/Screens/Main/Currency Creation/CurrencyBillCreationScreen.swift`
- Create: `Flipcash/Core/Screens/Main/Currency Creation/CurrencyConfirmationScreen.swift`

- [ ] **Step 1: Create `CurrencyNameScreen.swift`**

```swift
//
//  CurrencyNameScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

struct CurrencyNameScreen: View {
    @Bindable var state: CurrencyCreationState
    let onContinue: () -> Void

    @FocusState private var isFocused: Bool

    private let characterLimit = 25

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(alignment: .leading, spacing: 0) {
                Text("What do you want to call\nyour currency?")
                    .font(.appTextLarge)
                    .foregroundStyle(Color.textMain)
                    .padding(.top, 20)

                TextField("Currency Name", text: $state.currencyName)
                    .font(.appDisplayMedium)
                    .foregroundStyle(Color.textMain)
                    .focused($isFocused)
                    .padding(.top, 32)
                    .onChange(of: state.currencyName) { _, newValue in
                        if newValue.count > characterLimit {
                            state.currencyName = String(newValue.prefix(characterLimit))
                        }
                    }

                Spacer()

                Text("\(characterLimit - state.currencyName.count) characters")
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.bottom, 12)

                Button("Next", action: onContinue)
                    .buttonStyle(.filled)
                    .disabled(state.currencyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .padding(.bottom, 20)
            }
            .padding(.horizontal, 20)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { isFocused = true }
    }
}
```

- [ ] **Step 2: Create `CurrencyIconScreen.swift`**

```swift
//
//  CurrencyIconScreen.swift
//  Flipcash
//

import SwiftUI
import UniformTypeIdentifiers
import FlipcashUI

struct CurrencyIconScreen: View {
    @Bindable var state: CurrencyCreationState
    let onContinue: () -> Void

    @State private var isShowingPhotoPicker = false
    @State private var isShowingFilePicker = false

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 0) {
                Text("Upload Currency Icon")
                    .font(.appTextLarge)
                    .foregroundStyle(Color.textMain)
                    .padding(.top, 20)

                Text("Choose an image that represents your currency. It will be displayed as a circular icon.")
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                    .padding(.horizontal, 20)

                Spacer()

                Menu {
                    Button("Photo Library", systemImage: "photo.on.rectangle") {
                        isShowingPhotoPicker = true
                    }
                    Button("Choose File", systemImage: "folder") {
                        isShowingFilePicker = true
                    }
                } label: {
                    UploadCircle(selectedImage: state.selectedImage)
                }
                .menuIndicator(.hidden)

                Text(state.currencyName)
                    .font(.appDisplaySmall)
                    .foregroundStyle(Color.textMain)
                    .lineLimit(1)
                    .padding(.top, 16)

                Spacer()

                Text("500x500 Recommended")
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.bottom, 12)

                Button("Next", action: onContinue)
                    .buttonStyle(.filled)
                    .disabled(state.selectedImage == nil)
                    .padding(.bottom, 20)
            }
            .padding(.horizontal, 20)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $isShowingPhotoPicker) {
            ImagePickerWithEditor { image in
                Task.detached {
                    let compressed = ImageCompressor.compress(image)
                    await MainActor.run { state.selectedImage = compressed }
                }
            }
            .ignoresSafeArea()
        }
        .fileImporter(
            isPresented: $isShowingFilePicker,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first,
                  url.startAccessingSecurityScopedResource() else { return }
            let data = try? Data(contentsOf: url)
            url.stopAccessingSecurityScopedResource()
            guard let data, let image = UIImage(data: data) else { return }
            Task.detached {
                let compressed = ImageCompressor.compress(image)
                await MainActor.run { state.selectedImage = compressed }
            }
        case .failure:
            break
        }
    }
}

// MARK: - UploadCircle

private struct UploadCircle: View {
    let selectedImage: UIImage?

    var body: some View {
        ZStack {
            Circle().fill(Color(white: 0.2))

            if let image = selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "plus")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .frame(width: 150, height: 150)
        .compositingGroup()
        .clipShape(Circle())
    }
}

// MARK: - ImagePickerWithEditor

private struct ImagePickerWithEditor: UIViewControllerRepresentable {
    let onImagePicked: (UIImage) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onImagePicked: onImagePicked)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.allowsEditing = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImagePicked: (UIImage) -> Void

        init(onImagePicked: @escaping (UIImage) -> Void) {
            self.onImagePicked = onImagePicked
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage)
            picker.dismiss(animated: true)
            if let image { onImagePicked(image) }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
```

- [ ] **Step 3: Create `CurrencyDescriptionScreen.swift`**

```swift
//
//  CurrencyDescriptionScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

struct CurrencyDescriptionScreen: View {
    @Bindable var state: CurrencyCreationState
    let onContinue: () -> Void

    @FocusState private var isFocused: Bool

    private let characterLimit = 500

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 12) {
                            CurrencyImageCircle(image: state.selectedImage)
                                .frame(width: 28, height: 28)
                            Text(state.currencyName)
                                .font(.appTextLarge)
                                .foregroundStyle(Color.textMain)
                                .lineLimit(1)
                        }
                        .padding(.top, 20)

                        Text("Provide a description for\nyour currency")
                            .font(.appTextLarge)
                            .foregroundStyle(Color.textMain)
                            .padding(.top, 32)

                        TextField("Description", text: $state.currencyDescription, axis: .vertical)
                            .font(.appTextMedium)
                            .foregroundStyle(Color.textMain)
                            .focused($isFocused)
                            .padding(.top, 16)
                            .onChange(of: state.currencyDescription) { _, newValue in
                                if newValue.count > characterLimit {
                                    state.currencyDescription = String(newValue.prefix(characterLimit))
                                }
                            }

                        Color.clear.frame(height: 100)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .scrollIndicators(.hidden)

                Text("\(characterLimit - state.currencyDescription.count) characters")
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.bottom, 12)

                Button("Next", action: onContinue)
                    .buttonStyle(.filled)
                    .disabled(state.currencyDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .padding(.bottom, 20)
            }
            .padding(.horizontal, 20)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { isFocused = true }
    }
}

private struct CurrencyImageCircle: View {
    let image: UIImage?

    var body: some View {
        ZStack {
            Circle().fill(Color(white: 0.2))
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .clipShape(Circle())
    }
}
```

- [ ] **Step 4: Create `CurrencyBillCreationScreen.swift`**

```swift
//
//  CurrencyBillCreationScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

struct CurrencyBillCreationScreen: View {
    @Bindable var state: CurrencyCreationState
    let onContinue: () -> Void

    // swiftlint:disable:next force_try
    private static let previewFiat = try! Quarks(fiatDecimal: 20, currencyCode: .usd, decimals: 6)

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 0) {
                GeometryReader { geometry in
                    if geometry.size.width > 0, geometry.size.height > 0 {
                        BillView(
                            fiat: Self.previewFiat,
                            data: .placeholder35,
                            canvasSize: geometry.size,
                            backgroundColors: state.backgroundColors
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .padding(.top, 20)

                ColorEditorControl(colors: $state.backgroundColors)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 20)
                    .clipped()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
    }
}
```

The "Done" trailing action for this step is provided by `CurrencyCreationFlow` (it pushes `.confirmation`). The screen itself exposes no continue button — it's driven by the wizard chrome above.

- [ ] **Step 5: Create `CurrencyConfirmationScreen.swift`**

```swift
//
//  CurrencyConfirmationScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

struct CurrencyConfirmationScreen: View {
    @Bindable var state: CurrencyCreationState
    let onBuy: () -> Void

    // swiftlint:disable:next force_try
    private static let previewFiat = try! Quarks(fiatDecimal: 20, currencyCode: .usd, decimals: 6)

    @State private var isShowingFundingSheet = false

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    CurrencyImageCircle(image: state.selectedImage)
                        .frame(width: 28, height: 28)
                    Text(state.currencyName)
                        .font(.appTextLarge)
                        .foregroundStyle(Color.textMain)
                        .lineLimit(1)
                }
                .padding(.top, 20)

                GeometryReader { geometry in
                    if geometry.size.width > 0, geometry.size.height > 0 {
                        BillView(
                            fiat: Self.previewFiat,
                            data: .placeholder35,
                            canvasSize: geometry.size,
                            backgroundColors: state.backgroundColors
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .padding(.top, 32)
                .padding(.horizontal, 20)

                Button("Buy $20 to Create Your Currency") {
                    isShowingFundingSheet = true
                }
                .buttonStyle(.filled)
                .padding(.top, 20)
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 20)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $isShowingFundingSheet) {
            FundingSelectionSheet(
                reserveBalance: nil,
                isCoinbaseAvailable: false,
                onSelectReserves: { isShowingFundingSheet = false },
                onSelectCoinbase: { isShowingFundingSheet = false },
                onSelectPhantom: { isShowingFundingSheet = false },
                onDismiss: { isShowingFundingSheet = false }
            )
        }
    }
}

private struct CurrencyImageCircle: View {
    let image: UIImage?

    var body: some View {
        ZStack {
            Circle().fill(Color(white: 0.2))
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .clipShape(Circle())
    }
}
```

`onBuy` closure is currently a no-op in the wizard wrapper — it's where the backend integration hooks in later.

---

## Task 4: Replace `CurrencyCreationScreen.swift` entry point

**Files:**
- Modify: `Flipcash/Core/Screens/Main/Currency Creation/CurrencyCreationScreen.swift`

- [ ] **Step 1: Replace the contents**

```swift
//
//  CurrencyCreationScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

// MARK: - CreationProgressBar

struct CreationProgressBar: View {
    let current: Int
    let total: Int

    var body: some View {
        ProgressView(value: Double(current), total: Double(total))
            .progressViewStyle(.linear)
            .tint(Color.textMain)
            .frame(width: 140)
    }
}

// MARK: - CurrencyCreationStep

enum CurrencyCreationStep: Int, Hashable, CaseIterable {
    case name = 0
    case icon
    case description
    case billCreation
    case confirmation
}

// MARK: - CurrencyCreationState

@Observable
final class CurrencyCreationState {
    var currencyName: String = ""
    var selectedImage: UIImage?
    var currencyDescription: String = ""
    var backgroundColors: [Color] = [Color(white: 0.1)]
}

// MARK: - CurrencyCreationFlow

/// Root wizard view. Owns the NavigationStack path, renders the
/// persistent WizardNavigationBar above the stack, and registers every
/// step's destination at the root.
struct CurrencyCreationFlow: View {
    @Bindable var state: CurrencyCreationState

    @Environment(\.dismiss) private var dismiss
    @State private var path: [CurrencyCreationStep] = []

    private var currentStep: CurrencyCreationStep {
        path.last ?? .name
    }

    var body: some View {
        VStack(spacing: 0) {
            WizardNavigationBar(
                currentStep: currentStep,
                totalSteps: CurrencyCreationStep.allCases.count,
                trailingAction: trailingAction,
                onBack: handleBack
            )

            NavigationStack(path: $path) {
                CurrencyNameScreen(state: state) {
                    path.append(.icon)
                }
                .navigationDestination(for: CurrencyCreationStep.self) { step in
                    destinationScreen(for: step)
                }
            }
        }
        .background(Color.backgroundMain.ignoresSafeArea())
    }

    @ViewBuilder
    private func destinationScreen(for step: CurrencyCreationStep) -> some View {
        switch step {
        case .name:
            CurrencyNameScreen(state: state) { path.append(.icon) }
        case .icon:
            CurrencyIconScreen(state: state) { path.append(.description) }
        case .description:
            CurrencyDescriptionScreen(state: state) { path.append(.billCreation) }
        case .billCreation:
            CurrencyBillCreationScreen(state: state) { path.append(.confirmation) }
        case .confirmation:
            CurrencyConfirmationScreen(state: state) {
                // Backend integration lands here.
            }
        }
    }

    private var trailingAction: WizardNavigationBar.TrailingAction? {
        switch currentStep {
        case .billCreation:
            WizardNavigationBar.TrailingAction(
                title: "Done",
                isEnabled: true,
                action: { path.append(.confirmation) }
            )
        case .name, .icon, .description, .confirmation:
            nil
        }
    }

    private func handleBack() {
        if path.isEmpty {
            dismiss()
        } else {
            path.removeLast()
        }
    }
}

extension View {
    /// Renders the currency creation wizard. Presents from the currency
    /// discovery screen via `.navigationDestination(for:)`.
    func currencyCreationFlow(state: CurrencyCreationState) -> some View {
        self
    }
}

// MARK: - CurrencyCreationFlowEntry (navigation binding)

/// Exposed so `CurrencyDiscoveryScreen` can push the wizard via a
/// NavigationLink value. The old `CurrencyCreationStep.summary` /
/// `.wizard` cases are no longer needed — the wizard owns its own
/// internal NavigationStack.
enum CurrencyCreationFlowEntry: Hashable {
    case summary
    case flow
}
```

Note: the entry-point naming will need to match what `CurrencyDiscoveryScreen` uses. In Task 5 we update the discovery screen to navigate into this flow via `.flow`. If the existing `CurrencyCreationStep` / `CurrencyCreationFlow` modifier naming elsewhere in the codebase needs to stay, we'll rename on the go.

- [ ] **Step 2: Build**

```bash
xcodebuild build -scheme Flipcash -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | grep -E "error|FAILED" | head -20
```

Expected: errors in the call sites (CurrencyDiscoveryScreen, summary screen) that reference the old flow API. Task 5 fixes them.

---

## Task 5: Update call sites (summary → wizard, discovery → summary)

**Files:**
- Modify: `Flipcash/Core/Screens/Main/Currency Creation/CurrencyCreationSummaryScreen.swift`
- Modify: `Flipcash/Core/Screens/Main/Currency Discovery/CurrencyDiscoveryScreen.swift` (only if needed — compare with existing usage)

- [ ] **Step 1: Inspect current usage**

```bash
rg "CurrencyCreationStep|CurrencyCreationFlow|withCurrencyCreationFlow" Flipcash/
```

Record every match. Plan the minimal change to each call site.

- [ ] **Step 2: Update `CurrencyCreationSummaryScreen` to link into the new flow**

The summary screen currently has `NavigationLink(value: CurrencyCreationStep.wizard)`. With the new design, the wizard owns its own `NavigationStack`, so the summary can push to `.flow` (which renders `CurrencyCreationFlow`). Likely the cleanest: the summary view's "Get Started" button presents the flow as a sheet or pushes onto the outer discovery stack.

Option A: sheet presentation from summary
```swift
@State private var isShowingWizard = false

Button("Get Started") { isShowingWizard = true }
    .sheet(isPresented: $isShowingWizard) {
        CurrencyCreationFlow(state: state)
    }
```

Option B: push onto the outer NavigationStack via `.navigationDestination`
```swift
NavigationLink("Get Started", value: CurrencyCreationFlowEntry.flow)
    .navigationDestination(for: CurrencyCreationFlowEntry.self) { _ in
        CurrencyCreationFlow(state: state)
    }
```

I'll use **Option B** to match the existing pattern and keep the back chevron behavior consistent (pop vs dismiss).

Update `CurrencyCreationSummaryScreen`: change the existing `NavigationLink(value: CurrencyCreationStep.wizard)` to `NavigationLink(value: CurrencyCreationFlowEntry.flow)`. Update any surrounding `.navigationDestination(for: CurrencyCreationStep.self)` to `for: CurrencyCreationFlowEntry.self` where appropriate.

(If it turns out the current code already has a simpler shape, adapt — don't over-engineer.)

- [ ] **Step 3: Build**

```bash
xcodebuild build -scheme Flipcash -destination 'platform=iOS Simulator,name=iPhone 17'
```

Expected: BUILD SUCCEEDED.

---

## Task 6: Visual QA walkthrough

**Files:** none.

- [ ] **Step 1: Launch and walk the full flow**

Navigate: Currency Discovery → Create Your Currency → Get Started → wizard.

Per step, verify:

1. **Name step**
   - Top strip shows back chevron (leading), progress bar at 1/5, no trailing action.
   - TextField focused, keyboard up, placeholder visible.
   - Next button enabled after typing.
   - Typing above 25 chars clamps to 25.
2. **Name → Icon** push
   - Default NavigationStack push slide; no heroes, no custom chrome.
   - Progress bar animates from 1/5 → 2/5.
   - Back chevron now pops to name when tapped.
3. **Icon step**
   - Upload circle tappable; Photo Library / Choose File popover works.
   - Picked image appears in circle.
   - Currency name shown below circle.
   - Next enabled after image pick.
4. **Icon → Description** push; progress → 3/5.
5. **Description step** scrolls, description text works, Next advances.
6. **Description → Bill Creation**; progress → 4/5. Trailing action = "Done".
7. **Bill Creation**: Color editor works, bill reflects colors. "Done" in top strip advances.
8. **Bill Creation → Confirmation**; progress → 5/5. No trailing action.
9. **Confirmation**: hero row visible (name + icon), bill visible, "Buy $20…" opens funding sheet (placeholder).
10. **Back navigation**: tap back chevron on each step — slides back naturally, progress animates down. Swipe-back also works (native NavigationStack).

Specific watch-outs from the prior approach:
- No on-device glitches during cancelled gesture-back.
- No "two bills" or duplicated visuals.
- Keyboard dismissal doesn't shift anything unexpectedly.

- [ ] **Step 2: Stop, report to user, wait for explicit approval**

Do not commit without user "commit" instruction.

---

## Task 7: Commit

**Files:** all changes from Tasks 1–6.

- [ ] **Step 1: Verify user approval**

- [ ] **Step 2: Review diff**

```bash
git status
git diff
```

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
refactor: multi-screen wizard with persistent progress bar

Replaces the single-view anchor-preference hero wizard with a
NavigationStack-based multi-screen flow. Each step is its own Screen
view pushed natively; no heroes, no matchedGeometryEffect, no custom
transitions. A custom WizardNavigationBar lives above the stack with
back chevron + animated progress bar + optional trailing action
("Done" on bill creation). System navigation bar hidden on every
screen.

The hero architecture was functional at ~95% but had persistent edge
cases (on-device cancelled-back glitches, bill size vs ColorEditor
overflow, iOS 18 back-animation divergence). Shipping a simpler
architecture now unblocks backend integration.

Deletes CurrencyCreationWizardScreen.swift, CurrencyCreationHeroAnchor.swift,
CurrencyCreationHeroLayer.swift, and HeroAnchorKeyTests.swift. Historical
plans remain in .claude/plans/ for reference.
EOF
)"
```

- [ ] **Step 4: Verify**

```bash
git log -1 --stat
```

---

## Notes

- **The progress bar does NOT live inside the system toolbar.** It lives in a custom `WizardNavigationBar` strip above the `NavigationStack`. Each screen hides its system nav bar via `.toolbar(.hidden, for: .navigationBar)`.
- **Back navigation is entirely native.** `NavigationStack` handles the push/pop and animations. Our back button calls `path.removeLast()` (or `dismiss()` at the root).
- **Swipe-back gesture** still works because we're using `NavigationStack`. No need for `interactiveDismissDisabled()`.
- **State is shared via `CurrencyCreationState` (`@Observable`).** Every screen takes `@Bindable state`. No coordinator object needed.
- **No `matchedGeometryEffect` anywhere.** The CLAUDE.md pitfall entry about its modifier order stays valid for any future usage; we're just not using it in the wizard.
