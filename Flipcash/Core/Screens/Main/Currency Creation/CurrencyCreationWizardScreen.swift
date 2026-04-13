//
//  CurrencyCreationWizardScreen.swift
//  Flipcash
//
//  Single-view wizard for currency creation. Hero elements (currency name
//  text and icon circle) are always present in the view tree. AnyLayout
//  interpolates between VStack (icon step) and HStack (header steps) so
//  the heroes morph between layouts without conditional-branch cross-fade.
//

import SwiftUI
import UniformTypeIdentifiers
import FlipcashCore
import FlipcashUI

// MARK: - CurrencyCreationWizardScreen

struct CurrencyCreationWizardScreen: View {
    @Bindable var state: CurrencyCreationState

    @State private var step: WizardStep = .name
    @FocusState private var focusedField: Field?
    @State private var heroNameRevealed = false
    @State private var descriptionScrollOffset: CGFloat = 0
    @State private var isShowingPhotoPicker = false
    @State private var isShowingFilePicker = false
    @State private var isShowingFundingSheet = false

    private static let nameCharLimit = 25
    private static let descriptionCharLimit = 500

    // swiftlint:disable:next force_try
    private static let previewFiat = try! Quarks(fiatDecimal: 20, currencyCode: .usd, decimals: 6)

    enum Field: Hashable {
        case name
        case description
    }

    enum WizardStep: Int, CaseIterable {
        case name = 0
        case icon
        case description
        case billCreation
        case confirmation

        var next: WizardStep? {
            WizardStep(rawValue: rawValue + 1)
        }

        var isHeader: Bool {
            switch self {
            case .description, .billCreation, .confirmation: true
            case .name, .icon: false
            }
        }
    }

    var body: some View {
        Background(color: .backgroundMain) {
            GeometryReader { geometry in
                ZStack {
                    WizardStepContent(
                        step: step,
                        state: state,
                        focusedField: $focusedField,
                        previewFiat: Self.previewFiat,
                        descriptionCharLimit: Self.descriptionCharLimit,
                        descriptionScrollOffset: $descriptionScrollOffset
                    )

                    WizardHeroGroup(
                        step: step,
                        state: state,
                        heroNameRevealed: heroNameRevealed,
                        descriptionScrollOffset: descriptionScrollOffset,
                        focusedField: $focusedField,
                        geometry: geometry,
                        nameCharLimit: Self.nameCharLimit,
                        onPhotoPicker: { isShowingPhotoPicker = true },
                        onFilePicker: { isShowingFilePicker = true }
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
                .clipped()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled()
        .toolbar {
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
            if step == .name {
                focusedField = .name
            }
        }
        .onChange(of: step) { _, newStep in
            switch newStep {
            case .name:
                focusedField = .name
            case .description:
                focusedField = .description
            case .icon, .billCreation, .confirmation:
                focusedField = nil
            }
        }
    }

    private func advance() {
        guard let next = step.next else { return }
        descriptionScrollOffset = 0

        if step == .name {
            // Dismiss keyboard first so the layout settles before the
            // hero animation starts — prevents the ~300pt position jump
            // caused by keyboard avoidance shifting the GeometryReader.
            focusedField = nil
            heroNameRevealed = true
            DispatchQueue.main.async {
                withAnimation(.spring(duration: 0.55, bounce: 0.12)) {
                    step = next
                }
            }
            return
        }

        withAnimation(.spring(duration: 0.55, bounce: 0.12)) {
            step = next
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

// MARK: - WizardStepContent

private struct WizardStepContent: View {
    let step: CurrencyCreationWizardScreen.WizardStep
    @Bindable var state: CurrencyCreationState
    @FocusState.Binding var focusedField: CurrencyCreationWizardScreen.Field?
    let previewFiat: Quarks
    let descriptionCharLimit: Int
    @Binding var descriptionScrollOffset: CGFloat

    var body: some View {
        ZStack {
            if step == .name {
                NameStepContent()
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing),
                        removal: .move(edge: .leading)
                    ))
            }
            if step == .icon {
                IconStepContent()
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing),
                        removal: .move(edge: .leading)
                    ))
            }
            if step == .description {
                DescriptionStepContent(
                    state: state,
                    focusedField: $focusedField,
                    characterLimit: descriptionCharLimit,
                    scrollOffset: $descriptionScrollOffset
                )
                .transition(.asymmetric(
                        insertion: .move(edge: .trailing),
                        removal: .move(edge: .leading)
                    ))
            }
            if step == .billCreation {
                BillCreationStepContent(state: state, previewFiat: previewFiat)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing),
                        removal: .move(edge: .leading)
                    ))
            }
            if step == .confirmation {
                ConfirmationStepContent(previewFiat: previewFiat, state: state)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing),
                        removal: .move(edge: .leading)
                    ))
            }
        }
    }
}

// MARK: - Step Content Views

private struct NameStepContent: View {
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

private struct IconStepContent: View {
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
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct DescriptionStepContent: View {
    @Bindable var state: CurrencyCreationState
    @FocusState.Binding var focusedField: CurrencyCreationWizardScreen.Field?
    let characterLimit: Int
    @Binding var scrollOffset: CGFloat

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Reserve space for the hero header (floats above, moves with scroll)
                Color.clear
                    .frame(height: 80)

                Text("Provide a description for\nyour currency")
                    .font(.appTextLarge)
                    .foregroundStyle(Color.textMain)

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

                Color.clear
                    .frame(height: 100)
            }
            .padding(.horizontal, 20)
            .background(alignment: .top) {
                GeometryReader { proxy in
                    let y = proxy.frame(in: .scrollView).minY
                    Color.clear
                        .onAppear { scrollOffset = y }
                        .onChange(of: y) { _, newY in scrollOffset = newY }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.hidden)
    }
}

private struct BillCreationStepContent: View {
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

private struct ConfirmationStepContent: View {
    let previewFiat: Quarks
    @Bindable var state: CurrencyCreationState

    var body: some View {
        VStack(spacing: 0) {
            // Reserve space for the hero header row
            Color.clear
                .frame(height: 80)

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

// MARK: - WizardHeroGroup

/// Contains the hero icon circle and name text/field as children of an
/// AnyLayout. The layout morphs from VStack (name/icon steps) to HStack
/// (description/bill/confirmation header) — AnyLayout interpolates child
/// positions so the heroes smoothly rearrange without conditional branches.
private struct WizardHeroGroup: View {
    let step: CurrencyCreationWizardScreen.WizardStep
    @Bindable var state: CurrencyCreationState
    let heroNameRevealed: Bool
    let descriptionScrollOffset: CGFloat
    @FocusState.Binding var focusedField: CurrencyCreationWizardScreen.Field?
    let geometry: GeometryProxy
    let nameCharLimit: Int
    let onPhotoPicker: () -> Void
    let onFilePicker: () -> Void

    private var layout: AnyLayout {
        step.isHeader
            ? AnyLayout(HStackLayout(spacing: 12))
            : AnyLayout(VStackLayout(spacing: 16))
    }

    var body: some View {
        layout {
            WizardHeroCircle(
                step: step,
                selectedImage: state.selectedImage,
                onPhotoPicker: onPhotoPicker,
                onFilePicker: onFilePicker
            )

            WizardHeroNameField(
                step: step,
                state: state,
                heroNameRevealed: heroNameRevealed,
                focusedField: $focusedField,
                nameCharLimit: nameCharLimit
            )
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: frameAlignment)
        .offset(y: groupOffset + scrollAdjustment)
        .opacity(step == .billCreation ? 0 : 1)
    }

    private var frameAlignment: Alignment {
        switch step {
        case .description, .billCreation: .topLeading
        case .name, .icon, .confirmation: .top
        }
    }

    private var groupOffset: CGFloat {
        switch step {
        case .name: 93
        case .icon: geometry.size.height * 0.28
        case .description, .billCreation, .confirmation: 20
        }
    }

    private var scrollAdjustment: CGFloat {
        step == .description ? min(descriptionScrollOffset, 0) : 0
    }
}

// MARK: - WizardHeroCircle

private struct WizardHeroCircle: View {
    let step: CurrencyCreationWizardScreen.WizardStep
    let selectedImage: UIImage?
    let onPhotoPicker: () -> Void
    let onFilePicker: () -> Void

    var body: some View {
        Menu {
            Button("Photo Library", systemImage: "photo.on.rectangle") {
                onPhotoPicker()
            }
            Button("Choose File", systemImage: "folder") {
                onFilePicker()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(Color(white: 0.2))

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
            .frame(width: circleSize, height: circleSize)
            .compositingGroup()
            .clipShape(Circle())
        }
        .menuIndicator(.hidden)
        .contentTransition(.identity)
        .allowsHitTesting(step == .icon)
        .opacity(step == .name ? 0 : 1)
    }

    private var circleSize: CGFloat {
        switch step {
        case .name: 1
        case .icon: 150
        case .description, .billCreation, .confirmation: 28
        }
    }
}

// MARK: - WizardHeroNameField

/// A ZStack containing the always-visible hero name Text and a conditional
/// TextField overlay for the `.name` step. Both render the same string at
/// the same font, so the TextField sits perfectly on top. When advancing
/// from `.name`, the TextField fades out revealing the Text already there —
/// which then smoothly repositions via AnyLayout.
private struct WizardHeroNameField: View {
    let step: CurrencyCreationWizardScreen.WizardStep
    @Bindable var state: CurrencyCreationState
    let heroNameRevealed: Bool
    @FocusState.Binding var focusedField: CurrencyCreationWizardScreen.Field?
    let nameCharLimit: Int

    var body: some View {
        ZStack(alignment: .leading) {
            Text(state.currencyName.isEmpty ? " " : state.currencyName)
                .font(nameFont)
                .foregroundStyle(Color.textMain)
                .lineLimit(1)
                .opacity(heroNameRevealed ? 1 : 0)

            // Editable TextField — only on name step. Uses .identity transition
            // so SwiftUI removes it instantly (no fade), revealing the hero Text
            // already underneath at the same position/font.
            if step == .name {
                TextField("Currency Name", text: $state.currencyName)
                    .font(.appDisplayMedium)
                    .foregroundStyle(Color.textMain)
                    .multilineTextAlignment(.leading)
                    .focused($focusedField, equals: .name)
                    .transition(.identity)
                    .onChange(of: state.currencyName) { _, newValue in
                        if newValue.count > nameCharLimit {
                            state.currencyName = String(newValue.prefix(nameCharLimit))
                        }
                    }
            }
        }
    }

    private var nameFont: Font {
        switch step {
        case .name: .appDisplayMedium
        case .icon: .appDisplaySmall
        case .description, .billCreation, .confirmation: .appTextLarge
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
            Text(" ")
                .hidden()
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

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let image = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage)
            picker.dismiss(animated: true)
            if let image {
                onImagePicked(image)
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
