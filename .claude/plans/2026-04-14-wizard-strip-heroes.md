# Currency Creation Wizard — Strip Heroes (Option D)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep the single-view wizard structure but rip out everything hero-related — anchor preferences, `HeroLayer`, `menuHidden`/`heroNameRevealed`/`direction` flags, `withAnimation` completion handlers. Each step's content lives inline in the wizard file with default step-change transitions. The persistent toolbar (back button + progress bar) stays because it's one screen with one toolbar.

**Why this instead of Plan C:** Option A (sheet + NavigationStack) works but changes UX (sheet presentation). Option C (per-screen progress bar in NavigationStack) has visible flicker on push/pop. Option D preserves the current UX (pushed wizard screen) without the complexity that caused glitches. The hero morphing was the source of:
- iOS 18 back-animation oddness (direction-aware slide + completion handlers racing the system animator)
- On-device cancelled-back glitches (state coordination between `heroNameRevealed`, `menuHidden`, `direction`, and the spring)
- Bill sizing hassles (anchor rects vs. overlay canvasSize mismatch)

Remove all of that. State-driven step switch with default transitions. Done.

**Scope guard:** None needed — this plan only removes code; there's nothing to architecturally regress into.

**Reference:**
- `.claude/plans/2026-04-14-hero-anchor-preferences.md` — the hero architecture we're retiring (kept for history)
- Commit `38b1394f` — last state of the hero architecture (in git history for reference)

---

## Architecture

### The wizard

Single `CurrencyCreationWizardScreen` view. `@State step: WizardStep` drives which content renders:

```swift
struct CurrencyCreationWizardScreen: View {
    @Bindable var state: CurrencyCreationState
    @Environment(\.dismiss) private var dismiss
    @State private var step: WizardStep = .name
    @FocusState private var focusedField: Field?

    // ... sheet/picker state flags as before

    var body: some View {
        Background(color: .backgroundMain) {
            ZStack {
                switch step {
                case .name: NameStep(state: state, focusedField: $focusedField, onNext: advance)
                case .icon: IconStep(state: state, onPhotoPicker: ..., onFilePicker: ..., onNext: advance)
                case .description: DescriptionStep(state: state, focusedField: $focusedField, onNext: advance)
                case .billCreation: BillCreationStep(state: state, onDone: advance)
                case .confirmation: ConfirmationStep(state: state, onBuy: ...)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: goBack) {
                    Image(systemName: "chevron.backward")
                        .foregroundStyle(Color.textMain)
                }
            }
            ToolbarItem(placement: .principal) {
                CreationProgressBar(current: step.rawValue + 1, total: WizardStep.allCases.count)
            }
        }
        .navigationBarBackButtonHidden(true)
        // ... existing pickers, funding sheet, onAppear focus
    }

    private func advance() {
        guard let next = step.next else { return }
        withAnimation(.easeInOut(duration: 0.3)) { step = next }
    }

    private func goBack() {
        if let previous = step.previous {
            withAnimation(.easeInOut(duration: 0.3)) { step = previous }
        } else {
            dismiss()
        }
    }
}
```

### Step transitions

Default fade crossfade (`.transition(.opacity)` on each step's content, applied inside the switch). No direction tracking, no slide, no completion handlers. Simplest possible.

If the crossfade feels abrupt, we can upgrade to `.transition(.move(edge: .trailing))` — but direction-aware slide is what caused the iOS 18 and cancellation issues, so we avoid it unless necessary.

### Per-step content

Each step is its own private struct inside the wizard file, owning its layout:

- **`NameStep`** — "What do you want to call" heading + `TextField` + Next button.
- **`IconStep`** — heading + subtitle + `Menu` wrapping the image circle + currency name text + Next button.
- **`DescriptionStep`** — header row (small circle + name) inside a ScrollView + "Provide a description" heading + `TextField` + Next button.
- **`BillCreationStep`** — `BillView` filling top area + `ColorEditorControl` at bottom. "Done" is the trailing toolbar item (handled by the wizard, not the step).
- **`ConfirmationStep`** — header row (small circle + name) + `BillView` centered + "Buy $20 to Create Your Currency" button.

No shared heroes. No anchors. Each step owns its own circle/name/bill rendering. The "Currency Name" text on icon/description/confirmation steps is just a `Text(state.currencyName)` — it doesn't animate between positions.

### Persistent toolbar

`ToolbarItem(placement: .principal)` with `CreationProgressBar` persists because the wizard is a single view with a single toolbar. The value animates via `withAnimation` when `step` changes. No flicker — we validated the opposite behavior (flicker) requires multiple screens in a NavigationStack.

Back button (`ToolbarItem(placement: .topBarLeading)`) is always visible. On `.name`, it dismisses the wizard (pops the outer NavigationStack). On other steps, it decrements `step`.

### State flags we're removing

- `direction: Direction` — no more direction-aware transitions
- `heroNameRevealed: Bool` — no more TextField ↔ hero Text handoff
- `menuHidden: Bool` — no more Menu ↔ overlay HeroCircle handoff
- `@Namespace billNamespace` — no more matchedGeometryEffect
- Any `withAnimation(_:completion:)` — simplified to plain `withAnimation`

---

## File Structure

**Deleted files:**
- `Flipcash/Core/Screens/Main/Currency Creation/CurrencyCreationHeroAnchor.swift`
- `Flipcash/Core/Screens/Main/Currency Creation/CurrencyCreationHeroLayer.swift`
- `FlipcashTests/CurrencyCreation/HeroAnchorKeyTests.swift` (plus the empty `CurrencyCreation/` directory)

**Rewritten file:**
- `Flipcash/Core/Screens/Main/Currency Creation/CurrencyCreationWizardScreen.swift` — full rewrite, ~350 lines. Replaces the three-layer architecture with a single `switch step` ZStack.

**Unchanged files:**
- `CurrencyCreationScreen.swift` (registers the wizard destination on the outer stack — already correct)
- `CurrencyCreationSummaryScreen.swift` (pushes `.wizard` via `NavigationLink`)
- `CurrencyDiscoveryScreen.swift` (applies `.withCurrencyCreationFlow(state:)`)

---

## Test Strategy

Visual. The removed `HeroAnchorKeyTests.swift` is no longer relevant — deleted. No new unit tests. Manual walkthrough of each step forward + back.

---

## Task 1: Delete the hero architecture

**Files:**
- Delete: `Flipcash/Core/Screens/Main/Currency Creation/CurrencyCreationHeroAnchor.swift`
- Delete: `Flipcash/Core/Screens/Main/Currency Creation/CurrencyCreationHeroLayer.swift`
- Delete: `FlipcashTests/CurrencyCreation/HeroAnchorKeyTests.swift`
- Delete: `FlipcashTests/CurrencyCreation/` (empty directory)

- [ ] **Step 1: Remove the files**

```bash
rm "Flipcash/Core/Screens/Main/Currency Creation/CurrencyCreationHeroAnchor.swift"
rm "Flipcash/Core/Screens/Main/Currency Creation/CurrencyCreationHeroLayer.swift"
rm "FlipcashTests/CurrencyCreation/HeroAnchorKeyTests.swift"
rmdir "FlipcashTests/CurrencyCreation" 2>/dev/null || true
```

- [ ] **Step 2: Verify build fails**

```bash
xcodebuild build -scheme Flipcash -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | grep -E "error|FAILED" | head -20
```

Expected: errors in `CurrencyCreationWizardScreen.swift` because it imports / uses `HeroAnchorKey`, `HeroLayer`, etc. Task 2 fixes this.

---

## Task 2: Rewrite `CurrencyCreationWizardScreen.swift`

**Files:**
- Modify: `Flipcash/Core/Screens/Main/Currency Creation/CurrencyCreationWizardScreen.swift` (full rewrite)

- [ ] **Step 1: Replace the entire file with the following**

```swift
//
//  CurrencyCreationWizardScreen.swift
//  Flipcash
//
//  Single-view wizard. @State step drives which content renders.
//  No heroes, no anchor preferences, no overlay. Each step's content
//  is a private struct below that owns its own circle, name, bill,
//  etc. The persistent top toolbar (back + progress) is possible
//  because this is one screen with one toolbar.
//

import SwiftUI
import UniformTypeIdentifiers
import FlipcashCore
import FlipcashUI

// MARK: - CurrencyCreationWizardScreen

struct CurrencyCreationWizardScreen: View {
    @Bindable var state: CurrencyCreationState

    @Environment(\.dismiss) private var dismiss

    @State private var step: WizardStep = .name
    @FocusState private var focusedField: Field?

    @State private var isShowingPhotoPicker = false
    @State private var isShowingFilePicker = false
    @State private var isShowingFundingSheet = false

    static let nameCharLimit = 25
    static let descriptionCharLimit = 500
    static let heroCircleSize: CGFloat = 150

    // swiftlint:disable:next force_try
    private static let previewFiat = try! Quarks(fiatDecimal: 20, currencyCode: .usd, decimals: 6)

    enum Field: Hashable {
        case name
        case description
    }

    enum WizardStep: Int, CaseIterable {
        case name = 0, icon, description, billCreation, confirmation

        var next: WizardStep? { WizardStep(rawValue: rawValue + 1) }
        var previous: WizardStep? { WizardStep(rawValue: rawValue - 1) }
    }

    var body: some View {
        Background(color: .backgroundMain) {
            ZStack {
                switch step {
                case .name:
                    NameStep(
                        state: state,
                        focusedField: $focusedField,
                        characterLimit: Self.nameCharLimit,
                        onNext: advance
                    )
                    .transition(.opacity)

                case .icon:
                    IconStep(
                        state: state,
                        onPhotoPicker: { isShowingPhotoPicker = true },
                        onFilePicker: { isShowingFilePicker = true },
                        onNext: advance
                    )
                    .transition(.opacity)

                case .description:
                    DescriptionStep(
                        state: state,
                        focusedField: $focusedField,
                        characterLimit: Self.descriptionCharLimit,
                        onNext: advance
                    )
                    .transition(.opacity)

                case .billCreation:
                    BillCreationStep(
                        state: state,
                        previewFiat: Self.previewFiat
                    )
                    .transition(.opacity)

                case .confirmation:
                    ConfirmationStep(
                        state: state,
                        previewFiat: Self.previewFiat,
                        onBuy: { isShowingFundingSheet = true }
                    )
                    .transition(.opacity)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .interactiveDismissDisabled()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: goBack) {
                    Image(systemName: "chevron.backward")
                        .foregroundStyle(Color.textMain)
                }
            }
            ToolbarItem(placement: .principal) {
                CreationProgressBar(
                    current: step.rawValue + 1,
                    total: WizardStep.allCases.count
                )
            }
            if step == .billCreation {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: advance)
                }
            }
        }
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
        .onAppear {
            if step == .name { focusedField = .name }
        }
        .onChange(of: step) { _, newStep in
            switch newStep {
            case .name: focusedField = .name
            case .description: focusedField = .description
            case .icon, .billCreation, .confirmation: focusedField = nil
            }
        }
    }

    // MARK: - Navigation

    private func advance() {
        guard let next = step.next else { return }
        withAnimation(.easeInOut(duration: 0.3)) { step = next }
    }

    private func goBack() {
        if let previous = step.previous {
            withAnimation(.easeInOut(duration: 0.3)) { step = previous }
        } else {
            dismiss()
        }
    }

    // MARK: - File Import

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

// MARK: - NameStep

private struct NameStep: View {
    @Bindable var state: CurrencyCreationState
    @FocusState.Binding var focusedField: CurrencyCreationWizardScreen.Field?
    let characterLimit: Int
    let onNext: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("What do you want to call\nyour currency?")
                .font(.appTextLarge)
                .foregroundStyle(Color.textMain)
                .padding(.top, 20)

            TextField("Currency Name", text: $state.currencyName)
                .font(.appDisplayMedium)
                .foregroundStyle(Color.textMain)
                .focused($focusedField, equals: .name)
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 12)

            Button("Next", action: onNext)
                .buttonStyle(.filled)
                .disabled(state.currencyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.bottom, 20)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - IconStep

private struct IconStep: View {
    @Bindable var state: CurrencyCreationState
    let onPhotoPicker: () -> Void
    let onFilePicker: () -> Void
    let onNext: () -> Void

    var body: some View {
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
                Button("Photo Library", systemImage: "photo.on.rectangle") { onPhotoPicker() }
                Button("Choose File", systemImage: "folder") { onFilePicker() }
            } label: {
                CircleImage(
                    image: state.selectedImage,
                    size: CurrencyCreationWizardScreen.heroCircleSize,
                    plusSize: 40
                )
            }
            .menuIndicator(.hidden)

            if !state.currencyName.isEmpty {
                Text(state.currencyName)
                    .font(.appDisplaySmall)
                    .foregroundStyle(Color.textMain)
                    .lineLimit(1)
                    .padding(.top, 16)
            }

            Spacer()

            Text("500x500 Recommended")
                .font(.appTextSmall)
                .foregroundStyle(Color.textSecondary)
                .padding(.bottom, 12)

            Button("Next", action: onNext)
                .buttonStyle(.filled)
                .disabled(state.selectedImage == nil)
                .padding(.bottom, 20)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - DescriptionStep

private struct DescriptionStep: View {
    @Bindable var state: CurrencyCreationState
    @FocusState.Binding var focusedField: CurrencyCreationWizardScreen.Field?
    let characterLimit: Int
    let onNext: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 12) {
                        CircleImage(image: state.selectedImage, size: 28, plusSize: 14)
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
                        .focused($focusedField, equals: .description)
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 12)

            Button("Next", action: onNext)
                .buttonStyle(.filled)
                .disabled(state.currencyDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.bottom, 20)
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - BillCreationStep

private struct BillCreationStep: View {
    @Bindable var state: CurrencyCreationState
    let previewFiat: Quarks

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                if geometry.size.width > 0, geometry.size.height > 0 {
                    BillView(
                        fiat: previewFiat,
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
}

// MARK: - ConfirmationStep

private struct ConfirmationStep: View {
    @Bindable var state: CurrencyCreationState
    let previewFiat: Quarks
    let onBuy: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                CircleImage(image: state.selectedImage, size: 28, plusSize: 14)
                Text(state.currencyName)
                    .font(.appTextLarge)
                    .foregroundStyle(Color.textMain)
                    .lineLimit(1)
            }
            .padding(.top, 20)

            GeometryReader { geometry in
                if geometry.size.width > 0, geometry.size.height > 0 {
                    BillView(
                        fiat: previewFiat,
                        data: .placeholder35,
                        canvasSize: geometry.size,
                        backgroundColors: state.backgroundColors
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(.top, 32)
            .padding(.horizontal, 20)

            Button("Buy $20 to Create Your Currency", action: onBuy)
                .buttonStyle(.filled)
                .padding(.top, 20)
                .padding(.bottom, 20)
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - CircleImage

/// Shared small-medium circle used by NameStep/IconStep/DescriptionStep/
/// ConfirmationStep to display the selected image (or a plus icon as
/// placeholder) at different sizes.
private struct CircleImage: View {
    let image: UIImage?
    let size: CGFloat
    let plusSize: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(Color(white: 0.2))

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "plus")
                    .font(.system(size: plusSize, weight: .light))
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .frame(width: size, height: size)
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

- [ ] **Step 2: Build**

```bash
xcodebuild build -scheme Flipcash -destination 'platform=iOS Simulator,name=iPhone 17'
```

Expected: BUILD SUCCEEDED.

---

## Task 3: Visual QA

**Files:** none.

- [ ] **Step 1: Walk the forward path**

Navigate: Currencies → Create Your Own Currency → Get Started → wizard.

Per step, verify:

1. **Name step** — progress bar at 1/5, back chevron present, TextField focused, keyboard up. Typing past 25 chars clamps. Next enabled after typing.
2. **Name → Icon** — crossfade. Progress bar animates 1/5 → 2/5.
3. **Icon step** — heading + subtitle + circle with plus + currency name text below. Tap circle → Menu (Photo Library / Choose File). Pick image.
4. **Icon → Description** — crossfade. Progress 3/5.
5. **Description step** — scrolls, header row visible (circle + name), description TextField works.
6. **Description → Bill Creation** — crossfade. Progress 4/5. "Done" button visible in toolbar trailing.
7. **Bill Creation** — BillView above ColorEditor at bottom. Color changes reflect in bill. "Done" advances.
8. **Bill Creation → Confirmation** — crossfade. Progress 5/5. "Done" gone from toolbar.
9. **Confirmation** — header row (circle + name) + BillView + "Buy $20…" button. Button opens funding sheet (placeholder).

- [ ] **Step 2: Walk the back path**

Tap back chevron on each step, from confirmation back to name:

- Each back crossfades content back one step. Progress bar animates down.
- Try tapping back RAPIDLY to test cancellation. With `withAnimation` only (no completion handlers), rapid taps should just queue up state changes cleanly. Watch for glitches.
- Swipe-back gesture doesn't apply (we're `.interactiveDismissDisabled()` and single-view).
- On `.name` step, back button dismisses the wizard (pops the outer NavigationStack).

- [ ] **Step 3: Stop, report to user, wait for approval**

Do not commit without explicit approval.

---

## Task 4: Commit

**Files:** all changes from Tasks 1–3.

- [ ] **Step 1: Wait for user approval**

- [ ] **Step 2: Review diff**

```bash
git status
git diff
```

Expected:
- Deleted: `CurrencyCreationHeroAnchor.swift`, `CurrencyCreationHeroLayer.swift`, `HeroAnchorKeyTests.swift`
- Modified: `CurrencyCreationWizardScreen.swift` (full rewrite)

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
refactor: strip heroes from wizard, state-driven steps with default crossfade

Removes the anchor-preference hero system (HeroAnchorKey, HeroLayer,
menuHidden, heroNameRevealed, direction-aware slides, withAnimation
completion handlers, matchedGeometryEffect namespace) in favor of a
single ZStack switching on step state. Each step owns its content
(heading, TextField/Menu/BillView, Next button) inline; no morphing,
no overlay, no hero flags. Default opacity crossfade between steps.

The hero architecture was technically correct but fought iOS 18's
back-animation engine, produced on-device cancellation glitches, and
required per-device tuning of the bill rect to avoid overlapping the
ColorEditor. Dropping it returns the wizard to a known-working shape
with a single persistent toolbar (back chevron + progress bar).

Deletes CurrencyCreationHeroAnchor.swift, CurrencyCreationHeroLayer.swift,
and HeroAnchorKeyTests.swift.
EOF
)"
```

- [ ] **Step 4: Verify**

```bash
git log -1 --stat
```

---

## Notes

- **CLAUDE.md pitfall about `matchedGeometryEffect` modifier order** stays — still valid guidance for any future usage, even if we're not using it here.
- **Historical plans** in `.claude/plans/` remain as reference. They document why we ended up here; deleting them loses that context.
- **The `swiftui-pro` / `swiftui-expert` skills** will flag the `switch` inside `ZStack` as idiomatic, not something to extract.
- **If the fade feels abrupt** in visual QA, upgrade `.transition(.opacity)` to `.transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))`. That's direction-agnostic (same edges regardless of forward/back) so it doesn't re-introduce the cancellation glitches. But start with plain opacity.
