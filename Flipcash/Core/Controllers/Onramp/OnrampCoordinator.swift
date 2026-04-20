//
//  OnrampCoordinator.swift
//  Flipcash
//

import UIKit
import SwiftUI
import FlipcashUI
import FlipcashCore

private let logger = Logger(label: "flipcash.onramp-coordinator")

@MainActor
@Observable
final class OnrampCoordinator {

    // MARK: - Published state -

    /// Apple Pay order — drives the invisible WebView overlay hosted at root.
    private(set) var coinbaseOrder: OnrampOrderResponse?

    /// Non-nil once the post-onramp swap succeeds. Drives the calling
    /// screen's processing-screen cover.
    var completion: OnrampCompletion?

    /// Binding that surfaces only `.buyProcessing` completions so the
    /// buy-flow cover does not flash empty content when a `.launchProcessing`
    /// completion is published.
    var buyCompletionBinding: Binding<OnrampCompletion?> {
        Binding(
            get: {
                if case .buyProcessing = self.completion {
                    return self.completion
                }
                return nil
            },
            set: { newValue in
                if newValue == nil {
                    self.completion = nil
                }
            }
        )
    }

    /// Binding that surfaces only `.launchProcessing` completions so the
    /// launch-flow cover does not flash empty content when a `.buyProcessing`
    /// completion is published.
    var launchCompletionBinding: Binding<OnrampCompletion?> {
        Binding(
            get: {
                if case .launchProcessing = self.completion {
                    return self.completion
                }
                return nil
            },
            set: { newValue in
                if newValue == nil {
                    self.completion = nil
                }
            }
        )
    }

    // MARK: - Verification state -

    /// Drives the verification sheet at the root. `VerifyInfoScreen` binds to
    /// this flag to close itself via the toolbar close button.
    var isShowingVerificationFlow: Bool = false

    /// Navigation stack for the verification sub-flow sheet. When the path
    /// transitions from non-empty to empty (sheet dismissed mid-flight),
    /// the coordinator resets the transient verification state.
    var verificationPath: [OnrampVerificationPath] = [] {
        didSet {
            if verificationPath.isEmpty && !oldValue.isEmpty {
                resetVerificationState()
            }
        }
    }

    var enteredPhone: String = ""
    var enteredCode: String = ""
    var enteredEmail: String = ""

    private(set) var region: Region
    private(set) var isResending: Bool = false

    var sendCodeButtonState: ButtonState = .normal
    var sendEmailCodeState: ButtonState = .normal
    var confirmCodeButtonState: ButtonState = .normal
    var confirmEmailButtonState: ButtonState = .normal

    var dialogItem: DialogItem?

    /// True once Coinbase has accepted the order and remains true through the
    /// full committed flow: Apple Pay commit, on-chain settlement, the poll
    /// loop, the downstream `buyWithExternalFunding` swap, and while the
    /// processing screen is presented. Drives the sheet-level dismiss lock —
    /// the USDF destination is a staging ATA that only `buyWithExternalFunding`
    /// can drain, so dismissing mid-flight would strand funds with no recovery
    /// path through normal UI.
    var isProcessingPayment: Bool {
        coinbaseOrder != nil || pendingOperation != nil
    }

    let codeLength = 6

    // MARK: - Dependencies -

    @ObservationIgnored private let session: Session
    @ObservationIgnored private let flipClient: FlipClient
    @ObservationIgnored private let owner: KeyPair
    @ObservationIgnored private let coinbaseApiKey: String?
    @ObservationIgnored private var coinbase: Coinbase!

    @ObservationIgnored private var pendingOperation: OnrampOperation?
    @ObservationIgnored private var pendingAmount: ExchangedFiat?
    @ObservationIgnored private var fundingTask: Task<Void, Never>?

    @ObservationIgnored private let phoneFormatter = PhoneFormatter()

    // MARK: - Init -

    init(session: Session, flipClient: FlipClient) {
        self.session = session
        self.flipClient = flipClient
        self.owner = session.ownerKeyPair
        self.region = phoneFormatter.currentRegion
        self.coinbaseApiKey = try? InfoPlist.value(for: "coinbase").value(for: "apiKey").string()

        self.coinbase = Coinbase(configuration: .init(bearerTokenProvider: fetchCoinbaseJWT))
    }

    // MARK: - Verification derived state -

    var regionFlagStyle: Flag.Style {
        .fiat(region)
    }

    var countryCode: String {
        "+\(phoneFormatter.countryCode(for: region)!)"
    }

    var phone: Phone? {
        Phone(enteredPhone)
    }

    var canSendVerificationCode: Bool {
        phone != nil
    }

    var canSendEmailVerification: Bool {
        isEmailValid
    }

    var isCodeComplete: Bool {
        enteredCode.count >= codeLength
    }

    var isEmailValid: Bool {
        let e = enteredEmail.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !e.isEmpty, e.utf8.count <= 254 else {
            return false
        }

        return e.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil
    }

    private var isPhoneVerified: Bool {
        session.profile?.isPhoneVerified ?? false
    }

    private var isEmailVerified: Bool {
        session.profile?.isEmailVerified ?? false
    }

    private var isAccountVerified: Bool {
        isPhoneVerified && isEmailVerified
    }

    // MARK: - Verification setters & bindings -

    private func resetVerificationState() {
        enteredPhone = ""
        enteredCode = ""
        enteredEmail = ""
        isResending = false
    }

    func setRegion(_ region: Region) {
        self.region = region
    }

    var adjustingPhoneNumberBinding: Binding<String> {
        Binding { [weak self] in
            guard let self = self else { return "" }
            return self.enteredPhone

        } set: { [weak self] newValue in
            guard let self = self else { return }
            let cleanPhoneNumber = newValue.filter { character in
                CharacterSet.numbers.contains(character.unicodeScalars.first!)
            }

            let countryCode = self.phoneFormatter.countryCode(for: self.region)!
            self.enteredPhone = self.phoneFormatter.format("+\(countryCode)\(cleanPhoneNumber)")
        }
    }

    var adjustingCodeBinding: Binding<String> {
        Binding { [weak self] in
            guard let self = self else { return "" }
            return self.enteredCode

        } set: { [weak self] newValue in
            guard let self = self else { return }

            if newValue.count > self.codeLength {
                self.enteredCode = String(newValue.prefix(self.codeLength))
            } else {
                self.enteredCode = newValue
            }
        }
    }

    // MARK: - Clipboard -

    func pasteCodeFromClipboardIfPossible() {
        guard let code = codeFromClipboard() else {
            return
        }

        enteredCode = code
    }

    private func codeFromClipboard() -> String? {
        if let codeString = UIPasteboard.general.string, codeString.count == codeLength {
            let digits: [Int] = codeString.utf8.compactMap { char in
                let digit = Int(char)
                if digit >= 48 && digit <= 57 {
                    return digit
                }
                return nil
            }

            if digits.count == codeLength {
                return codeString
            }
        }
        return nil
    }

    // MARK: - Coinbase JWT -

    private func fetchCoinbaseJWT(method: String, path: String) async throws -> String {
        guard let coinbaseApiKey else {
            throw OnrampError.missingCoinbaseApiKey
        }

        return try await flipClient.fetchCoinbaseOnrampJWT(
            apiKey: coinbaseApiKey,
            owner: owner,
            method: method,
            path: path
        )
    }

    // MARK: - Public API -

    func startBuy(
        amount: ExchangedFiat,
        mint: PublicKey,
        displayName: String,
        onCompleted: @escaping @MainActor @Sendable (Signature, ExchangedFiat) async throws -> SignedSwapResult
    ) {
        guard !isProcessingPayment else { return }
        let operation = OnrampOperation.buy(mint: mint, displayName: displayName, onCompleted: onCompleted)
        pendingOperation = operation
        pendingAmount = amount
        navigateToVerificationOrPurchase(for: operation, amount: amount)
    }

    func startLaunch(
        amount: ExchangedFiat,
        displayName: String,
        onCompleted: @escaping @MainActor @Sendable (Signature, ExchangedFiat) async throws -> SignedSwapResult
    ) {
        guard !isProcessingPayment else { return }
        let operation = OnrampOperation.launch(displayName: displayName, onCompleted: onCompleted)
        pendingOperation = operation
        pendingAmount = amount
        navigateToVerificationOrPurchase(for: operation, amount: amount)
    }

    func cancel() {
        fundingTask?.cancel()
        fundingTask = nil
        pendingOperation = nil
        pendingAmount = nil
        coinbaseOrder = nil
    }

    // MARK: - Verification navigation -

    /// Entry point invoked by `VerifyInfoScreen`'s Next button.
    func navigateToInitialVerification() {
        navigateToAmount(from: .info)
    }

    private func navigateToAmount(from origin: Origin) {
        if origin.rawValue < Origin.info.rawValue, (!isPhoneVerified || !isEmailVerified) {
            verificationPath.append(.info)
            return
        }

        if origin.rawValue < Origin.phone.rawValue, !isPhoneVerified {
            Analytics.track(event: Analytics.OnrampEvent.showEnterPhone)
            verificationPath.append(.enterPhoneNumber)
            return
        }

        if origin.rawValue < Origin.email.rawValue, !isEmailVerified {
            Analytics.track(event: Analytics.OnrampEvent.showEnterEmail)
            verificationPath.append(.enterEmail)
            return
        }

        // Verification complete — drop the sheet and kick off the order.
        guard let operation = pendingOperation, let amount = pendingAmount else {
            logger.warning("Verification completed without a pending operation")
            isShowingVerificationFlow = false
            return
        }
        isShowingVerificationFlow = false
        Task { await createOrder(amount: amount, operation: operation) }
    }

    private func navigateToVerificationOrPurchase(for operation: OnrampOperation, amount: ExchangedFiat) {
        if isAccountVerified {
            Task { await createOrder(amount: amount, operation: operation) }
        } else {
            Analytics.track(event: Analytics.OnrampEvent.showVerificationInfo)
            isShowingVerificationFlow = true
        }
    }

    // MARK: - Verification actions -

    func sendPhoneNumberCodeAction() {
        guard let phone else {
            return
        }

        Task {
            sendCodeButtonState = .loading
            defer {
                sendCodeButtonState = .normal
            }

            do {
                try await flipClient.sendVerificationCode(
                    phone: phone.e164,
                    owner: owner
                )
                try await Task.delay(milliseconds: 500)
                sendCodeButtonState = .success

                try await Task.delay(milliseconds: 500)
                verificationPath.append(.confirmPhoneNumberCode)

                Analytics.track(event: Analytics.OnrampEvent.showConfirmPhone)

                try await Task.delay(milliseconds: 500)
            }

            catch
                ErrorSendVerificationCode.invalidPhoneNumber,
                ErrorSendVerificationCode.unsupportedPhoneType
            {
                showUnsupportedPhoneNumberError()
            }

            catch {
                ErrorReporting.captureError(error)
                showGenericError()
            }
        }
    }

    func resendCodeAction() async throws {
        guard let phone else {
            return
        }

        isResending = true
        defer {
            isResending = false
        }

        do {
            try await flipClient.sendVerificationCode(
                phone: phone.e164,
                owner: owner
            )
        } catch {
            ErrorReporting.captureError(error)
        }
    }

    func confirmPhoneNumberCodeAction() {
        guard let phone else {
            return
        }

        guard isCodeComplete else {
            return
        }

        Task {
            confirmCodeButtonState = .loading
            defer {
                confirmCodeButtonState = .normal
            }

            do {
                try await flipClient.checkVerificationCode(
                    phone: phone.e164,
                    code: enteredCode,
                    owner: owner
                )

                try? await session.updateProfile()

                try await Task.delay(milliseconds: 500)
                confirmCodeButtonState = .success

                try await Task.delay(milliseconds: 500)
                navigateToAmount(from: .phone)

                try await Task.delay(milliseconds: 500)
            } catch ErrorCheckVerificationCode.invalidCode {
                showInvalidCodeError()
            } catch ErrorCheckVerificationCode.noVerification {
                showGenericError()
            } catch {
                ErrorReporting.captureError(error)
            }
        }
    }

    func sendEmailCodeAction() {
        guard isEmailValid else {
            return
        }

        Task {
            sendEmailCodeState = .loading
            defer {
                sendEmailCodeState = .normal
            }

            do {
                try await flipClient.sendEmailVerification(
                    email: enteredEmail,
                    owner: owner
                )
                try await Task.delay(milliseconds: 500)
                sendEmailCodeState = .success

                try await Task.delay(milliseconds: 500)
                verificationPath.append(.confirmEmailCode)

                Analytics.track(event: Analytics.OnrampEvent.showConfirmEmail)

                try await Task.delay(milliseconds: 500)
            } catch ErrorSendEmailCode.invalidEmailAddress {
                showInvalidEmailError()
            } catch {
                ErrorReporting.captureError(error)
                showGenericError()
            }
        }
    }

    func resendEmailCodeAction() async throws {
        guard isEmailValid else {
            return
        }

        isResending = true
        defer {
            isResending = false
        }

        do {
            try await flipClient.sendEmailVerification(
                email: enteredEmail,
                owner: owner
            )
        } catch {
            ErrorReporting.captureError(error)
        }
    }

    func applyDeeplinkVerification(_ verification: VerificationDescription) {
        guard !isEmailVerified else { return }

        // If the user isn't already parked on the confirm-code screen, jump
        // them there so the API call's result has somewhere to surface.
        if !isShowingVerificationFlow {
            verificationPath = [.confirmEmailCode]
            enteredEmail = verification.email
            isShowingVerificationFlow = true
        }

        Task {
            confirmEmailButtonState = .loading
            defer {
                confirmEmailButtonState = .normal
            }

            do {
                try await flipClient.checkEmailCode(
                    email: verification.email,
                    code: verification.code,
                    owner: owner
                )

                try? await session.updateProfile()

                try await Task.delay(milliseconds: 500)
                confirmEmailButtonState = .success

                try await Task.delay(milliseconds: 500)
                navigateToAmount(from: .email)
            } catch ErrorCheckEmailCode.invalidCode {
                showInvalidVerificationLinkError { [weak self] in
                    Task {
                        try await self?.resendEmailCodeAction()
                    }
                }
            } catch ErrorCheckEmailCode.noVerification {
                showExpiredVerificationLinkError { [weak self] in
                    Task {
                        try await self?.resendEmailCodeAction()
                    }
                }
            } catch {
                ErrorReporting.captureError(error)
                showGenericError()
            }
        }
    }

    // MARK: - Dialog factories -

    private func presentDestructiveDialog(
        title: String,
        subtitle: String,
        action: @escaping DialogAction.DialogActionHandler = {}
    ) {
        dialogItem = .init(
            style: .destructive,
            title: title,
            subtitle: subtitle,
            dismissable: true,
        ) {
            .okay(kind: .destructive, action: action)
        }
    }

    private func presentResendOrCancelDialog(title: String, subtitle: String, resendAction: @escaping () -> Void) {
        dialogItem = .init(
            style: .destructive,
            title: title,
            subtitle: subtitle,
            dismissable: true,
        ) {
            .destructive("Resend Verification Code") {
                resendAction()
            };
            .cancel()
        }
    }

    private func showGenericError(action: @escaping DialogAction.DialogActionHandler = {}) {
        presentDestructiveDialog(
            title: "Something Went Wrong",
            subtitle: "Please try again later",
            action: action
        )
    }

    private func showBuyFailedDialog() {
        coinbaseOrder = nil
        presentDestructiveDialog(
            title: "Couldn't Buy Token",
            subtitle: "Your USDF is in your wallet. Try again from the currency screen."
        )
    }

    private func showUnsupportedPhoneNumberError() {
        presentDestructiveDialog(
            title: "Unsupported Phone Number",
            subtitle: "Please use a different phone number and try again"
        )
    }

    private func showInvalidEmailError() {
        presentDestructiveDialog(
            title: "Invalid Email",
            subtitle: "Please enter a different email and try again"
        )
    }

    private func showInvalidCodeError() {
        presentDestructiveDialog(
            title: "Invalid Code",
            subtitle: "Please enter the verification code that was sent to your phone number or request a new code"
        )
    }

    private func showInvalidVerificationLinkError(resendAction: @escaping () -> Void) {
        presentResendOrCancelDialog(
            title: "Verification Link Invalid",
            subtitle: "This verification link is invalid. Please try again",
            resendAction: resendAction
        )
    }

    private func showExpiredVerificationLinkError(resendAction: @escaping () -> Void) {
        presentResendOrCancelDialog(
            title: "Verification Link Expired",
            subtitle: "This verification link has expired. Please try again",
            resendAction: resendAction
        )
    }

    // MARK: - Coinbase order -

    private func createOrder(amount: ExchangedFiat, operation: OnrampOperation) async {
        guard let profile = session.profile, profile.canCreateCoinbaseOrder else {
            logger.warning("createOrder invoked without a Coinbase-capable profile")
            return
        }

        guard let email = profile.email, let phone = profile.phone?.e164 else {
            logger.warning("createOrder invoked with incomplete profile")
            return
        }

        Analytics.onrampInvokePayment(amount: amount.underlying)

        let id       = UUID()
        let userRef  = "\(email):\(phone)"
        let orderRef = "\(userRef):\(id)"
        let ref = BetaFlags.shared.hasEnabled(.coinbaseSandbox) ? "sandbox-\(userRef)" : userRef

        do {
            logger.info("Creating Coinbase order", metadata: [
                "currency": "\(amount.converted.currencyCode)",
                "purchase_quarks": "\(amount.underlying.quarks)",
                "sandbox": "\(BetaFlags.shared.hasEnabled(.coinbaseSandbox))",
                "destination_kind": "\(operation.logKind)",
            ])

            guard let usdfSwapAccounts = MintMetadata.usdf.timelockSwapAccounts(owner: session.owner.authorityPublicKey) else {
                fatalError("Failed to derive USDF swap accounts")
            }

            let response = try await coinbase.createOrder(request: .init(
                purchaseAmount: "\(amount.underlying.decimalValue)",
                paymentCurrency: "USD",
                purchaseCurrency: "USDF",
                isQuote: false,
                destinationAddress: usdfSwapAccounts.ata.publicKey,
                email: email,
                phoneNumber: phone,
                partnerOrderRef: orderRef,
                partnerUserRef: ref,
                phoneNumberVerifiedAt: .now,
                agreementAcceptedAt: .now
            ))

            coinbaseOrder = response
            logger.info("Coinbase order created", metadata: [
                "order_id": "\(response.id)"
            ])
        }

        catch let error as OnrampErrorResponse {
            logger.error("Coinbase order failed", metadata: [
                "error_type": "\(error.errorType)",
                "error_title": "\(error.title)"
            ])
            ErrorReporting.captureError(error)
            pendingOperation = nil
            pendingAmount = nil

            if error.errorType == .guestRegionForbidden {
                presentDestructiveDialog(title: error.title, subtitle: error.subtitle) { [weak self] in
                    Task {
                        try? await self?.session.unlinkProfile()
                    }
                }
            } else {
                presentDestructiveDialog(title: error.title, subtitle: error.subtitle)
            }
        }

        catch {
            logger.error("Coinbase order failed with unexpected error", metadata: [
                "error": "\(error)"
            ])
            ErrorReporting.captureError(error)
            pendingOperation = nil
            pendingAmount = nil
        }
    }

    func receiveApplePayEvent(_ event: ApplePayEvent) {
        func errorMetadata() -> Logger.Metadata {
            [
                "error_code": "\(event.data?.errorCode ?? "nil")",
                "error_message": "\(event.data?.errorMessage ?? "nil")"
            ]
        }

        func handleEventError(_ kind: ApplePayEvent.Event) {
            coinbaseOrder = nil
            pendingOperation = nil
            pendingAmount = nil

            // Prefer the Coinbase-provided reason if we have one — users hitting
            // a region mismatch or card decline shouldn't see "Something went wrong".
            let title: String
            let subtitle: String
            if let message = event.data?.errorMessage, !message.isEmpty {
                title = "Payment Failed"
                subtitle = message
            } else {
                title = "Something Went Wrong"
                subtitle = "Please try again later"
            }
            presentDestructiveDialog(title: title, subtitle: subtitle)

            ErrorReporting.captureError(kind)
        }

        switch event.event {
        case .loadPending:
            logger.info("Apple Pay load pending")
        case .loadSuccess:
            logger.info("Apple Pay loaded")
        case .loadError:
            logger.error("Apple Pay load failed", metadata: errorMetadata())
            handleEventError(.loadError)

        case .applePayButtonPressed:
            logger.info("Apple Pay button pressed")
        case .pendingPaymentAuth:
            logger.info("Apple Pay pending payment auth")

        case .commitSuccess:
            logger.info("Apple Pay commit succeeded")
        case .commitError:
            logger.error("Apple Pay commit failed", metadata: errorMetadata())
            handleEventError(.commitError)
        case .pollingStart:
            logger.info("Apple Pay polling started")
        case .pollingSuccess:
            fundingTask?.cancel()
            fundingTask = Task { [weak self] in
                await self?.handleCoinbaseFundingSuccess()
            }
        case .pollingError:
            logger.error("Apple Pay polling failed", metadata: errorMetadata())
            Analytics.onrampCompleted(
                amount: nil,
                successful: false,
                error: nil
            )
            handleEventError(.pollingError)
        case .cancelled:
            logger.info("Apple Pay cancelled")
            coinbaseOrder = nil
            pendingOperation = nil
            pendingAmount = nil
        case .none:
            logger.warning("Apple Pay received unknown event", metadata: ["raw_event": "\(event.name)"])
        }
    }

    // MARK: - Poll + settle -

    /// Polls `GET /v2/onramp/orders/{id}` until the order reaches a terminal state
    /// (COMPLETED or FAILED) or the timeout expires. Returns the final order on
    /// success. Throws on timeout, FAILED status, or repeated network errors.
    private func pollCoinbaseOrderUntilComplete(orderId: String) async throws -> OnrampOrderResponse.Order {
        let start = Date()
        let deadline = start.addingTimeInterval(60) // sandbox completes in 250ms; 60s is generous for production
        var pollCount = 0
        var lastError: Error?

        while Date() < deadline {
            try Task.checkCancellation()
            pollCount += 1
            do {
                let response = try await coinbase.fetchOrder(orderId: orderId)
                let elapsedMs = Int(Date().timeIntervalSince(start) * 1000)
                let status = response.order.status.uppercased()

                logger.info("Coinbase order poll", metadata: [
                    "poll": "\(pollCount)",
                    "elapsed_ms": "\(elapsedMs)",
                    "status": "\(response.order.status)",
                    "tx_hash": "\(response.order.txHash ?? "nil")"
                ])

                if status.contains("COMPLETED") {
                    return response.order
                }
                if status.contains("FAILED") {
                    throw OnrampError.coinbaseOrderFailed(status: response.order.status)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as OnrampError {
                throw error
            } catch {
                lastError = error
                logger.warning("Coinbase order poll error, retrying", metadata: [
                    "poll": "\(pollCount)",
                    "error": "\(error)"
                ])
            }

            // Backoff: start at 500ms, +200ms every 5 polls
            let delayMs = 500 + (200 * (pollCount / 5))
            try await Task.delay(milliseconds: delayMs)
        }

        throw lastError ?? OnrampError.coinbaseOrderPollTimeout
    }

    /// Builds an ExchangedFiat for the buyWithExternalFunding call. The Coinbase
    /// `purchaseAmount` is a string-encoded decimal in USDF units (e.g. "5" for $5).
    /// Returns nil if the order didn't actually purchase USDF (defense against future
    /// Coinbase API changes — we always request USDF, so a mismatch indicates a server
    /// behavior change worth failing closed on).
    private func makeUsdfSwapAmount(from order: OnrampOrderResponse.Order) -> ExchangedFiat? {
        guard let purchaseCurrency = order.purchaseCurrency,
              purchaseCurrency.uppercased() == "USDF" else {
            return nil
        }

        guard let purchaseAmountString = order.purchaseAmount,
              let decimal = NumberFormatter.decimal(from: purchaseAmountString) else {
            return nil
        }

        guard let underlying = try? Quarks(
            fiatDecimal: decimal,
            currencyCode: .usd,
            decimals: PublicKey.usdf.mintDecimals
        ) else {
            return nil
        }

        return try? ExchangedFiat(
            underlying: underlying,
            rate: .oneToOne,
            mint: .usdf
        )
    }

    private func handleCoinbaseFundingSuccess() async {
        // Always release the transient onramp state when this method exits,
        // regardless of success / error / sandbox short-circuit. Without this
        // the user is stranded with `isProcessingPayment == true` and no way
        // to retry.
        defer {
            pendingOperation = nil
            pendingAmount = nil
            coinbaseOrder = nil
            fundingTask = nil
        }

        guard let operation = pendingOperation else {
            logger.error("pollingSuccess fired with no pending operation")
            return
        }

        logger.info("Coinbase funding succeeded", metadata: [
            "destination_kind": "\(operation.logKind)",
            "destination_name": "\(operation.displayName)"
        ])

        guard let orderId = coinbaseOrder?.order.orderId else {
            logger.error("pollingSuccess fired with no active Coinbase order")
            showBuyFailedDialog()
            return
        }

        // Poll Coinbase for the completed order. This runs in sandbox too — it
        // validates the full Coinbase integration (JWT scoping, GET endpoint,
        // status transitions, txHash field parsing) end-to-end on every run.
        let order: OnrampOrderResponse.Order
        do {
            order = try await pollCoinbaseOrderUntilComplete(orderId: orderId)
        } catch is CancellationError {
            logger.info("Coinbase order poll cancelled")
            return
        } catch {
            logger.error("Coinbase order poll failed", metadata: ["error": "\(error)"])
            ErrorReporting.captureError(error)
            showBuyFailedDialog()
            return
        }

        // Sandbox short-circuits the on-chain settlement — Coinbase returns a
        // placeholder tx_hash that isn't a real Solana signature. We skip the
        // buy (`buyWithExternalFunding` would reject the placeholder) but only
        // AFTER exercising the full Coinbase order polling pipeline above.
        if BetaFlags.shared.hasEnabled(.coinbaseSandbox) {
            logger.info("Sandbox order — skipping buy", metadata: [
                "order_id": "\(orderId)",
                "status": "\(order.status)",
                "tx_hash": "\(order.txHash ?? "nil")"
            ])
            return
        }

        guard let txHash = order.txHash, !txHash.isEmpty else {
            logger.error("Coinbase order completed with no txHash", metadata: [
                "order_id": "\(orderId)",
                "status": "\(order.status)"
            ])
            showBuyFailedDialog()
            return
        }

        guard let signature = try? Signature(base58: txHash) else {
            logger.error("Failed to decode txHash as Solana signature", metadata: [
                "tx_hash": "\(txHash)",
                "tx_hash_length": "\(txHash.count)"
            ])
            showBuyFailedDialog()
            return
        }

        guard let amount = makeUsdfSwapAmount(from: order) else {
            logger.error("Failed to construct swap amount from order", metadata: [
                "order_id": "\(orderId)"
            ])
            showBuyFailedDialog()
            return
        }

        let onCompletedClosure: @MainActor @Sendable (Signature, ExchangedFiat) async throws -> SignedSwapResult
        switch operation {
        case .buy(_, _, let cb):    onCompletedClosure = cb
        case .launch(_, let cb):    onCompletedClosure = cb
        }

        do {
            switch try await onCompletedClosure(signature, amount) {
            case .buyExisting(let swapId):
                self.completion = .buyProcessing(
                    swapId: swapId,
                    currencyName: operation.displayName,
                    amount: amount
                )
            case .launch(let swapId, let mint):
                self.completion = .launchProcessing(
                    swapId: swapId,
                    launchedMint: mint,
                    currencyName: operation.displayName,
                    amount: amount
                )
            }

            Analytics.onrampCompleted(
                amount: amount.underlying,
                successful: true,
                error: nil
            )
        } catch {
            logger.error("Buy failed", metadata: ["error": "\(error)"])
            ErrorReporting.captureError(error)
            showBuyFailedDialog()
        }
    }
}

// MARK: - Supporting types -

private enum Origin: Int {
    case root
    case info
    case phone
    case email
    case payment
}

private extension CharacterSet {
    static let numbers: CharacterSet = CharacterSet(charactersIn: "0123456789")
}
