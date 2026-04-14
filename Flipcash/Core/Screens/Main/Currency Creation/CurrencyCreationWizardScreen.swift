//
//  CurrencyCreationWizardScreen.swift
//  Flipcash
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
    @State private var compressTask: Task<Void, Never>?
    @FocusState private var focusedField: Field?

    @State private var isShowingPhotoPicker = false
    @State private var isShowingFilePicker = false
    @State private var isShowingFundingSheet = false

    static let nameCharLimit = 25
    static let descriptionCharLimit = 500
    static let iconCircleSize: CGFloat = 150

    private static let previewFiat = Quarks(fiatUnsigned: 20, currencyCode: .usd, decimals: 6)

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

        var slide: AnyTransition {
            switch self {
            case .forward:
                .asymmetric(insertion: .move(edge: .trailing),
                            removal: .move(edge: .leading))
            case .backward:
                .asymmetric(insertion: .move(edge: .leading),
                            removal: .move(edge: .trailing))
            }
        }
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
                    .transition(direction.slide)

                case .icon:
                    IconStep(
                        state: state,
                        onPhotoPicker: { isShowingPhotoPicker = true },
                        onFilePicker: { isShowingFilePicker = true },
                        onNext: advance
                    )
                    .transition(direction.slide)

                case .description:
                    DescriptionStep(
                        state: state,
                        focusedField: $focusedField,
                        characterLimit: Self.descriptionCharLimit,
                        onNext: advance
                    )
                    .transition(direction.slide)

                case .billCreation:
                    BillCreationStep(
                        state: state,
                        previewFiat: Self.previewFiat
                    )
                    .transition(direction.slide)

                case .confirmation:
                    ConfirmationStep(
                        state: state,
                        previewFiat: Self.previewFiat,
                        onBuy: { isShowingFundingSheet = true }
                    )
                    .transition(direction.slide)
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
            ImagePickerWithEditor(
                onImagePicked: setSelectedImage,
                onDismiss: { isShowingPhotoPicker = false }
            )
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
        // `direction` must be set outside `withAnimation` so the transition
        // modifier captures the new edge when SwiftUI evaluates the push.
        direction = .forward
        withAnimation(.easeInOut(duration: 0.3)) {
            step = next
        }
    }

    private func goBack() {
        if let previous = step.previous {
            direction = .backward
            withAnimation(.easeInOut(duration: 0.3)) {
                step = previous
            }
        } else {
            dismiss()
        }
    }

    private func setSelectedImage(_ image: UIImage) {
        compressTask?.cancel()
        compressTask = Task {
            let compressed = await ImageCompressor.compress(image)
            guard !Task.isCancelled else { return }
            state.selectedImage = compressed
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        Task {
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            let data = await Task.detached(priority: .userInitiated) {
                try? Data(contentsOf: url)
            }.value
            guard let data, let image = UIImage(data: data) else { return }
            setSelectedImage(image)
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
                .disabled(state.currencyName.allSatisfy(\.isWhitespace))
                .padding(.bottom, 20)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - IconStep

private struct IconStep: View {
    let state: CurrencyCreationState
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
                    size: CurrencyCreationWizardScreen.iconCircleSize,
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
                .disabled(state.currencyDescription.allSatisfy(\.isWhitespace))
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
    let state: CurrencyCreationState
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
    let onDismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onImagePicked: onImagePicked, onDismiss: onDismiss)
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
        let onDismiss: () -> Void

        init(onImagePicked: @escaping (UIImage) -> Void, onDismiss: @escaping () -> Void) {
            self.onImagePicked = onImagePicked
            self.onDismiss = onDismiss
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage)
            if let image { onImagePicked(image) }
            onDismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onDismiss()
        }
    }
}
