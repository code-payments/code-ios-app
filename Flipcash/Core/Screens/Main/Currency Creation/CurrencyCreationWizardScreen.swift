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

import SwiftUI
import UniformTypeIdentifiers
import FlipcashCore
import FlipcashUI

// MARK: - CurrencyCreationWizardScreen

struct CurrencyCreationWizardScreen: View {
    @Bindable var state: CurrencyCreationState

    @Environment(\.dismiss) private var dismiss

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
                    descriptionCharLimit: Self.descriptionCharLimit,
                    menuHidden: menuHidden,
                    onPhotoPicker: { isShowingPhotoPicker = true },
                    onFilePicker: { isShowingFilePicker = true }
                )

                StepControls(
                    step: step,
                    state: state,
                    focusedField: $focusedField,
                    nameCharLimit: Self.nameCharLimit,
                    heroNameRevealed: heroNameRevealed
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
                    previewFiat: Self.previewFiat,
                    anchors: anchors
                )
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .interactiveDismissDisabled()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    if step == .name {
                        dismiss()
                    } else {
                        goBack()
                    }
                } label: {
                    Image(systemName: "chevron.backward")
                        .foregroundStyle(Color.textMain)
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
/// bounds as the anchor for the given hero ID. Pass `nil` for either
/// dimension to let it flex to fill the parent (used by the bill
/// placeholder, which takes the remaining space in its container).
private struct HeroPlaceholder: View {
    let id: HeroAnchorID
    let width: CGFloat?
    let height: CGFloat?

    init(_ id: HeroAnchorID, width: CGFloat? = nil, height: CGFloat? = nil) {
        self.id = id
        self.width = width
        self.height = height
    }

    var body: some View {
        Color.clear
            .frame(width: width, height: height)
            .frame(
                maxWidth: width == nil ? .infinity : nil,
                maxHeight: height == nil ? .infinity : nil
            )
            .heroAnchor(id)
    }
}

// MARK: - StepChrome (sliding layer)

private struct StepChrome: View {
    let step: CurrencyCreationWizardScreen.WizardStep
    let direction: CurrencyCreationWizardScreen.Direction
    @Bindable var state: CurrencyCreationState
    @FocusState.Binding var focusedField: CurrencyCreationWizardScreen.Field?
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
                BillCreationChrome(state: state)
                    .transition(direction.slide)
            }
            if step == .confirmation {
                ConfirmationChrome()
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

    // Circle center Y as a fraction of content height. 0.5 is exact
    // geometric center; 0.4 sits visually above the center to match
    // the canonical mock (name + helper + button balance below the
    // circle). Tune here.
    private static let circleCenterFraction: CGFloat = 0.4

    var body: some View {
        GeometryReader { proxy in
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
            .position(
                x: proxy.size.width / 2,
                y: proxy.size.height * Self.circleCenterFraction
            )
        }
        .overlay(alignment: .top) {
            VStack(spacing: 16) {
                Text("Upload Currency Icon")
                    .font(.appTextLarge)
                    .foregroundStyle(Color.textMain)

                Text("Choose an image that represents your currency. It will be displayed as a circular icon.")
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            .padding(.top, 20)
            .padding(.horizontal, 20)
        }
    }
}

private struct DescriptionChrome: View {
    @Bindable var state: CurrencyCreationState
    @FocusState.Binding var focusedField: CurrencyCreationWizardScreen.Field?
    let characterLimit: Int

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header placeholders live inside the ScrollView so
                // scrolling moves the hero anchors for free.
                HStack(spacing: 12) {
                    HeroPlaceholder(.circle, width: 28, height: 28)
                    HeroPlaceholder(.name, height: 24)
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
            .padding(.horizontal, 20)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.hidden)
    }
}

/// The bill itself is rendered by the HeroLayer overlay at the `.bill`
/// anchor published in BillCreationControls. This chrome just holds the
/// ColorEditor at the bottom.
private struct BillCreationChrome: View {
    @Bindable var state: CurrencyCreationState

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            ColorEditorControl(colors: $state.backgroundColors)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 20)
                .clipped()
        }
    }
}

/// Empty sliding chrome — all content (heroes, bill, button) lives in
/// non-sliding layers that morph between steps.
private struct ConfirmationChrome: View {
    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - StepControls (non-sliding layer)

private struct StepControls: View {
    let step: CurrencyCreationWizardScreen.WizardStep
    @Bindable var state: CurrencyCreationState
    @FocusState.Binding var focusedField: CurrencyCreationWizardScreen.Field?
    let nameCharLimit: Int
    let heroNameRevealed: Bool

    var body: some View {
        ZStack {
            if step == .name {
                NameControls(
                    state: state,
                    focusedField: $focusedField,
                    nameCharLimit: nameCharLimit,
                    heroNameRevealed: heroNameRevealed
                )
                .transition(.identity)
            }
            if step == .icon {
                IconControls().transition(.identity)
            }
            if step == .billCreation {
                BillCreationControls().transition(.identity)
            }
            if step == .confirmation {
                ConfirmationControls(state: state).transition(.identity)
            }
            // .description publishes its header anchors inside the
            // ScrollView in DescriptionChrome so they scroll with
            // content.
        }
    }
}

private struct NameControls: View {
    @Bindable var state: CurrencyCreationState
    @FocusState.Binding var focusedField: CurrencyCreationWizardScreen.Field?
    let nameCharLimit: Int
    let heroNameRevealed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Heading lives in NameChrome; this reserves room so the
            // TextField sits below it with a visible gap.
            Color.clear.frame(height: 96)

            TextField("Currency Name", text: $state.currencyName)
                .font(.appDisplayMedium)
                .foregroundStyle(Color.textMain)
                .multilineTextAlignment(.leading)
                .focused($focusedField, equals: .name)
                .heroAnchor(.name)
                // Hidden while overlay HeroName owns the visual (during
                // forward advance and back-return transitions). Toggled
                // instantly with `heroNameRevealed` — no fade.
                .opacity(heroNameRevealed ? 0 : 1)
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
    // Keep in sync with IconChrome.circleCenterFraction so the circle
    // footprint lines up with the Menu's anchor exactly.
    private static let circleCenterFraction: CGFloat = 0.4

    var body: some View {
        GeometryReader { proxy in
            let centerY = proxy.size.height * Self.circleCenterFraction

            Color.clear
                .frame(
                    width: CurrencyCreationWizardScreen.heroCircleSize,
                    height: CurrencyCreationWizardScreen.heroCircleSize
                )
                .position(x: proxy.size.width / 2, y: centerY)

            HeroPlaceholder(.name, height: 40)
                .padding(.horizontal, 20)
                .position(
                    x: proxy.size.width / 2,
                    y: centerY
                        + CurrencyCreationWizardScreen.heroCircleSize / 2
                        + 16
                        + 20
                )
        }
    }
}

/// Publishes the .bill anchor at the bill-creation position.
/// Proportional sizing keeps the bill smaller than confirmation
/// because the ColorEditor takes significant vertical space at the
/// bottom (larger than the Buy button used on confirmation).
private struct BillCreationControls: View {
    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                HeroPlaceholder(.bill, height: proxy.size.height * 0.52)
                    .padding(.top, 20)
                    .padding(.horizontal, 40)

                Spacer(minLength: 0)

                // ColorEditor sits at the bottom of BillCreationChrome.
                // Reserve ~30% of content height — ColorEditor internals
                // (PanelMetrics.height 110 + tile grid + paddings) plus
                // a visual gap above.
                Color.clear.frame(height: proxy.size.height * 0.32)
            }
        }
    }
}

/// Centered header for the confirmation step PLUS the bill anchor
/// below it. The bill is taller here than on bill creation because
/// the only thing below it is the Buy button (much shorter than the
/// ColorEditor).
private struct ConfirmationControls: View {
    @Bindable var state: CurrencyCreationState

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    HeroPlaceholder(.circle, width: 28, height: 28)

                    Text(state.currencyName.isEmpty ? " " : state.currencyName)
                        .font(.appTextLarge)
                        .lineLimit(1)
                        .hidden()
                        .heroAnchor(.name)
                }
                .padding(.top, 20)

                // Gap between heroes and bill.
                Color.clear.frame(height: 40)

                HeroPlaceholder(.bill, height: proxy.size.height * 0.62)
                    .padding(.horizontal, 20)

                Spacer(minLength: 0)

                // Reserve for the Buy button in the bottom bar.
                Color.clear.frame(height: 120)
            }
        }
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
