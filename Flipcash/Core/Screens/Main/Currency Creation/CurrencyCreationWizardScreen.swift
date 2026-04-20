//
//  CurrencyCreationWizardScreen.swift
//  Flipcash
//

import SwiftUI
import UniformTypeIdentifiers
import FlipcashCore
import FlipcashUI

private let logger = Logger(label: "flipcash.currency-creation")

// MARK: - CurrencyCreationWizardScreen

struct CurrencyCreationWizardScreen: View {
    @Bindable var state: CurrencyCreationState
    let sessionContainer: SessionContainer

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var client: Client
    @EnvironmentObject private var flipClient: FlipClient
    @Environment(Session.self) private var session
    @Environment(RatesController.self) private var ratesController
    @Environment(WalletConnection.self) private var walletConnection
    @Environment(OnrampCoordinator.self) private var onrampCoordinator

    @State private var step: WizardStep = .name
    @State private var direction: Direction = .forward
    @State private var compressTask: Task<Void, Never>?
    @State private var validationTask: Task<Void, Never>?
    @State private var isValidating: Bool = false
    @State private var pendingCoinbaseLaunch: Bool = false
    @State private var errorDialog: DialogItem?
    @FocusState private var focusedField: Field?

    @State private var isShowingPhotoPicker = false
    @State private var isShowingFilePicker = false
    @State private var isShowingFundingSheet = false
    /// Non-nil while the Reserves-funded launch is in flight. Drives a
    /// `fullScreenCover` that presents `CurrencyLaunchProcessingScreen`.
    @State private var reservesLaunchContext: ReservesLaunchContext?
    /// Mint from an earlier attempt whose buy failed inline. On a
    /// `nameExists` retry, reuse it so only the buy reruns. Bound to
    /// `name` — renaming invalidates.
    @State private var createdMint: CreatedMintRecord?

    private struct CreatedMintRecord {
        let mint: PublicKey
        let name: String
    }

    private struct ReservesLaunchContext: Identifiable, Hashable {
        let swapId: SwapId
        let launchedMint: PublicKey
        let currencyName: String
        let amount: ExchangedFiat

        var id: String { swapId.publicKey.base58 }
    }

    static let nameCharLimit = 32
    static let descriptionCharLimit = 500
    static let iconCircleSize: CGFloat = 150

    /// USDF amount the user must buy to launch the currency. Driven by the
    /// server-supplied `newCurrencyPurchaseAmount` user flag and falls back to
    /// zero quarks until flags are loaded.
    private var launchAmount: ExchangedFiat {
        let quarks = session.userFlags?.newCurrencyPurchaseAmount.quarks ?? 0
        return ExchangedFiat.computeFromQuarks(
            quarks: quarks,
            mint: .usdf,
            rate: .oneToOne,
            supplyQuarks: 0
        )
    }

    private var previewFiat: Quarks {
        launchAmount.underlying
    }

    private var reserveBalance: ExchangedFiat? {
        guard let stored = session.balance(for: .usdf) else { return nil }
        guard stored.usdf >= launchAmount.underlying else { return nil }
        return try? ExchangedFiat(
            underlying: stored.usdf,
            rate: ratesController.rateForBalanceCurrency(),
            mint: .usdf
        )
    }

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
                        isValidating: isValidating,
                        onNext: { validateAndAdvanceName() }
                    )
                    .transition(direction.slide)

                case .icon:
                    IconStep(
                        state: state,
                        isValidating: isValidating,
                        onPhotoPicker: { isShowingPhotoPicker = true },
                        onFilePicker: { isShowingFilePicker = true },
                        onNext: { validateAndAdvanceIcon() }
                    )
                    .transition(direction.slide)

                case .description:
                    DescriptionStep(
                        state: state,
                        focusedField: $focusedField,
                        characterLimit: Self.descriptionCharLimit,
                        isValidating: isValidating,
                        onNext: { validateAndAdvanceDescription() }
                    )
                    .transition(direction.slide)

                case .billCreation:
                    BillCreationStep(
                        state: state,
                        previewFiat: previewFiat
                    )
                    .transition(direction.slide)

                case .confirmation:
                    ConfirmationStep(
                        state: state,
                        previewFiat: previewFiat,
                        launchAmount: launchAmount,
                        onBuy: { isShowingFundingSheet = true }
                    )
                    .transition(direction.slide)
                }
            }
        }
        .dialog(item: $errorDialog)
        .dialog(item: Bindable(walletConnection).dialogItem)
        .dialog(item: Bindable(onrampCoordinator).dialogItem)
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
        .sheet(isPresented: $isShowingFundingSheet, onDismiss: {
            // SwiftUI allows only one modal sheet at a time. If the user picked
            // Coinbase and they're unverified, the coordinator needs to present
            // its own verification sheet — defer the kickoff until the funding
            // sheet has fully dismissed so the two sheets don't collide.
            guard pendingCoinbaseLaunch else { return }
            pendingCoinbaseLaunch = false
            onrampCoordinator.startLaunch(
                amount: launchAmount,
                displayName: state.currencyName,
                onCompleted: { signature, amount in
                    try await launchAfterOnramp(signature: signature, amount: amount)
                }
            )
        }) {
            FundingSelectionSheet(
                reserveBalance: reserveBalance,
                isCoinbaseAvailable: session.hasCoinbaseOnramp,
                onSelectReserves: {
                    isShowingFundingSheet = false
                    launchAndBuyWithReserves()
                },
                onSelectCoinbase: {
                    pendingCoinbaseLaunch = true
                    isValidating = true
                    isShowingFundingSheet = false
                },
                onSelectPhantom: {
                    isShowingFundingSheet = false
                    beginPhantomLaunch()
                },
                onDismiss: { isShowingFundingSheet = false }
            )
        }
        .fullScreenCover(item: $reservesLaunchContext) { context in
            NavigationStack {
                CurrencyLaunchProcessingScreen(
                    swapId: context.swapId,
                    launchedMint: context.launchedMint,
                    currencyName: context.currencyName,
                    launchAmount: context.amount,
                    fundingMethod: .reserves
                )
                .environment(\.dismissParentContainer, {
                    reservesLaunchContext = nil
                    dismiss()
                })
            }
        }
        // Coinbase launch flow: the onrampCoordinator publishes `.launchProcessing`
        // once the post-onramp swap has been submitted. The cover presents
        // `CurrencyLaunchProcessingScreen` and its Done button tears down
        // the wizard so the user lands back in the discovery stack.
        .fullScreenCover(item: onrampCoordinator.launchCompletionBinding) { completion in
            if case .launchProcessing(let swapId, let launchedMint, let name, let amount) = completion {
                NavigationStack {
                    CurrencyLaunchProcessingScreen(
                        swapId: swapId,
                        launchedMint: launchedMint,
                        currencyName: name,
                        launchAmount: amount,
                        fundingMethod: .coinbase
                    )
                    .environment(\.dismissParentContainer, {
                        onrampCoordinator.completion = nil
                        isValidating = false
                        dismiss()
                    })
                }
            }
        }
        // Phantom launch flow: `WalletConnection.launchProcessing` is set
        // inside `didSignTransaction` after the user returns from signing.
        // The wizard only ever hosts launches here — buy-existing Phantom
        // flows present their own cover from `CurrencyInfoScreen`.
        .fullScreenCover(item: Bindable(walletConnection).launchProcessing) { processing in
            NavigationStack {
                CurrencyLaunchProcessingScreen(
                    swapId: processing.swapId,
                    launchedMint: processing.launchedMint,
                    currencyName: processing.currencyName,
                    launchAmount: processing.amount,
                    fundingMethod: .phantom
                )
                .environment(\.dismissParentContainer, {
                    walletConnection.dismissProcessing()
                    isValidating = false
                    dismiss()
                })
            }
        }
        .onAppear {
            if step == .name { focusedField = .name }
        }
        // On an onrampCoordinator error the Coinbase flow resets to idle without
        // publishing a completion. Mirror that by clearing `isValidating`
        // so the confirmation screen becomes interactive again. The success
        // path runs through the `.launchProcessing` cover, whose
        // `dismissParentContainer` already resets `isValidating`.
        .onChange(of: onrampCoordinator.isProcessingPayment) { _, isProcessing in
            if !isProcessing && onrampCoordinator.completion == nil {
                isValidating = false
            }
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

    // MARK: - Validation

    private func validateAndAdvanceName() {
        validationTask?.cancel()
        validationTask = Task {
            isValidating = true
            defer { isValidating = false }

            let name = state.currencyName

            // 1. Uniqueness check
            let isAvailable: Bool
            do {
                isAvailable = try await client.checkAvailability(name: name)
            } catch {
                if Task.isCancelled { return }
                logger.error("Currency name availability check failed", metadata: ["error": "\(error)"])
                ErrorReporting.captureError(error)
                presentGenericErrorDialog()
                return
            }
            if !isAvailable {
                logger.info("Currency name unavailable", metadata: ["name_length": "\(name.count)"])
                errorDialog = makeDestructiveDialog(
                    title: "This Name is Taken",
                    subtitle: "Try a different currency name"
                )
                return
            }

            // 2. Moderation
            let attestation: ModerationAttestation
            do {
                attestation = try await flipClient.moderateText(name, owner: session.ownerKeyPair)
            } catch ErrorModeration.denied(let category) {
                logger.info("Currency name moderation denied", metadata: ["category": "\(category)"])
                errorDialog = makeDestructiveDialog(
                    title: "This Name is Not Allowed",
                    subtitle: "Try a different currency name"
                )
                return
            } catch {
                if Task.isCancelled { return }
                logger.error("Currency name moderation failed", metadata: ["error": "\(error)"])
                ErrorReporting.captureError(error)
                presentGenericErrorDialog()
                return
            }

            state.nameAttestation = attestation
            advance()
        }
    }

    private func validateAndAdvanceIcon() {
        validationTask?.cancel()
        validationTask = Task {
            isValidating = true
            defer { isValidating = false }

            guard let image = state.selectedImage else {
                logger.error("Icon step triggered without a selected image")
                presentGenericErrorDialog()
                return
            }

            // 1 MB = max request size accepted by Moderation + Launch RPCs.
            let imageData: Data
            do {
                imageData = try await ImageEncoder.encodeForUpload(image, maxBytes: 1_048_576)
            } catch {
                logger.error("Failed to encode icon within 1 MB budget", metadata: ["error": "\(error)"])
                ErrorReporting.captureError(error)
                errorDialog = makeDestructiveDialog(
                    title: "Couldn't Process Image",
                    subtitle: "Try a smaller or simpler image"
                )
                return
            }
            state.encodedIconData = imageData

            let attestation: ModerationAttestation
            do {
                attestation = try await flipClient.moderateImage(imageData, owner: session.ownerKeyPair)
            } catch ErrorModeration.denied(let category) {
                logger.info("Currency icon moderation denied", metadata: ["category": "\(category)"])
                errorDialog = makeDestructiveDialog(
                    title: "This Image is Not Allowed",
                    subtitle: "Try a different image"
                )
                return
            } catch ErrorModeration.unsupportedFormat {
                logger.info("Currency icon format unsupported")
                errorDialog = makeDestructiveDialog(
                    title: "This Image Format Isn't Supported",
                    subtitle: "Use PNG, JPEG, or HEIC"
                )
                return
            } catch {
                if Task.isCancelled { return }
                logger.error("Currency icon moderation failed", metadata: ["error": "\(error)"])
                ErrorReporting.captureError(error)
                presentGenericErrorDialog()
                return
            }

            state.iconAttestation = attestation
            advance()
        }
    }

    private func validateAndAdvanceDescription() {
        validationTask?.cancel()
        validationTask = Task {
            isValidating = true
            defer { isValidating = false }

            let description = state.currencyDescription

            let attestation: ModerationAttestation
            do {
                attestation = try await flipClient.moderateText(description, owner: session.ownerKeyPair)
            } catch ErrorModeration.denied(let category) {
                logger.info("Currency description moderation denied", metadata: ["category": "\(category)"])
                errorDialog = makeDestructiveDialog(
                    title: "This Description is Not Allowed",
                    subtitle: "Try a different description"
                )
                return
            } catch {
                if Task.isCancelled { return }
                logger.error("Currency description moderation failed", metadata: ["error": "\(error)"])
                ErrorReporting.captureError(error)
                presentGenericErrorDialog()
                return
            }

            state.descriptionAttestation = attestation
            advance()
        }
    }

    // MARK: - Launch + Buy

    private func launchAndBuyWithReserves() {
        validationTask?.cancel()
        validationTask = Task {
            isValidating = true

            let launchAmount = self.launchAmount
            let displayName = state.currencyName

            // 1. Launch — must be awaited inline; its error routing (denied /
            // nameExists / invalidIcon) has to run before we navigate forward.
            guard let mint = await launchCurrencyWithPreflightRouting() else {
                isValidating = false
                return
            }

            // 2. Submit the buy — awaited inline. The stateful swap stream returns
            // only after the server-side swap record is created (state=created),
            // so a failure here means the submission never took effect. Surface
            // it as a wizard dialog rather than presenting a processing screen
            // that would poll a swap id the server never registered.
            let swapId: SwapId
            do {
                swapId = try await session.buyNewCurrency(amount: launchAmount, mint: mint)
            } catch Session.Error.insufficientBalance {
                logger.info("Insufficient balance to complete currency purchase")
                errorDialog = makeDestructiveDialog(
                    title: "Not Enough Funds",
                    subtitle: "You need \(launchAmount.converted.formatted()) to create this currency."
                )
                isValidating = false
                return
            } catch {
                if Task.isCancelled { isValidating = false; return }
                logger.error("Reserves-funded buy failed", metadata: [
                    "error": "\(error)",
                    "mint": "\(mint.base58)",
                ])
                ErrorReporting.captureError(error)
                errorDialog = makeDestructiveDialog(
                    title: "Couldn't Create Currency",
                    subtitle: "Please try again."
                )
                isValidating = false
                return
            }

            // 3. Submission accepted — hand off to the processing screen.
            reservesLaunchContext = ReservesLaunchContext(
                swapId: swapId,
                launchedMint: mint,
                currencyName: displayName,
                amount: launchAmount
            )
            isValidating = false
        }
    }

    /// Runs the Launch RPC and routes post-preflight failures (DENIED /
    /// NAME_EXISTS / INVALID_ICON) back to the offending step with an
    /// error dialog queued. Returns the new mint on success, nil on any
    /// failure (with the appropriate dialog / step navigation already
    /// applied). Shared between the reserves and Coinbase funding flows.
    private func launchCurrencyWithPreflightRouting() async -> PublicKey? {
        guard let nameAttestation = state.nameAttestation,
              let iconAttestation = state.iconAttestation,
              let descriptionAttestation = state.descriptionAttestation,
              let iconData = state.encodedIconData else {
            logger.error("Confirmation reached without required attestations or icon")
            presentGenericErrorDialog()
            return nil
        }

        let billColors = state.backgroundColors.map { $0.hexString }

        do {
            let mint = try await session.launchCurrency(
                name: state.currencyName,
                description: state.currencyDescription,
                billColors: billColors,
                icon: iconData,
                nameAttestation: nameAttestation,
                descriptionAttestation: descriptionAttestation,
                iconAttestation: iconAttestation
            )
            createdMint = CreatedMintRecord(mint: mint, name: state.currencyName)
            return mint
        } catch ErrorLaunchCurrency.denied {
            logger.error("Launch denied after preflight attestations passed")
            ErrorReporting.captureError(ErrorLaunchCurrency.denied)
            errorDialog = makeDestructiveDialog(
                title: "Couldn't Launch Currency",
                subtitle: "Please try again. Contact support if this persists."
            )
            return nil
        } catch ErrorLaunchCurrency.nameExists {
            if let existing = createdMint, existing.name == state.currencyName {
                logger.info("Launch nameExists — reusing mint from prior attempt", metadata: [
                    "mint": "\(existing.mint.base58)",
                ])
                return existing.mint
            }
            logger.error("Launch name-exists after preflight CheckAvailability passed")
            ErrorReporting.captureError(ErrorLaunchCurrency.nameExists)
            errorDialog = makeDestructiveDialog(
                title: "Name No Longer Available",
                subtitle: "Please pick a different name."
            )
            return nil
        } catch ErrorLaunchCurrency.invalidIcon {
            logger.error("Launch rejected icon after preflight moderation passed")
            ErrorReporting.captureError(ErrorLaunchCurrency.invalidIcon)
            errorDialog = makeDestructiveDialog(
                title: "Image Is Invalid",
                subtitle: "Please pick a different image."
            )
            return nil
        } catch {
            if Task.isCancelled { return nil }
            logger.error("Launch failed", metadata: ["error": "\(error)"])
            ErrorReporting.captureError(error)
            errorDialog = makeDestructiveDialog(
                title: "Couldn't Launch Currency",
                subtitle: "Check your connection and try again."
            )
            return nil
        }
    }

    /// Called by the Coinbase onramp after a successful USDF deposit. Runs
    /// the same Launch + error-routing helper used by the reserves flow,
    /// then buys the new currency with the external-funding signature.
    /// Returns the resulting `SwapId` so the onramp view model can push its
    /// `SwapProcessing` step. Throws `CancellationError` on launch failure —
    /// the wizard has already shown its own step-routed dialog, so this
    /// signals "stop" to OnrampViewModel without surfacing a second one.
    private func launchAfterOnramp(signature: Signature, amount: ExchangedFiat) async throws -> SignedSwapResult {
        guard let mint = await launchCurrencyWithPreflightRouting() else {
            throw CancellationError()
        }

        let swapId = try await session.buyNewCurrencyWithExternalFunding(
            amount: amount,
            mint: mint,
            transactionSignature: signature
        )
        logger.info("New currency purchased (external funding)")
        return .launch(swapId: swapId, mint: mint)
    }

    /// Kicks off the Phantom launch flow. Phantom signing happens out of
    /// process (deeplink), so we don't toggle `isValidating` — once Phantom
    /// returns, `WalletConnection.processing` becomes non-nil and the
    /// `fullScreenCover` takes over the UI. Any failure while *requesting*
    /// the swap surfaces a generic dialog.
    private func beginPhantomLaunch() {
        validationTask?.cancel()
        validationTask = Task {
            let displayName = state.currencyName
            do {
                if !walletConnection.isConnected {
                    try await walletConnection.connect()
                    // Returning from Phantom drops us through a brief
                    // background → inactive → active scene transition.
                    // UIApplication.shared.open is silently suppressed
                    // until the scene is fully active, so the follow-up
                    // sign request is no-op'd without this yield.
                    try await Task.sleep(for: .seconds(1))
                }
                try await walletConnection.requestSwapForLaunch(
                    usdc: launchAmount.underlying,
                    displayName: displayName,
                    onCompleted: { signature, amount in
                        try await launchAfterPhantom(signature: signature, amount: amount)
                    }
                )
            } catch is CancellationError {
                // User declined the connect request in Phantom. Surface a
                // dialog so the wizard shows visible feedback instead of
                // silently returning to the confirmation screen.
                errorDialog = makeDestructiveDialog(
                    title: "Wallet Connection Cancelled",
                    subtitle: "You cancelled the connection in your wallet. Tap Phantom again to retry."
                )
            } catch {
                if Task.isCancelled { return }
                logger.error("Failed to request Phantom swap", metadata: ["error": "\(error)"])
                ErrorReporting.captureError(error)
                presentGenericErrorDialog()
            }
        }
    }

    /// Called by `WalletConnection` after Phantom returns with a signed swap.
    /// Runs the same Launch + error-routing helper used by the reserves and
    /// Coinbase flows, then tells the server to complete the buy with the
    /// external-funding signature. Returns the resulting `SwapId` so the
    /// processing screen polls the right swap state. Throws `CancellationError`
    /// on launch failure — the wizard has already shown its step-routed
    /// dialog, so this signals "stop" to `WalletConnection.didSignTransaction`
    /// without surfacing a second one.
    private func launchAfterPhantom(signature: Signature, amount: ExchangedFiat) async throws -> SignedSwapResult {
        guard let mint = await launchCurrencyWithPreflightRouting() else {
            throw CancellationError()
        }

        let swapId = try await session.buyNewCurrencyWithExternalFunding(
            amount: amount,
            mint: mint,
            transactionSignature: signature
        )
        logger.info("New currency purchased (Phantom funding)")
        return .launch(swapId: swapId, mint: mint)
    }

    // MARK: - Dialogs

    private func presentGenericErrorDialog() {
        errorDialog = makeDestructiveDialog(
            title: "Something Went Wrong",
            subtitle: "Please try again"
        )
    }

    private func makeDestructiveDialog(title: String, subtitle: String) -> DialogItem {
        .init(
            style: .destructive,
            title: title,
            subtitle: subtitle,
            dismissable: true
        ) {
            .okay(kind: .destructive)
        }
    }
}

// MARK: - NameStep

private struct NameStep: View {
    @Bindable var state: CurrencyCreationState
    @FocusState.Binding var focusedField: CurrencyCreationWizardScreen.Field?
    let characterLimit: Int
    let isValidating: Bool
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
                .disabled(isValidating)
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

            Button(action: onNext) {
                if isValidating {
                    ProgressView().progressViewStyle(.circular)
                } else {
                    Text("Next")
                }
            }
            .buttonStyle(.filled)
            .disabled(!state.isCurrencyNameValid || isValidating)
            .padding(.bottom, 20)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - IconStep

private struct IconStep: View {
    let state: CurrencyCreationState
    let isValidating: Bool
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
            .disabled(isValidating)

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

            Button(action: onNext) {
                if isValidating {
                    ProgressView().progressViewStyle(.circular)
                } else {
                    Text("Next")
                }
            }
            .buttonStyle(.filled)
            .disabled(state.selectedImage == nil || isValidating)
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
    let isValidating: Bool
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
                        .disabled(isValidating)
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

            Button(action: onNext) {
                if isValidating {
                    ProgressView().progressViewStyle(.circular)
                } else {
                    Text("Next")
                }
            }
            .buttonStyle(.filled)
            .disabled(state.currencyDescription.allSatisfy(\.isWhitespace) || isValidating)
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
    let launchAmount: ExchangedFiat
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

            Button("Buy \(launchAmount.converted.formatted()) to Create Your Currency", action: onBuy)
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
