# Currency Creation Wizard — Anchor-Preference Heroes, Three-Layer Architecture

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the remaining wizard animation bugs by restructuring the view tree into three layers (sliding chrome, non-sliding controls/anchors, hero overlay) driven by anchor preferences. Eliminates hardcoded offsets, `AnyLayout` coupling, the `DispatchQueue.main.async` keyboard hack, and gives clean hero handoffs.

**Architecture:** The wizard stacks three coexisting layers inside a single `ZStack`:

1. **Sliding chrome** — headings, subtitles, description scroll, bill preview, AND the real `Menu` for the icon step. Uses `.transition(.asymmetric(...))` with a `direction` state so transitions reverse when going back.
2. **Non-sliding controls/anchors** — real `TextField` for the name step, invisible `HeroPlaceholder` views for every step's hero targets. Uses `.transition(.identity)` — step changes swap contents instantly.
3. **Hero overlay** — pure visual `HeroName` (Text) and `HeroCircle` (Circle + image/plus). Purely presentational, `.allowsHitTesting(false)`. Reads `anchors[.circle]` / `anchors[.name]` via `overlayPreferenceValue`.

**Two state flags coordinate the hero handoff:**
- `heroNameRevealed`: when false, overlay HeroName hidden so TextField is the only name on screen; flipped to true before advancing from `.name`, flipped back in completion on the back transition to `.name`.
- `menuHidden`: toggled via `.transaction { $0.animation = nil }` so Menu snaps in/out without animation. Forward icon→description sets it true before `withAnimation`; back description→icon sets it false in the completion handler.

**Tech Stack:** SwiftUI, `@Observable`, anchor preferences, `overlayPreferenceValue`, `GeometryProxy[anchor]`, `withAnimation(_:completion:)` (iOS 17+).

**Reference:**
- `.claude/plans/2026-04-13-hero-animation-handoff.md` — problem statement.
- This plan's section "Transition behavior" below — normative behavior per transition.

**Scope guard:** If a task hits a new architectural dead end, stop. Fall back to Option C (stock NavigationStack, no hero). Do not compound patches. Time budget for this work: one focused session.

---

## Transition behavior (normative)

Use this as the checklist for visual QA. Deviations from this table are bugs.

| Transition | Circle behavior | Name behavior | Chrome behavior |
|------------|----------------|---------------|-----------------|
| `.name` → `.icon` forward | Slides in from right **with icon chrome** (it's inside the Menu which lives in chrome) | Overlay hero morphs from TextField position to below-circle position (shrinks) | Icon chrome slides in from right; name chrome slides out left |
| `.icon` → `.name` back | Slides out to right **with icon chrome** (Menu goes with it) | Overlay hero morphs from below-circle back to TextField position (grows); on completion, overlay hides and TextField becomes the visible name | Icon chrome slides out right; name chrome slides in from left |
| `.icon` → `.description` forward | Real Menu hidden instantly via `menuHidden` flag; overlay HeroCircle morphs from 150pt center to 28pt header (leading) | Overlay hero morphs from below-circle to header (beside circle) | Icon chrome slides left (with invisible Menu); description chrome slides in right |
| `.description` → `.icon` back | Overlay HeroCircle morphs from 28pt header to 150pt center; on completion, `menuHidden` flipped false so real Menu reveals at center | Overlay hero morphs from header back to below-circle | Icon chrome slides in from left; description chrome slides out right |
| `.description` → `.billCreation` | Overlay HeroCircle and HeroName fade out (step has no anchors) | — | Description chrome slides left; bill chrome slides in right |
| `.billCreation` → `.confirmation` forward, and back pairs | Heroes fade back in at header; symmetric on back | Symmetric | Chrome slides per direction |

**Golden rule**: no double circles, no double name texts. On every transition, the user sees exactly one of each (unless both are absent, like bill step).

---

## File Structure

**New files:**
- `Flipcash/Core/Screens/Main/Currency Creation/CurrencyCreationHeroAnchor.swift` — `HeroAnchorKey`, `HeroAnchorID`, `.heroAnchor(_:)` modifier.
- `Flipcash/Core/Screens/Main/Currency Creation/CurrencyCreationHeroLayer.swift` — `HeroLayer`, `HeroCircle`, `HeroName` (all purely visual).
- `FlipcashTests/CurrencyCreation/HeroAnchorKeyTests.swift` — preference-key merge tests.

**Modified:** `Flipcash/Core/Screens/Main/Currency Creation/CurrencyCreationWizardScreen.swift` — full rewrite. Existing structs `WizardHeroGroup`, `WizardHeroCircle`, `WizardHeroNameField`, and the `descriptionScrollOffset` state are removed. New private structs `StepChrome`, `StepControls`, and the individual step views live here (they're tightly coupled to the wizard).

**Unchanged files:** `CurrencyCreationScreen.swift`, `CurrencyCreationSummaryScreen.swift`.

---

## Test Strategy

Animation work is visual. Unit tests cover the pure-data preference merge. Visual QA happens after Task 5 via simulator walkthroughs against the "Transition behavior" table above.

---

## Task 1: Add `HeroAnchorKey` infrastructure

**Files:**
- Create: `Flipcash/Core/Screens/Main/Currency Creation/CurrencyCreationHeroAnchor.swift`
- Create: `FlipcashTests/CurrencyCreation/HeroAnchorKeyTests.swift`

- [ ] **Step 1: Write the failing unit test**

Create `FlipcashTests/CurrencyCreation/HeroAnchorKeyTests.swift`:

```swift
//
//  HeroAnchorKeyTests.swift
//  FlipcashTests
//

import SwiftUI
import Testing
@testable import Flipcash

@Suite("HeroAnchorKey")
struct HeroAnchorKeyTests {

    @Test("Default value is empty")
    func defaultValueIsEmpty() {
        #expect(HeroAnchorKey.defaultValue.isEmpty)
    }

    @Test("Merge is last-writer-wins per key")
    func mergeLastWriterWinsPerKey() {
        var current: [HeroAnchorID: Int] = [.circle: 1]
        let incoming: [HeroAnchorID: Int] = [.circle: 2, .name: 9]
        current.merge(incoming) { _, new in new }

        #expect(current[.circle] == 2)
        #expect(current[.name] == 9)
    }
}
```

- [ ] **Step 2: Run the test; confirm compile failure**

```bash
xcodebuild test -scheme Flipcash -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FlipcashTests/HeroAnchorKeyTests
```
Expected: compile error — `HeroAnchorKey`, `HeroAnchorID` undefined.

- [ ] **Step 3: Create the file**

```swift
//
//  CurrencyCreationHeroAnchor.swift
//  Flipcash
//
//  Layout-driven hero positioning for the currency creation wizard.
//  The non-sliding controls layer and the icon chrome's Menu publish
//  Anchor<CGRect> rects via `.heroAnchor(_:)`. The HeroLayer overlay
//  reads those anchors and positions independent circle + name views.
//

import SwiftUI

enum HeroAnchorID: Hashable {
    case circle
    case name
}

struct HeroAnchorKey: PreferenceKey {
    static let defaultValue: [HeroAnchorID: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [HeroAnchorID: Anchor<CGRect>],
        nextValue: () -> [HeroAnchorID: Anchor<CGRect>]
    ) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Publishes this view's bounds as the anchor for the given hero ID.
    /// Attach to either an invisible `HeroPlaceholder` (non-sliding controls
    /// layer) or to the actual interactive control (Menu on icon chrome,
    /// TextField on name controls).
    func heroAnchor(_ id: HeroAnchorID) -> some View {
        anchorPreference(key: HeroAnchorKey.self, value: .bounds) { anchor in
            [id: anchor]
        }
    }
}
```

- [ ] **Step 4: Run the test; confirm pass**

```bash
xcodebuild test -scheme Flipcash -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FlipcashTests/HeroAnchorKeyTests
```
Expected: both tests PASS.

- [ ] **Step 5: Do not commit yet. Proceed to Task 2.**

---

## Task 2: Create `HeroLayer` overlay

**Files:**
- Create: `Flipcash/Core/Screens/Main/Currency Creation/CurrencyCreationHeroLayer.swift`

- [ ] **Step 1: Create the file**

```swift
//
//  CurrencyCreationHeroLayer.swift
//  Flipcash
//
//  The wizard's hero overlay layer. Pure visuals — reads anchor rects
//  via `overlayPreferenceValue(HeroAnchorKey.self)` and positions an
//  independent HeroCircle and HeroName at those rects. Never
//  interactive: `.allowsHitTesting(false)` lets taps pass through to
//  the real Menu / TextField underneath.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

struct HeroLayer: View {
    let step: CurrencyCreationWizardScreen.WizardStep
    @Bindable var state: CurrencyCreationState
    let heroNameRevealed: Bool
    let anchors: [HeroAnchorID: Anchor<CGRect>]

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                // Circle: rendered whenever the current step publishes a
                // circle anchor. On `.name` step there is no circle anchor,
                // so nothing renders and no stale position lingers.
                if step != .billCreation, let rect = anchors[.circle].map({ proxy[$0] }) {
                    HeroCircle(step: step, selectedImage: state.selectedImage)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }

                // Name: rendered whenever there's a name anchor and we're
                // not on bill creation. Hidden on `.name` step until
                // `heroNameRevealed` is set — lets the real TextField own
                // the visual while the user is typing.
                if step != .billCreation, let rect = anchors[.name].map({ proxy[$0] }) {
                    HeroName(step: step, name: state.currencyName)
                        .frame(width: rect.width, height: rect.height, alignment: .leading)
                        .position(x: rect.midX, y: rect.midY)
                        .opacity(step == .name && !heroNameRevealed ? 0 : 1)
                }
            }
        }
        .ignoresSafeArea(.keyboard)
        .allowsHitTesting(false)
    }
}

private struct HeroCircle: View {
    let step: CurrencyCreationWizardScreen.WizardStep
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
                    .font(.system(size: step == .icon ? 40 : 18, weight: .light))
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .compositingGroup()
        .clipShape(Circle())
    }
}

private struct HeroName: View {
    let step: CurrencyCreationWizardScreen.WizardStep
    let name: String

    var body: some View {
        Text(name.isEmpty ? " " : name)
            .font(font)
            .foregroundStyle(Color.textMain)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var font: Font {
        switch step {
        case .name: .appDisplayMedium
        case .icon: .appDisplaySmall
        case .description, .billCreation, .confirmation: .appTextLarge
        }
    }
}
```

- [ ] **Step 2: Verify build**

```bash
xcodebuild build -scheme Flipcash -destination 'platform=iOS Simulator,name=iPhone 17'
```

Expected: BUILD SUCCEEDED (`HeroLayer` compiles standalone; not wired yet, so `CurrencyCreationWizardScreen.WizardStep` reference must resolve — it already exists in the wizard file).

---

## Task 3: Rewrite `CurrencyCreationWizardScreen.swift`

This is a full file rewrite. Do it in one shot for clarity — the final contents are given in Step 1. Tasks 4 and 5 will build on this.

**Files:**
- Modify: `Flipcash/Core/Screens/Main/Currency Creation/CurrencyCreationWizardScreen.swift` — full replacement

- [ ] **Step 1: Replace the entire file with the following contents**

```swift
//
//  CurrencyCreationWizardScreen.swift
//  Flipcash
//
//  Single-view wizard with three layers stacked in a ZStack:
//    1. StepChrome — sliding headings, subtitles, scroll content,
//       bill preview, AND the icon step's real Menu. Uses
//       `.transition(.asymmetric(...))` driven by `direction`.
//    2. StepControls — non-sliding. Real TextField on name step,
//       invisible HeroPlaceholder views per step. Uses
//       `.transition(.identity)` so step changes swap contents
//       instantly.
//    3. HeroLayer — overlay reading anchor preferences, purely
//       visual HeroCircle + HeroName. `.allowsHitTesting(false)`.
//
//  State flags:
//    - heroNameRevealed: hides overlay HeroName on .name step until
//      user advances; set synchronously pre-advance, reset in back
//      completion.
//    - menuHidden: instant (non-animated) flag for the icon step's
//      real Menu. Set true before forward icon→description; set
//      false in back description→icon completion. Ensures the
//      "real" Menu disappears instantly when overlay HeroCircle
//      needs to morph past it.
//    - direction: .forward | .backward. Selects slide direction for
//      StepChrome transitions.
//

import SwiftUI
import UniformTypeIdentifiers
import FlipcashCore
import FlipcashUI

// MARK: - CurrencyCreationWizardScreen

struct CurrencyCreationWizardScreen: View {
    @Bindable var state: CurrencyCreationState

    @State private var step: WizardStep = .name
    @State private var direction: Direction = .forward
    @State private var heroNameRevealed = false
    @State private var menuHidden = false
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

    enum Direction {
        case forward, backward

        var insertionEdge: Edge { self == .forward ? .trailing : .leading }
        var removalEdge: Edge { self == .forward ? .leading : .trailing }

        var slide: AnyTransition {
            .asymmetric(
                insertion: .move(edge: insertionEdge),
                removal: .move(edge: removalEdge)
            )
        }
    }

    var body: some View {
        Background(color: .backgroundMain) {
            ZStack {
                StepChrome(
                    step: step,
                    direction: direction,
                    state: state,
                    focusedField: $focusedField,
                    previewFiat: Self.previewFiat,
                    descriptionCharLimit: Self.descriptionCharLimit,
                    menuHidden: menuHidden,
                    onPhotoPicker: { isShowingPhotoPicker = true },
                    onFilePicker: { isShowingFilePicker = true }
                )

                StepControls(
                    step: step,
                    state: state,
                    focusedField: $focusedField,
                    nameCharLimit: Self.nameCharLimit
                )

                if step != .billCreation {
                    WizardBottomBar(
                        step: step,
                        state: state,
                        nameCharLimit: Self.nameCharLimit,
                        descriptionCharLimit: Self.descriptionCharLimit,
                        onAdvance: advance,
                        onBuy: { isShowingFundingSheet = true }
                    )
                }
            }
            .overlayPreferenceValue(HeroAnchorKey.self) { anchors in
                HeroLayer(
                    step: step,
                    state: state,
                    heroNameRevealed: heroNameRevealed,
                    anchors: anchors
                )
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if step != .name {
                    Button {
                        goBack()
                    } label: {
                        Image(systemName: "chevron.backward")
                            .foregroundStyle(Color.textMain)
                    }
                }
            }

            ToolbarItem(placement: .principal) {
                CreationProgressBar(
                    current: step.rawValue + 1,
                    total: WizardStep.allCases.count
                )
                .animation(.easeInOut(duration: 0.35), value: step)
            }

            if step == .billCreation {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { advance() }
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

        direction = .forward

        // Pre-transition state adjustments outside withAnimation.
        if step == .name {
            focusedField = nil
            heroNameRevealed = true
        }
        if step == .icon {
            // Real Menu vanishes instantly; overlay HeroCircle takes
            // over at the same position for the morph.
            withTransaction(Transaction(animation: nil)) {
                menuHidden = true
            }
        }

        withAnimation(.spring(duration: 0.55, bounce: 0.12)) {
            step = next
        }
    }

    private func goBack() {
        guard let previous = step.previous else { return }

        direction = .backward

        withAnimation(.spring(duration: 0.55, bounce: 0.12)) {
            step = previous
        } completion: {
            // After the back transition settles:
            //   - If we landed on .icon, reveal the real Menu (its
            //     overlay HeroCircle is already at the same position).
            //   - If we landed on .name, hide overlay HeroName so the
            //     real TextField becomes the only name on screen.
            if previous == .icon {
                withTransaction(Transaction(animation: nil)) {
                    menuHidden = false
                }
            }
            if previous == .name {
                heroNameRevealed = false
            }
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

// MARK: - HeroPlaceholder

/// Invisible view sized to where a hero should land, publishing its
/// bounds as the anchor for the given hero ID. Pass `width: nil` for a
/// flexible/leading target (e.g. the name row); pass a concrete width
/// for a fixed target (e.g. a 28pt header circle).
private struct HeroPlaceholder: View {
    let id: HeroAnchorID
    let width: CGFloat?
    let height: CGFloat

    init(_ id: HeroAnchorID, width: CGFloat? = nil, height: CGFloat) {
        self.id = id
        self.width = width
        self.height = height
    }

    var body: some View {
        Color.clear
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil)
            .heroAnchor(id)
    }
}

// MARK: - StepChrome (sliding layer)

/// Sliding chrome: headings, subtitles, scroll content, bill preview,
/// AND the icon step's real Menu. Uses `.transition(.asymmetric(...))`
/// driven by `direction`.
private struct StepChrome: View {
    let step: CurrencyCreationWizardScreen.WizardStep
    let direction: CurrencyCreationWizardScreen.Direction
    @Bindable var state: CurrencyCreationState
    @FocusState.Binding var focusedField: CurrencyCreationWizardScreen.Field?
    let previewFiat: Quarks
    let descriptionCharLimit: Int
    let menuHidden: Bool
    let onPhotoPicker: () -> Void
    let onFilePicker: () -> Void

    var body: some View {
        ZStack {
            if step == .name {
                NameChrome().transition(direction.slide)
            }
            if step == .icon {
                IconChrome(
                    menuHidden: menuHidden,
                    onPhotoPicker: onPhotoPicker,
                    onFilePicker: onFilePicker
                )
                .transition(direction.slide)
            }
            if step == .description {
                DescriptionChrome(
                    state: state,
                    focusedField: $focusedField,
                    characterLimit: descriptionCharLimit
                )
                .transition(direction.slide)
            }
            if step == .billCreation {
                BillCreationChrome(state: state, previewFiat: previewFiat)
                    .transition(direction.slide)
            }
            if step == .confirmation {
                ConfirmationChrome(previewFiat: previewFiat, state: state)
                    .transition(direction.slide)
            }
        }
    }
}

private struct NameChrome: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("What do you want to call\nyour currency?")
                .font(.appTextLarge)
                .foregroundStyle(Color.textMain)
                .padding(.top, 20)

            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct IconChrome: View {
    let menuHidden: Bool
    let onPhotoPicker: () -> Void
    let onFilePicker: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Upload Currency Icon")
                .font(.appTextLarge)
                .foregroundStyle(Color.textMain)
                .padding(.top, 20)

            Text("Choose an image that represents your currency. It will be displayed as a circular icon.")
                .font(.appTextSmall)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            Spacer(minLength: 0)

            // The real Menu — publishes the circle anchor. Rendered
            // with opacity-driven visibility controlled by `menuHidden`
            // so we can hand off to overlay HeroCircle without a fade.
            Menu {
                Button("Photo Library", systemImage: "photo.on.rectangle") { onPhotoPicker() }
                Button("Choose File", systemImage: "folder") { onFilePicker() }
            } label: {
                Color.clear
                    .frame(
                        width: CurrencyCreationWizardScreen.heroCircleSize,
                        height: CurrencyCreationWizardScreen.heroCircleSize
                    )
                    .heroAnchor(.circle)
            }
            .menuIndicator(.hidden)
            .opacity(menuHidden ? 0 : 1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct DescriptionChrome: View {
    @Bindable var state: CurrencyCreationState
    @FocusState.Binding var focusedField: CurrencyCreationWizardScreen.Field?
    let characterLimit: Int

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Reserve space for the hero header row (inside the
                // ScrollView, so scrolling moves the anchors for free).
                Color.clear.frame(height: 48)

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
            .padding(.horizontal, 20)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.hidden)
    }
}

private struct BillCreationChrome: View {
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

private struct ConfirmationChrome: View {
    let previewFiat: Quarks
    @Bindable var state: CurrencyCreationState

    var body: some View {
        VStack(spacing: 0) {
            // Reserve space for the hero header row.
            Color.clear.frame(height: 48)

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
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
    }
}

// MARK: - StepControls (non-sliding layer)

/// Non-sliding. Holds the real TextField on `.name` step and invisible
/// HeroPlaceholder views on every step that has them. Uses
/// `.transition(.identity)` so step changes swap contents instantly —
/// the heroes themselves handle the perceived motion via anchor morphs.
private struct StepControls: View {
    let step: CurrencyCreationWizardScreen.WizardStep
    @Bindable var state: CurrencyCreationState
    @FocusState.Binding var focusedField: CurrencyCreationWizardScreen.Field?
    let nameCharLimit: Int

    var body: some View {
        ZStack {
            if step == .name {
                NameControls(
                    state: state,
                    focusedField: $focusedField,
                    nameCharLimit: nameCharLimit
                )
                .transition(.identity)
            }
            if step == .icon {
                IconControls().transition(.identity)
            }
            if step == .description || step == .confirmation {
                HeaderControls().transition(.identity)
            }
            // .billCreation intentionally has no controls / anchors.
        }
    }
}

private struct NameControls: View {
    @Bindable var state: CurrencyCreationState
    @FocusState.Binding var focusedField: CurrencyCreationWizardScreen.Field?
    let nameCharLimit: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The heading space is owned by chrome, we just leave room
            // for it here so the TextField lands in the right place.
            Color.clear.frame(height: 72)

            TextField("Currency Name", text: $state.currencyName)
                .font(.appDisplayMedium)
                .foregroundStyle(Color.textMain)
                .multilineTextAlignment(.leading)
                .focused($focusedField, equals: .name)
                .heroAnchor(.name)
                .onChange(of: state.currencyName) { _, newValue in
                    if newValue.count > nameCharLimit {
                        state.currencyName = String(newValue.prefix(nameCharLimit))
                    }
                }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct IconControls: View {
    // Circle anchor is published by the Menu in icon chrome. We only
    // need the name placeholder here — it goes below the circle.
    var body: some View {
        VStack(spacing: 16) {
            Color.clear
                .frame(height: 72 + 8 + 14 + 16)  // heading + spacing + subtitle + pad

            Spacer(minLength: 0)

            // Reserve the circle's vertical footprint so the name lands
            // below where the circle actually is.
            Color.clear.frame(height: CurrencyCreationWizardScreen.heroCircleSize)

            HeroPlaceholder(.name, height: 32)
                .padding(.horizontal, 20)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct HeaderControls: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                HeroPlaceholder(.circle, width: 28, height: 28)
                HeroPlaceholder(.name, height: 24)
            }
            .padding(.top, 20)
            .padding(.horizontal, 20)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - WizardBottomBar

private struct WizardBottomBar: View {
    let step: CurrencyCreationWizardScreen.WizardStep
    @Bindable var state: CurrencyCreationState
    let nameCharLimit: Int
    let descriptionCharLimit: Int
    let onAdvance: () -> Void
    let onBuy: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            WizardHelperText(
                step: step,
                state: state,
                nameCharLimit: nameCharLimit,
                descriptionCharLimit: descriptionCharLimit
            )
            .font(.appTextSmall)
            .foregroundStyle(Color.textSecondary)
            .frame(maxWidth: .infinity, alignment: helperTextAlignment)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            WizardPrimaryButton(
                step: step,
                state: state,
                onAdvance: onAdvance,
                onBuy: onBuy
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    private var helperTextAlignment: Alignment {
        switch step {
        case .name, .description: .leading
        case .icon, .billCreation, .confirmation: .center
        }
    }
}

private struct WizardHelperText: View {
    let step: CurrencyCreationWizardScreen.WizardStep
    @Bindable var state: CurrencyCreationState
    let nameCharLimit: Int
    let descriptionCharLimit: Int

    var body: some View {
        switch step {
        case .name:
            Text("\(nameCharLimit - state.currencyName.count) characters")
        case .icon:
            Text("500x500 Recommended")
        case .description:
            Text("\(descriptionCharLimit - state.currencyDescription.count) characters")
        case .billCreation, .confirmation:
            Text(" ").hidden()
        }
    }
}

private struct WizardPrimaryButton: View {
    let step: CurrencyCreationWizardScreen.WizardStep
    @Bindable var state: CurrencyCreationState
    let onAdvance: () -> Void
    let onBuy: () -> Void

    var body: some View {
        Button(buttonTitle) {
            step == .confirmation ? onBuy() : onAdvance()
        }
        .buttonStyle(.filled)
        .disabled(isDisabled)
    }

    private var buttonTitle: String {
        switch step {
        case .confirmation: "Buy $20 to Create Your Currency"
        case .name, .icon, .description, .billCreation: "Next"
        }
    }

    private var isDisabled: Bool {
        switch step {
        case .name:
            state.currencyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .icon:
            state.selectedImage == nil
        case .description:
            state.currencyDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .billCreation, .confirmation:
            false
        }
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

- [ ] **Step 2: Verify build**

```bash
xcodebuild build -scheme Flipcash -destination 'platform=iOS Simulator,name=iPhone 17'
```

Expected: BUILD SUCCEEDED.

---

## Task 4: Visual QA in the simulator

**Files:** none — testing only.

- [ ] **Step 1: Run the app**

Boot the iPhone 17 simulator and launch Flipcash. Navigate: Currency Discovery → Create Your Currency → Get Started.

- [ ] **Step 2: Walk the golden forward path and verify the Transition Behavior table**

Exercise each transition:

1. **`.name` step (initial)** — TextField focused, keyboard up. Helper text "25 characters". Progress 1/5. No back button.
2. **`.name` → `.icon`** — tap Next. Expected:
   - Keyboard dismisses.
   - Name text shrinks and moves down (overlay morphs from TextField position to below-circle position).
   - Circle (with `+`) slides in from the right with icon chrome.
   - **No double name, no double circle, no position jump.**
3. **`.icon` step** — tap the circle; Menu appears with Photo Library / Choose File. Pick an image. Helper text "500×500 Recommended". Progress 2/5. Back button appears.
4. **`.icon` → `.description`** — tap Next. Expected:
   - Icon chrome slides left (Menu goes with it, INVISIBLY — no double circle).
   - Overlay HeroCircle morphs from 150pt center to 28pt header-leading.
   - Overlay HeroName morphs from below-circle to beside the header circle.
   - Description chrome slides in from right.
5. **`.description` step** — scrolls; the header hero row scrolls with the content (inside ScrollView, anchors move for free). Progress 3/5.
6. **`.description` → `.billCreation`** — tap Next. Expected:
   - Heroes fade out.
   - Description chrome slides left; bill chrome slides in right. Color editor appears.
   - "Done" in toolbar. Bottom bar hidden.
7. **`.billCreation` → `.confirmation`** — tap Done. Expected:
   - Heroes fade back in at header.
   - Chrome slides forward. Bill preview shown with "Buy $20…" button.

- [ ] **Step 3: Walk the golden back path and verify reversal**

From `.confirmation` back to `.name`:

1. **`.confirmation` → `.billCreation`** — tap back. Chrome slides right (reversed). Heroes fade out again.
2. **`.billCreation` → `.description`** — tap back. Heroes fade in at header. Chrome slides right.
3. **`.description` → `.icon`** — tap back. Expected:
   - Overlay HeroCircle morphs from 28pt header to 150pt center.
   - Overlay HeroName morphs from header to below-circle.
   - Icon chrome slides in from left; description chrome slides out right.
   - At animation completion, real Menu reveals (menuHidden → false) and is perfectly coincident with overlay HeroCircle.
4. **`.icon` → `.name`** — tap back. Expected:
   - Icon chrome slides right; **Menu (and the visible `+` circle) slides out with it** to the right.
   - Overlay HeroName morphs from below-circle back to TextField position.
   - Name chrome slides in from left.
   - At completion, overlay HeroName hides (`heroNameRevealed = false`), TextField is the only name visible.

- [ ] **Step 4: Screenshot the five steps via MCP**

Use `mcp__XcodeBuildMCP__screenshot` (if available) or the simulator's screenshot to capture each step. Save to `/tmp/wizard-screenshots/`. Attach to the user message.

- [ ] **Step 5: Stop — hand off to the user**

Report exactly which transitions passed and any that regressed. Do NOT commit. If a transition regresses in a way that needs an architectural change (not a 1-line padding tweak), trigger the scope guard: report the issue, don't keep patching.

---

## Task 5: Fix or tune based on QA feedback

This task is deliberately open-ended. Likely tuning areas:
- Name placeholder height / vertical spacing inside `NameControls` and `IconControls` to match text baselines.
- `HeaderControls` top padding if the 28pt circle doesn't line up with where the description body text starts.
- `heroCircleSize` if 150pt looks wrong on smaller devices.
- Spring parameters (`duration: 0.55, bounce: 0.12`) if the motion feels off.

Constraints:
- No hardcoded offsets beyond what's already in this plan.
- No `DispatchQueue.main.async` reappearances.
- No `.animation(nil, value:)` as a symptom patch.

If the issue is structural, fall back to the scope guard (Option C) — do not compound patches.

---

## Task 6: Commit

**Files:** all changes from Tasks 1–5.

- [ ] **Step 1: Wait for explicit user approval**

Per commit discipline, do not proceed without "commit" from the user.

- [ ] **Step 2: Review diff**

```bash
git status
git diff
```

Expected: 2 new Swift files in `Flipcash/Core/Screens/Main/Currency Creation/`, 1 modified (the wizard screen), 1 new test file in `FlipcashTests/CurrencyCreation/`.

- [ ] **Step 3: Commit**

```bash
git add \
  "Flipcash/Core/Screens/Main/Currency Creation/CurrencyCreationHeroAnchor.swift" \
  "Flipcash/Core/Screens/Main/Currency Creation/CurrencyCreationHeroLayer.swift" \
  "Flipcash/Core/Screens/Main/Currency Creation/CurrencyCreationWizardScreen.swift" \
  "FlipcashTests/CurrencyCreation/HeroAnchorKeyTests.swift"

git commit -m "$(cat <<'EOF'
refactor: three-layer wizard with anchor-preference heroes

Replaces AnyLayout grouping + hardcoded offsets + DispatchQueue keyboard
hack with a three-layer ZStack: sliding StepChrome, non-sliding
StepControls, hero overlay positioned via Anchor<CGRect> preferences.

Transition behavior:
- Name→Icon / Icon→Name: circle slides with icon chrome (not a hero
  here); name hero morphs between TextField position and below-circle
- Icon→Description / Description→Icon: circle hero morphs between
  150pt center and 28pt leading header; real Menu is hidden via
  menuHidden flag (transaction with nil animation) during the handoff
  and revealed again in the back completion closure
- Direction-aware slide transitions driven by a Direction state so
  back navigation reverses the slide edges

Removes WizardHeroGroup / WizardHeroCircle / WizardHeroNameField and
the descriptionScrollOffset binding. Hero overlay ignores the keyboard
safe area, so keyboard dismissal no longer shifts the hero coordinate
space — no timing hacks required.
EOF
)"
```

- [ ] **Step 4: Verify**

```bash
git log -1 --stat
```

Expected: commit at HEAD with the four files listed.

---

## Notes

- **Why the real Menu's `heroAnchor(.circle)` is attached to a `Color.clear.frame(150x150)` and not to the visible circle:** the `Color.clear` is a flexible sizing primitive that won't interfere with `Menu`'s own layout, and `.heroAnchor(.circle)` captures its bounds. The overlay HeroCircle renders the actual visual at the same rect — they appear to the user as one circle.
- **Why the overlay continues to render when step is `.icon`:** overlay HeroCircle rendering is gated by `anchors[.circle] != nil`, which is true on icon step (Menu publishes the anchor). Overlay and Menu coincide visually → user sees one circle. This is intentional and load-bearing for the icon↔description handoff.
- **`withAnimation(_:completion:)` is iOS 17+**. App min is iOS 17, so this is available universally.
