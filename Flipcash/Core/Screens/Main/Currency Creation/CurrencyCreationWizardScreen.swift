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

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var client: Client
    @EnvironmentObject private var flipClient: FlipClient
    @Environment(Session.self) private var session
    @Environment(RatesController.self) private var ratesController
    @Environment(AppRouter.self) private var router

    @State private var step: WizardStep = .name
    @State private var direction: Direction = .forward
    @State private var compressTask: Task<Void, Never>?
    @State private var validationTask: Task<Void, Never>?
    @State private var isValidating: Bool = false
    @State private var errorDialog: DialogItem?
    @FocusState private var focusedField: Field?

    @State private var isShowingPhotoPicker = false
    @State private var isShowingFilePicker = false

    /// Non-nil while a launch is in flight. Drives a `fullScreenCover` that
    /// presents `CurrencyLaunchProcessingScreen`.
    @State private var launchContext: LaunchContext?
    /// Mint from an earlier attempt whose buy failed inline. On a
    /// `nameExists` retry, reuse it so only the buy reruns. Bound to
    /// `name` — renaming invalidates.
    @State private var createdMint: CreatedMintRecord?

    private struct CreatedMintRecord {
        let mint: PublicKey
        let name: String
    }

    private struct LaunchContext: Identifiable, Hashable {
        let swapId: SwapId
        let launchedMint: PublicKey
        let currencyName: String
        let amount: ExchangedFiat
        /// The token that paid the launch cost, for analytics.
        let paymentMint: PublicKey

        var id: String { swapId.publicKey.base58 }
    }

    static let iconCircleSize: CGFloat = 150

    /// USDF amount the user buys to mint their first bill. Driven by the
    /// server-supplied `newCurrencyPurchaseAmount` user flag and falls back to
    /// zero quarks until flags are loaded. Displayed on the preview bill.
    private var launchAmount: ExchangedFiat {
        let quarks = session.userFlags?.newCurrencyPurchaseAmount.quarks ?? 0
        return ExchangedFiat.compute(
            onChainAmount: TokenAmount(quarks: quarks, mint: .usdf),
            rate: .oneToOne,
            supplyQuarks: 0
        )
    }

    /// USDF amount the user pays as a launch fee, on top of `launchAmount`.
    /// Defaults to zero until flags load.
    private var launchFee: ExchangedFiat {
        let quarks = session.userFlags?.newCurrencyFeeAmount.quarks ?? 0
        return ExchangedFiat.compute(
            onChainAmount: TokenAmount(quarks: quarks, mint: .usdf),
            rate: .oneToOne,
            supplyQuarks: 0
        )
    }

    /// Total USDF charged to the user to launch the currency
    /// (`launchAmount + launchFee`). Used for the CTA button copy, the
    /// reserves-affordability check, and every funding flow.
    private var totalLaunchCost: ExchangedFiat {
        launchAmount.adding(launchFee)
    }

    private var previewFiat: FiatAmount {
        FiatAmount(
            value: launchAmount.onChainAmount.decimalValue,
            currency: .usd
        )
    }

    /// True while a launch is preflighting or its processing cover is up.
    private var isPayInFlight: Bool {
        isValidating || launchContext != nil
    }

    enum Field: Hashable {
        case name
        case description
    }

    enum WizardStep: Int, CaseIterable {
        case name = 0, icon, description, billCreation, confirmation, paymentSelection

        var next: WizardStep? { WizardStep(rawValue: rawValue + 1) }
        var previous: WizardStep? { WizardStep(rawValue: rawValue - 1) }

        /// Whether this step joins the progress bar. The payment picker shows a
        /// title instead, so it opts out — the bar's total derives from this, not
        /// a hard-coded count.
        var showsProgressBar: Bool { self != .paymentSelection }

        /// Number of steps the progress bar counts.
        static let progressStepCount = allCases.filter(\.showsProgressBar).count
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
                        characterLimit: CurrencyNameValidator.maxLength,
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
                        characterLimit: CurrencyCreationState.descriptionCharLimit,
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
                    // `isPayInFlight`, not `isValidating` — the CTA must stay
                    // disabled while the launch cover is up.
                    ConfirmationStep(
                        state: state,
                        previewFiat: previewFiat,
                        totalLaunchCost: totalLaunchCost,
                        isValidating: isPayInFlight,
                        onBuy: onPayToCreateTap
                    )
                    .transition(direction.slide)

                case .paymentSelection:
                    PaymentSelectionStep(
                        viewModel: CurrencyPaymentSelectionViewModel(
                            launchCost: totalLaunchCost.onChainAmount,
                            // The launch flow prices everything in USD — the
                            // rows must match the "$20" the CTA promised.
                            displayRate: .oneToOne,
                            session: session,
                            ratesController: ratesController
                        ),
                        isLaunching: isPayInFlight,
                        onConfirm: { launchAndBuy(payment: $0) }
                    )
                    .transition(direction.slide)
                }
            }
        }
        .dialog(item: $errorDialog)
        // The picker step names itself; the creation steps show the progress bar.
        .navigationTitle(step.showsProgressBar ? "" : "Select Payment Currency")
        .toolbarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .interactiveDismissDisabled()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: goBack) {
                    Image(systemName: "chevron.backward")
                        .foregroundStyle(Color.textMain)
                }
            }
            if step.showsProgressBar {
                ToolbarItem(placement: .principal) {
                    CreationProgressBar(
                        current: step.rawValue + 1,
                        total: WizardStep.progressStepCount
                    )
                }
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
        .fullScreenCover(item: $launchContext) { context in
            NavigationStack {
                CurrencyLaunchProcessingScreen(
                    swapId: context.swapId,
                    launchedMint: context.launchedMint,
                    currencyName: context.currencyName,
                    launchAmount: context.amount,
                    paymentMint: context.paymentMint
                )
                .environment(\.dismissParentContainer, {
                    // Sheet dismiss unmounts the wizard, taking the
                    // fullScreenCover with it as a single animation.
                    // Nilling the cover binding here would stage a separate
                    // cover-dismiss before the sheet animation; the @State
                    // is freed automatically when the wizard unmounts.
                    router.dismissSheet()
                })
            }
        }
        .onAppear {
            if step == .name { focusedField = .name }
        }
        .onChange(of: step) { _, newStep in
            switch newStep {
            case .name: focusedField = .name
            case .description: focusedField = .description
            case .icon, .billCreation, .confirmation, .paymentSelection: focusedField = nil
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

            guard let name = state.validatedCurrencyName else { return }

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
                errorDialog = DialogItem.error(
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
                errorDialog = DialogItem.error(
                    title: "This Name is Not Allowed",
                    subtitle: "Try a different currency name"
                )
                return
            } catch ErrorModeration.unsupportedLanguage {
                logger.info("Currency name moderation: unsupported language")
                errorDialog = DialogItem.error(
                    title: "Couldn't Check This Name",
                    subtitle: "Try a different name."
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
                errorDialog = DialogItem.error(
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
                errorDialog = DialogItem.error(
                    title: "This Image is Not Allowed",
                    subtitle: "Try a different image"
                )
                return
            } catch ErrorModeration.unsupportedFormat {
                logger.info("Currency icon format unsupported")
                errorDialog = DialogItem.error(
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
                errorDialog = DialogItem.error(
                    title: "This Description is Not Allowed",
                    subtitle: "Try a different description"
                )
                return
            } catch ErrorModeration.unsupportedLanguage {
                logger.info("Currency description moderation: unsupported language")
                errorDialog = DialogItem.error(
                    title: "Couldn't Check This Description",
                    subtitle: "Try a different description."
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

    /// Records the mint produced by a successful `session.launchCurrency`
    /// call so a subsequent retry can skip the launch step and avoid
    /// `nameExists`. No-op when `mint` is nil (operation never got past
    /// preflight). Callers pass the wizard name in effect when the snapshot
    /// was taken — success paths typically use the operation's echoed
    /// `swap.currencyName`; failure paths use the wizard's current
    /// `state.currencyName`, which a rename invalidates against `priorMint`.
    private func captureCreatedMint(_ mint: PublicKey?, name: String) {
        guard let mint else { return }
        createdMint = CreatedMintRecord(mint: mint, name: name)
    }

    private func launchAndBuyWithReserves() {
        performLaunch(paymentMint: .usdf) {
            guard let pin = await ratesController.currentPinnedState(
                for: launchAmount.nativeAmount.currency,
                mint: launchAmount.mint
            ) else { return nil }
            return { mint in
                try await session.buyNewCurrency(
                    amount: launchAmount,
                    feeAmount: launchFee,
                    verifiedState: pin,
                    mint: mint
                )
            }
        }
    }

    /// Shared launch scaffold: guards the wizard's attestations, resolves the
    /// funding proof via `prepareBuy`, launches the currency, buys the first
    /// tokens with the yielded closure, and routes every error to a dialog. On
    /// a `nameExists` collision it reuses a prior attempt's mint and reruns only
    /// the buy. `prepareBuy` returns `nil` when the proof can't be resolved.
    private func performLaunch(
        paymentMint: PublicKey,
        prepareBuy: @escaping () async -> ((PublicKey) async throws -> SwapId)?
    ) {
        validationTask?.cancel()
        validationTask = Task {
            isValidating = true
            defer { isValidating = false }

            let totalLaunchCost = self.totalLaunchCost
            let launchAmount = self.launchAmount
            let displayName = state.currencyName

            // These two guards can fail while the "Ready To Create?" dialog is
            // still tearing down — a locally-bound `.dialog(item:)` presented in
            // that window is silently dropped, so route them through
            // `session.dialogItem` (rendered in `DialogWindow` above any sheet).
            guard let nameAttestation = state.nameAttestation,
                  let iconAttestation = state.iconAttestation,
                  let descriptionAttestation = state.descriptionAttestation,
                  let iconData = state.encodedIconData else {
                logger.error("Confirmation reached without required attestations or icon")
                session.dialogItem = .error(title: "Something Went Wrong", subtitle: "Please try again")
                return
            }

            guard let buy = await prepareBuy() else {
                session.dialogItem = .error(title: "Rate Unavailable", subtitle: "Couldn't get a fresh rate. Please try again.")
                return
            }

            var launchedMint: PublicKey?
            let swapId: SwapId
            do {
                let mint = try await session.launchCurrency(
                    name: displayName,
                    description: state.currencyDescription,
                    billColors: state.backgroundColors.map { $0.hexString },
                    icon: iconData,
                    nameAttestation: nameAttestation,
                    descriptionAttestation: descriptionAttestation,
                    iconAttestation: iconAttestation
                )
                launchedMint = mint
                swapId = try await buy(mint)
            } catch ErrorLaunchCurrency.denied {
                logger.error("Launch denied after preflight attestations passed")
                ErrorReporting.captureError(ErrorLaunchCurrency.denied)
                errorDialog = DialogItem.error(
                    title: "Couldn't Launch Currency",
                    subtitle: "Please try again. Contact support if this persists."
                )
                return
            } catch ErrorLaunchCurrency.nameExists {
                // Recover when a prior attempt minted the same name but its
                // buy step failed — reuse the mint and rerun the buy directly
                // so the user isn't stranded on a server-confirmed collision.
                if let existing = createdMint, existing.name == displayName {
                    logger.info("Launch nameExists — reusing mint from prior attempt", metadata: [
                        "mint": "\(existing.mint.base58)",
                    ])
                    do {
                        let retrySwapId = try await buy(existing.mint)
                        launchContext = LaunchContext(
                            swapId: retrySwapId,
                            launchedMint: existing.mint,
                            currencyName: displayName,
                            amount: launchAmount,
                            paymentMint: paymentMint
                        )
                    } catch Session.Error.insufficientBalance {
                        presentInsufficientFundsDialog(totalLaunchCost: totalLaunchCost)
                    } catch {
                        if Task.isCancelled { return }
                        logger.error("Buy retry failed", metadata: [
                            "error": "\(error)",
                            "mint": "\(existing.mint.base58)",
                        ])
                        ErrorReporting.captureError(error)
                        presentCouldNotCreateCurrencyDialog()
                    }
                    return
                }
                logger.error("Launch name-exists after preflight CheckAvailability passed")
                ErrorReporting.captureError(ErrorLaunchCurrency.nameExists)
                errorDialog = DialogItem.error(
                    title: "Name No Longer Available",
                    subtitle: "Please pick a different name."
                )
                return
            } catch ErrorLaunchCurrency.invalidIcon {
                logger.error("Launch rejected icon after preflight moderation passed")
                ErrorReporting.captureError(ErrorLaunchCurrency.invalidIcon)
                errorDialog = DialogItem.error(
                    title: "Image Is Invalid",
                    subtitle: "Please pick a different image."
                )
                return
            } catch Session.Error.insufficientBalance {
                captureCreatedMint(launchedMint, name: displayName)
                presentInsufficientFundsDialog(totalLaunchCost: totalLaunchCost)
                return
            } catch {
                if Task.isCancelled { return }
                captureCreatedMint(launchedMint, name: displayName)
                logger.error("Launch failed", metadata: [
                    "error": "\(error)",
                    "mint": "\(launchedMint?.base58 ?? "nil")",
                ])
                ErrorReporting.captureError(error)
                presentCouldNotCreateCurrencyDialog()
                return
            }

            // Submission accepted — record the mint and present the processing screen.
            captureCreatedMint(launchedMint, name: displayName)
            launchContext = LaunchContext(
                swapId: swapId,
                launchedMint: launchedMint!,
                currencyName: displayName,
                amount: launchAmount,
                paymentMint: paymentMint
            )
        }
    }

    private func launchAndBuyWithCurrency(payment: StoredBalance) {
        performLaunch(paymentMint: payment.mint) {
            // Pin the payment currency's USD proof and derive the swap/fee split
            // at the commit moment — quarks are tied to this exact proof.
            guard let pin = await ratesController.currentPinnedState(for: .usd, mint: payment.mint),
                  let supply = pin.supplyFromBonding,
                  let split = LaunchPaymentSplit.compute(
                      purchaseUSD: launchAmount.nativeAmount.value,
                      feeUSD: launchFee.nativeAmount.value,
                      rate: pin.rate,
                      paymentMint: payment.mint,
                      supplyQuarks: supply,
                      balanceUSD: payment.usdf
                  )
            else { return nil }
            return { mint in
                try await session.buyNewCurrency(
                    amount: split.swap,
                    feeAmount: split.fee,
                    with: payment.mint,
                    verifiedState: pin,
                    mint: mint
                )
            }
        }
    }

    private func presentInsufficientFundsDialog(totalLaunchCost: ExchangedFiat) {
        logger.info("Insufficient balance to complete currency purchase")
        errorDialog = DialogItem.error(
            title: "Not Enough Funds",
            subtitle: "You need \(totalLaunchCost.nativeAmount.formatted(minimumFractionDigits: 0)) to create this currency."
        )
    }

    private func presentCouldNotCreateCurrencyDialog() {
        errorDialog = DialogItem.error(
            title: "Couldn't Create Currency",
            subtitle: "Please try again."
        )
    }

    // MARK: - Pay-to-Create dispatch

    /// "Pay X to Create" tap handler — advances to the payment-currency picker,
    /// or routes to Add Money when no balance covers the cost (checked at "Get
    /// Started", so that only fires if it dropped mid-flow).
    private func onPayToCreateTap() {
        if shouldAddMoneyBeforeLaunch(session: session, launchCost: totalLaunchCost.onChainAmount) {
            session.dialogItem = .noBalance(subtitle: AddMoneyContext.createCurrency.noBalanceSubtitle) {
                router.presentAddMoney(.createCurrency, source: .buyShortfall)
            }
        } else {
            advance()
        }
    }

    /// Routes a chosen payment currency to the matching launch path.
    private func launchAndBuy(payment: StoredBalance) {
        if payment.mint == .usdf {
            launchAndBuyWithReserves()
        } else {
            launchAndBuyWithCurrency(payment: payment)
        }
    }

    // MARK: - Dialogs

    private func presentGenericErrorDialog() {
        errorDialog = DialogItem.error(
            title: "Something Went Wrong",
            subtitle: "Please try again"
        )
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
                .characterLimit(characterLimit, text: $state.currencyName)

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
                        .characterLimit(characterLimit, text: $state.currencyDescription)

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
            .disabled(!state.isCurrencyDescriptionValid || isValidating)
            .padding(.bottom, 20)
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - BillCreationStep

private struct BillCreationStep: View {
    @Bindable var state: CurrencyCreationState
    let previewFiat: FiatAmount

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
    let previewFiat: FiatAmount
    let totalLaunchCost: ExchangedFiat
    let isValidating: Bool
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

            Button(action: onBuy) {
                if isValidating {
                    ProgressView().progressViewStyle(.circular)
                } else {
                    Text("Pay \(totalLaunchCost.nativeAmount.formatted(minimumFractionDigits: 0)) to Create")
                }
            }
            .buttonStyle(.filled)
            .disabled(isValidating)
            .padding(.top, 20)
            .padding(.bottom, 20)
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - PaymentSelectionStep

private struct PaymentSelectionStep: View {
    @State private var viewModel: CurrencyPaymentSelectionViewModel
    let isLaunching: Bool
    let onConfirm: (StoredBalance) -> Void

    init(
        viewModel: CurrencyPaymentSelectionViewModel,
        isLaunching: Bool,
        onConfirm: @escaping (StoredBalance) -> Void
    ) {
        self._viewModel = State(initialValue: viewModel)
        self.isLaunching = isLaunching
        self.onConfirm = onConfirm
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        List {
            Section {
                ForEach(viewModel.rows) { row in
                    let eligible = viewModel.isEligible(row)
                    let isUSDF = row.stored.mint == .usdf
                    // The confirmed row's chevron becomes the in-flight loader —
                    // the app never shows a full-screen loader.
                    let isPaying = isLaunching && viewModel.confirmedMint == row.stored.mint
                    CurrencyBalanceRow(
                        exchangedBalance: row,
                        accessibilityIdentifier: isUSDF ? "launch-payment-row-usdf" : "launch-payment-row",
                        accessory: isPaying ? .loader : .chevron,
                        amountStyle: .pill,
                        usesSymbol: isUSDF
                    ) {
                        viewModel.select(row, onConfirm: onConfirm)
                    }
                    .disabled(!eligible || isLaunching)
                    .opacity(eligible ? 1 : 0.4)
                }
            }
            .listRowInsets(EdgeInsets())
            .listSectionSeparator(.hidden, edges: .top)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .dialog(item: $viewModel.dialogItem)
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

// MARK: - CharacterLimit

private struct CharacterLimit: ViewModifier {
    @Binding var text: String
    let limit: Int

    func body(content: Content) -> some View {
        content
            .onChange(of: text) { _, newValue in
                if newValue.count > limit {
                    text = String(newValue.prefix(limit))
                }
            }
    }
}

private extension View {
    func characterLimit(_ limit: Int, text: Binding<String>) -> some View {
        modifier(CharacterLimit(text: text, limit: limit))
    }
}
