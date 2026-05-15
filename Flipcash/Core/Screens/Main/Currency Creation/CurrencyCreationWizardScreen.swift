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
    @Environment(VerificationRouter.self) private var verificationRouter
    @Environment(CoinbaseService.self) private var coinbaseService
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
    /// Drives the `PurchaseMethodSheet` when the user picks "Pay to Create"
    /// and USDF doesn't cover the launch cost.
    @State private var pendingOperation: PaymentOperation?

    /// Non-nil while the Reserves-funded launch is in flight. Drives a
    /// `fullScreenCover` that presents `CurrencyLaunchProcessingScreen`.
    @State private var reservesLaunchContext: ReservesLaunchContext?
    /// Non-nil while an external-wallet (Phantom) launch has completed
    /// chain submission and we're showing the launch processing screen.
    @State private var phantomLaunchContext: ExternalLaunchProcessing?
    /// Non-nil while a Coinbase launch has completed and we're showing the
    /// launch processing screen.
    @State private var coinbaseLaunchContext: ExternalLaunchProcessing?
    /// In-flight funding operation (Phantom or Coinbase). For Phantom, the
    /// wizard's state observer pushes `.phantomFlow` once the operation
    /// reaches its first `awaitingUserAction` — never synchronously on
    /// assignment, so a preflight throw (NAME_EXISTS, DENIED, etc.) lets
    /// the wizard's `errorDialog` render on the wizard itself instead of
    /// being trapped under a freshly-pushed flow screen.
    @State private var fundingOperation: (any FundingOperation)?
    /// Identity of the Phantom operation we've already pushed `.phantomFlow`
    /// for. Resets when `fundingOperation` becomes `nil` (operation done) so
    /// a retry can push fresh.
    @State private var phantomFlowPushedFor: ObjectIdentifier?
    /// Mint from an earlier attempt whose buy failed inline. On a
    /// `nameExists` retry, reuse it so only the buy reruns. Bound to
    /// `name` — renaming invalidates.
    @State private var createdMint: CreatedMintRecord?
    /// Active verification flow, if any. Set when the Coinbase launch path
    /// runs the verification gate.
    @State private var verificationViewModel: VerificationViewModel?

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

    private var reserveBalance: ExchangedFiat? {
        guard let stored = session.balance(for: .usdf) else { return nil }
        guard stored.usdf.value >= totalLaunchCost.onChainAmount.decimalValue else { return nil }
        return ExchangedFiat.compute(
            onChainAmount: TokenAmount(wholeTokens: stored.usdf.value, mint: .usdf),
            rate: ratesController.rateForBalanceCurrency(),
            supplyQuarks: nil
        )
    }

    /// True while *anything* pay-related is in flight from the confirmation
    /// step — preflight validation, a queued purchase method picker, an
    /// in-flight funding operation, or an active processing cover. The CTA
    /// disables on this so the user can't double-tap into a stuck state.
    private var isPayInFlight: Bool {
        if isValidating { return true }
        if pendingOperation != nil { return true }
        if fundingOperation != nil { return true }
        if coinbaseService.coinbaseOrder != nil { return true }
        if reservesLaunchContext != nil { return true }
        if phantomLaunchContext != nil { return true }
        if coinbaseLaunchContext != nil { return true }
        return false
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
                    // The CTA disables on *any* in-flight pay state, not just
                    // validation. Without this, the button stays tappable
                    // after the user picks a method and they can re-fire the
                    // funding op while the first one is still building the
                    // Coinbase order / handshake.
                    ConfirmationStep(
                        state: state,
                        previewFiat: previewFiat,
                        totalLaunchCost: totalLaunchCost,
                        isValidating: isPayInFlight,
                        onBuy: onPayToCreateTap
                    )
                    .transition(direction.slide)
                }
            }
        }
        .dialog(item: $errorDialog)
        .dialog(item: Bindable(walletConnection).dialogItem)
        .onChange(of: fundingOperation?.state) { _, newState in
            // Single observer covers both push + reset:
            // - `nil` state → operation slot emptied → reset push tracking
            //   so a fresh op can push again on retry.
            // - First `.awaitingUserAction` transition for this op → push
            //   `.phantomFlow`. Preflight throws (NAME_EXISTS, DENIED,
            //   INVALID_ICON) then surface on the wizard's `errorDialog`
            //   instead of a stranded flow screen.
            // Assumes `PhantomFundingOperation` is single-shot per the
            // `FundingOperation` contract; identity-keyed tracking would
            // need to widen if instances ever get reused.
            guard let newState else {
                phantomFlowPushedFor = nil
                return
            }
            guard let operation = fundingOperation as? PhantomFundingOperation,
                  case .awaitingUserAction = newState else { return }
            let id = ObjectIdentifier(operation)
            guard phantomFlowPushedFor != id else { return }
            phantomFlowPushedFor = id
            router.push(.phantomFlow(operation))
        }
        .sheet(item: $verificationViewModel.cancellingOnDismiss()) { vm in
            VerifyInfoScreen(viewModel: vm)
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
        .sheet(item: $pendingOperation) { operation in
            PurchaseMethodSheet(
                operation: operation,
                sources: [.applePay, .phantom],
                applePayAction: { payment in startCoinbaseLaunchFunding(payment: payment) },
                phantomAction: { payment in startPhantomLaunchFunding(payment: payment) },
                onDismiss: { pendingOperation = nil }
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
                    // Sheet dismiss unmounts the wizard, taking the
                    // fullScreenCover with it as a single animation.
                    // Nilling the cover binding here would stage a separate
                    // cover-dismiss before the sheet animation; the @State
                    // is freed automatically when the wizard unmounts.
                    router.dismissSheet()
                })
            }
        }
        .fullScreenCover(item: $coinbaseLaunchContext) { processing in
            NavigationStack {
                CurrencyLaunchProcessingScreen(
                    swapId: processing.swapId,
                    launchedMint: processing.launchedMint,
                    currencyName: processing.currencyName,
                    launchAmount: launchAmount,
                    fundingMethod: .coinbase
                )
                .environment(\.dismissParentContainer, {
                    router.dismissSheet()
                })
            }
        }
        // The wizard only hosts launch covers — buy-existing Phantom flows
        // present their own cover from `BuyAmountScreen`. State sourced from
        // `phantomLaunchContext`, populated when the Phantom funding
        // operation returns successfully.
        .fullScreenCover(item: $phantomLaunchContext) { processing in
            NavigationStack {
                CurrencyLaunchProcessingScreen(
                    swapId: processing.swapId,
                    launchedMint: processing.launchedMint,
                    currencyName: processing.currencyName,
                    launchAmount: launchAmount,
                    fundingMethod: .phantom
                )
                .environment(\.dismissParentContainer, {
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
            } catch ErrorModeration.unsupportedLanguage {
                logger.info("Currency name moderation: unsupported language")
                errorDialog = makeDestructiveDialog(
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
            } catch ErrorModeration.unsupportedLanguage {
                logger.info("Currency description moderation: unsupported language")
                errorDialog = makeDestructiveDialog(
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
        validationTask?.cancel()
        validationTask = Task {
            isValidating = true
            defer { isValidating = false }

            let launchAmount = self.launchAmount
            let launchFee = self.launchFee
            let totalLaunchCost = self.totalLaunchCost
            let displayName = state.currencyName

            // Pack wizard state into the operation payload. The operation
            // owns the launch + buyNewCurrency sequence; the wizard catches
            // its thrown errors and routes them to the right dialog.
            guard let nameAttestation = state.nameAttestation,
                  let iconAttestation = state.iconAttestation,
                  let descriptionAttestation = state.descriptionAttestation,
                  let iconData = state.encodedIconData else {
                logger.error("Confirmation reached without required attestations or icon")
                presentGenericErrorDialog()
                return
            }

            guard let verifiedState = await ratesController.currentPinnedState(
                for: launchAmount.nativeAmount.currency,
                mint: launchAmount.mint
            ) else {
                presentGenericErrorDialog()
                return
            }

            let attestations = PaymentOperation.LaunchAttestations(
                description: state.currencyDescription,
                billColors: state.backgroundColors.map { $0.hexString },
                icon: iconData,
                nameAttestation: nameAttestation,
                descriptionAttestation: descriptionAttestation,
                iconAttestation: iconAttestation
            )

            let payload = PaymentOperation.LaunchPayload(
                currencyName: displayName,
                total: totalLaunchCost,
                launchAmount: launchAmount,
                launchFee: launchFee,
                attestations: attestations,
                verifiedState: verifiedState
            )

            let operation = ReservesFundingOperation(session: session)
            let swap: StartedSwap
            do {
                swap = try await operation.start(.launch(payload))
            } catch ErrorLaunchCurrency.denied {
                logger.error("Launch denied after preflight attestations passed")
                ErrorReporting.captureError(ErrorLaunchCurrency.denied)
                errorDialog = makeDestructiveDialog(
                    title: "Couldn't Launch Currency",
                    subtitle: "Please try again. Contact support if this persists."
                )
                return
            } catch ErrorLaunchCurrency.nameExists {
                // Recover when a prior attempt minted the same name but its
                // buyNewCurrency step failed — reuse the mint and try the buy
                // directly so the user isn't stranded on a server-confirmed
                // name collision.
                if let existing = createdMint, existing.name == displayName {
                    logger.info("Launch nameExists — reusing mint from prior attempt", metadata: [
                        "mint": "\(existing.mint.base58)",
                    ])
                    do {
                        let retrySwapId = try await session.buyNewCurrency(
                            amount: launchAmount,
                            feeAmount: launchFee,
                            verifiedState: verifiedState,
                            mint: existing.mint
                        )
                        reservesLaunchContext = ReservesLaunchContext(
                            swapId: retrySwapId,
                            launchedMint: existing.mint,
                            currencyName: displayName,
                            amount: launchAmount
                        )
                    } catch Session.Error.insufficientBalance {
                        presentInsufficientFundsDialog(totalLaunchCost: totalLaunchCost)
                    } catch {
                        if Task.isCancelled { return }
                        logger.error("Reserves-funded buy retry failed", metadata: [
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
                errorDialog = makeDestructiveDialog(
                    title: "Name No Longer Available",
                    subtitle: "Please pick a different name."
                )
                return
            } catch ErrorLaunchCurrency.invalidIcon {
                logger.error("Launch rejected icon after preflight moderation passed")
                ErrorReporting.captureError(ErrorLaunchCurrency.invalidIcon)
                errorDialog = makeDestructiveDialog(
                    title: "Image Is Invalid",
                    subtitle: "Please pick a different image."
                )
                return
            } catch Session.Error.insufficientBalance {
                captureCreatedMint(operation.launchedMint, name: displayName)
                presentInsufficientFundsDialog(totalLaunchCost: totalLaunchCost)
                return
            } catch {
                if Task.isCancelled { return }
                captureCreatedMint(operation.launchedMint, name: displayName)
                logger.error("Reserves-funded buy failed", metadata: [
                    "error": "\(error)",
                    "mint": "\(operation.launchedMint?.base58 ?? "nil")",
                ])
                ErrorReporting.captureError(error)
                presentCouldNotCreateCurrencyDialog()
                return
            }

            // Submission accepted — record the mint and present the processing screen.
            captureCreatedMint(swap.launchedMint, name: displayName)
            reservesLaunchContext = ReservesLaunchContext(
                swapId: swap.swapId,
                launchedMint: swap.launchedMint ?? operation.launchedMint!,
                currencyName: swap.currencyName,
                amount: swap.amount
            )
        }
    }

    private func presentInsufficientFundsDialog(totalLaunchCost: ExchangedFiat) {
        logger.info("Insufficient balance to complete currency purchase")
        errorDialog = makeDestructiveDialog(
            title: "Not Enough Funds",
            subtitle: "You need \(totalLaunchCost.nativeAmount.formatted()) to create this currency."
        )
    }

    private func presentCouldNotCreateCurrencyDialog() {
        errorDialog = makeDestructiveDialog(
            title: "Couldn't Create Currency",
            subtitle: "Please try again."
        )
    }

    // MARK: - Pay-to-Create dispatch

    /// "Pay X to Create" tap handler. USDF gate first — if reserves cover the
    /// total launch cost, run the reserves flow immediately. Otherwise pack
    /// the launch attestations into the payload and open the picker; the
    /// chosen funding operation runs the preflight launch + chain dance.
    private func onPayToCreateTap() {
        if reserveBalance != nil {
            launchAndBuyWithReserves()
            return
        }

        guard let attestations = makeLaunchAttestations() else {
            presentGenericErrorDialog()
            return
        }

        // If a prior funding attempt for this same name already minted the
        // currency (Phantom sign cancelled mid-flow, Apple Pay rejected
        // post-launch), reuse that mint so the next attempt skips the launch
        // RPC and doesn't hit `nameExists` on the server.
        let priorMint = (createdMint?.name == state.currencyName) ? createdMint?.mint : nil

        pendingOperation = .launch(.init(
            currencyName: state.currencyName,
            total: totalLaunchCost,
            launchAmount: launchAmount,
            launchFee: launchFee,
            attestations: attestations,
            preLaunchedMint: priorMint
        ))
    }

    private func makeLaunchAttestations() -> PaymentOperation.LaunchAttestations? {
        guard let nameAttestation = state.nameAttestation,
              let iconAttestation = state.iconAttestation,
              let descriptionAttestation = state.descriptionAttestation,
              let iconData = state.encodedIconData else {
            logger.error("onPayToCreateTap reached without required attestations or icon")
            return nil
        }
        return PaymentOperation.LaunchAttestations(
            description: state.currencyDescription,
            billColors: state.backgroundColors.map { $0.hexString },
            icon: iconData,
            nameAttestation: nameAttestation,
            descriptionAttestation: descriptionAttestation,
            iconAttestation: iconAttestation
        )
    }

    /// `PurchaseMethodSheet.phantomAction` dispatch. Spawns a Phantom
    /// funding operation; the wizard's `.onChange(of: fundingOperation?.state)`
    /// observer pushes `.phantomFlow` only when the operation reaches its
    /// first `awaitingUserAction`. Pushing synchronously would expose the
    /// flow screen during launch preflight — a NAME_EXISTS / DENIED throw
    /// would then surface its `errorDialog` underneath the flow screen.
    /// Wallet-side cancels are handled inside the operation's retry loop —
    /// they never throw out here.
    private func startPhantomLaunchFunding(payment: PaymentOperation) {
        let operation = PhantomFundingOperation(
            walletConnection: walletConnection,
            session: session
        )
        fundingOperation = operation

        Task { [operation] in
            do {
                let swap = try await operation.start(payment)
                guard let mint = swap.launchedMint else {
                    logger.error("Phantom launch returned no mint")
                    presentGenericErrorDialog()
                    return
                }
                captureCreatedMint(mint, name: swap.currencyName)
                // Don't pop the flow screen — the fullScreenCover below
                // overlays it directly. Popping first would animate the
                // flow screen sliding back to the bill view before the
                // cover slides up, which reads as the wizard "going
                // backwards" mid-success. The cover's dismissParent path
                // tears the whole wizard sheet down anyway.
                phantomLaunchContext = ExternalLaunchProcessing(
                    swapId: swap.swapId,
                    launchedMint: mint,
                    currencyName: swap.currencyName,
                    amount: swap.amount
                )
            } catch is CancellationError {
                // Local dismiss (user backed out of the flow screen) — silent.
                // Recording the mint here lets a retry skip the launch step
                // when it had already succeeded server-side mid-cancel.
                captureCreatedMint(operation.launchedMint, name: state.currencyName)
            } catch ErrorLaunchCurrency.denied {
                logger.error("Phantom launch denied after preflight attestations passed")
                ErrorReporting.captureError(ErrorLaunchCurrency.denied)
                errorDialog = makeDestructiveDialog(
                    title: "Couldn't Launch Currency",
                    subtitle: "Please try again. Contact support if this persists."
                )
            } catch ErrorLaunchCurrency.nameExists {
                logger.error("Phantom launch name-exists after preflight CheckAvailability passed")
                ErrorReporting.captureError(ErrorLaunchCurrency.nameExists)
                errorDialog = makeDestructiveDialog(
                    title: "Name No Longer Available",
                    subtitle: "Please pick a different name."
                )
            } catch ErrorLaunchCurrency.invalidIcon {
                logger.error("Phantom launch rejected icon after preflight moderation passed")
                ErrorReporting.captureError(ErrorLaunchCurrency.invalidIcon)
                errorDialog = makeDestructiveDialog(
                    title: "Image Is Invalid",
                    subtitle: "Please pick a different image."
                )
            } catch {
                captureCreatedMint(operation.launchedMint, name: state.currencyName)
                logger.error("Phantom-funded launch failed", metadata: [
                    "error": "\(error)",
                    "mint": "\(operation.launchedMint?.base58 ?? "nil")",
                ])
                ErrorReporting.captureError(error)
                errorDialog = makeDestructiveDialog(
                    title: "Couldn't Create Currency",
                    subtitle: "Please try again."
                )
            }
            if (fundingOperation as AnyObject?) === operation {
                fundingOperation = nil
            }
        }
    }

    /// `PurchaseMethodSheet.applePayAction` dispatch for launch. Runs the
    /// verification gate via `VerificationRouter`, then spawns a
    /// `CoinbaseFundingOperation` that performs the preflight launch
    /// internally followed by the Coinbase order + Apple Pay flow.
    private func startCoinbaseLaunchFunding(payment: PaymentOperation) {
        verificationRouter.runGated(
            for: session,
            bind: { verificationViewModel = $0 }
        ) {
            runCoinbaseLaunchOperation(payment: payment)
        }
    }

    private func runCoinbaseLaunchOperation(payment: PaymentOperation) {
        let operation = CoinbaseFundingOperation(
            coinbaseService: coinbaseService,
            session: session
        )
        fundingOperation = operation

        Task { [operation] in
            do {
                let swap = try await operation.start(payment)
                guard let mint = swap.launchedMint else {
                    logger.error("Coinbase launch returned no mint")
                    presentGenericErrorDialog()
                    return
                }
                captureCreatedMint(mint, name: swap.currencyName)
                coinbaseLaunchContext = ExternalLaunchProcessing(
                    swapId: swap.swapId,
                    launchedMint: mint,
                    currencyName: swap.currencyName,
                    amount: swap.amount
                )
            } catch is CancellationError {
                // Local dismiss — silent. Recording the mint here lets a
                // retry skip the launch step when it had already succeeded
                // server-side mid-cancel.
                captureCreatedMint(operation.launchedMint, name: state.currencyName)
                // Distinguish the 60s idle-timeout cancel (surface the
                // dialog above the wizard sheet) from a plain user-dismiss
                // (silent — they explicitly walked away).
                if operation.didTimeOut {
                    session.dialogItem = .applePaySheetTimeout
                }
            } catch ErrorLaunchCurrency.denied {
                ErrorReporting.captureError(ErrorLaunchCurrency.denied)
                errorDialog = makeDestructiveDialog(
                    title: "Couldn't Launch Currency",
                    subtitle: "Please try again. Contact support if this persists."
                )
            } catch ErrorLaunchCurrency.nameExists {
                ErrorReporting.captureError(ErrorLaunchCurrency.nameExists)
                errorDialog = makeDestructiveDialog(
                    title: "Name No Longer Available",
                    subtitle: "Please pick a different name."
                )
            } catch ErrorLaunchCurrency.invalidIcon {
                ErrorReporting.captureError(ErrorLaunchCurrency.invalidIcon)
                errorDialog = makeDestructiveDialog(
                    title: "Image Is Invalid",
                    subtitle: "Please pick a different image."
                )
            } catch {
                captureCreatedMint(operation.launchedMint, name: state.currencyName)
                logger.error("Coinbase-funded launch failed", metadata: [
                    "error": "\(error)",
                    "mint": "\(operation.launchedMint?.base58 ?? "nil")",
                ])
                ErrorReporting.captureError(error)
                errorDialog = makeDestructiveDialog(
                    title: "Couldn't Create Currency",
                    subtitle: "Please try again."
                )
            }
            if (fundingOperation as AnyObject?) === operation {
                fundingOperation = nil
            }
        }
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
                    Text("Pay \(totalLaunchCost.nativeAmount.formatted()) to Create")
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
