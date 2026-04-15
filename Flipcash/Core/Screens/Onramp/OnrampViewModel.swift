//
//  OnrampViewModel.swift
//  Code
//
//  Created by Dima Bart on 2025-08-11.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

private let logger = Logger(label: "flipcash.onramp")

/// Long-lived store for Onramp email verification deeplinks. `DeepLinkController`
/// drops incoming verifications here; `OnrampAmountScreen` observes the value
/// with `.onChange(initial: true)`, so whether the link arrived before or
/// after the sheet opened the verification is picked up through the same
/// entry point. Lives on `SessionContainer` so it survives sheet dismissal
/// but not logout.
@MainActor @Observable
final class OnrampDeeplinkInbox {
    var pendingEmailVerification: VerificationDescription?
}

@MainActor @Observable
class OnrampViewModel {

    var isShowingVerificationFlow: Bool = false

    var amountPath: [OnrampAmountPath] = []

    var verificationPath: [OnrampVerificationPath] = [] {
        didSet {
            if verificationPath.isEmpty && !oldValue.isEmpty {
                reset()
            }
        }
    }

    var coinbaseOrder: OnrampOrderResponse?

    /// True once Coinbase has accepted the order and remains true through the
    /// full committed flow: Apple Pay commit, on-chain settlement, the poll
    /// loop, the downstream `buyWithExternalFunding` swap, and while
    /// `SwapProcessingScreen` is on the nav stack. Drives the sheet-level
    /// dismiss lock — the USDF destination is a VM-owned staging ATA that only
    /// `buyWithExternalFunding` can drain, so dismissing mid-flight would
    /// strand funds with no recovery path through normal UI.
    var isProcessingPayment: Bool {
        coinbaseOrder != nil || !amountPath.isEmpty
    }

    var dialogItem: DialogItem?

    /// Display name shown on the SwapProcessing step and surfaced in logs.
    /// For buy-existing flows this is the target currency's name; for
    /// launch-new flows it's the user-chosen name of the currency being
    /// created. Fixed at init time.
    let displayName: String

    var enteredCode: String = ""
    var enteredEmail: String = ""
    var enteredAmount: String = ""

    private(set) var isResending: Bool = false

    private(set) var region: Region
    private(set) var enteredPhone: String = ""

    var payButtonState: ButtonState = .normal
    private(set) var sendCodeButtonState: ButtonState = .normal
    private(set) var sendEmailCodeState: ButtonState = .normal
    private(set) var confirmCodeButtonState: ButtonState = .normal
    private(set) var confirmEmailButtonState: ButtonState = .normal
    
    let codeLength = 6
    
    var enteredFiat: ExchangedFiat? {
        guard !enteredAmount.isEmpty else {
            return nil
        }

        guard let amount = NumberFormatter.decimal(from: enteredAmount) else {
            return nil
        }

        guard let converted = try? Quarks(fiatDecimal: amount, currencyCode: .usd, decimals: PublicKey.usdf.mintDecimals) else {
            return nil
        }

        return try? ExchangedFiat(
            converted: converted,
            rate: .oneToOne,
            mint: .usdf
        )
    }
    
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
    
    @ObservationIgnored private let session: Session
    @ObservationIgnored private let flipClient: FlipClient
    @ObservationIgnored private let owner: KeyPair
    @ObservationIgnored private let onDismiss: () -> Void

    /// Internal dispatch for the post-onramp step. Paired with the matching
    /// factory init (see `forBuying` / `forLaunching`), so cases carry exactly
    /// the data they need.
    private enum Mode {
        case buyExistingCurrency(mint: PublicKey)
        case launchNewCurrency(onUsdfReady: @MainActor @Sendable (Signature, ExchangedFiat) async throws -> SwapId)

        var logKind: String {
            switch self {
            case .buyExistingCurrency: "buy_existing"
            case .launchNewCurrency:   "launch_new"
            }
        }
    }

    @ObservationIgnored private let mode: Mode

    @ObservationIgnored private var coinbase: Coinbase!

    @ObservationIgnored private let coinbaseApiKey: String?

    @ObservationIgnored private var fundingTask: Task<Void, Never>?

    @ObservationIgnored private let phoneFormatter = PhoneFormatter()


    private var isPhoneVerified: Bool {
        session.profile?.isPhoneVerified ?? false
    }

    private var isEmailVerified: Bool {
        session.profile?.isEmailVerified ?? false
    }

    private var isAccountVerified: Bool {
        isPhoneVerified && isEmailVerified
    }

    // MARK: - Init -

    static func forBuying(
        mint: PublicKey,
        displayName: String,
        session: Session,
        flipClient: FlipClient,
        onDismiss: @escaping () -> Void
    ) -> OnrampViewModel {
        OnrampViewModel(
            displayName: displayName,
            mode: .buyExistingCurrency(mint: mint),
            session: session,
            flipClient: flipClient,
            onDismiss: onDismiss
        )
    }

    static func forLaunching(
        displayName: String,
        session: Session,
        flipClient: FlipClient,
        onDismiss: @escaping () -> Void,
        onUsdfReady: @escaping @MainActor @Sendable (Signature, ExchangedFiat) async throws -> SwapId
    ) -> OnrampViewModel {
        OnrampViewModel(
            displayName: displayName,
            mode: .launchNewCurrency(onUsdfReady: onUsdfReady),
            session: session,
            flipClient: flipClient,
            onDismiss: onDismiss
        )
    }

    private init(
        displayName: String,
        mode: Mode,
        session: Session,
        flipClient: FlipClient,
        onDismiss: @escaping () -> Void
    ) {
        self.displayName = displayName
        self.mode = mode
        self.session = session
        self.flipClient = flipClient
        self.owner = session.ownerKeyPair
        self.onDismiss = onDismiss
        self.region = phoneFormatter.currentRegion
        self.coinbaseApiKey = try? InfoPlist.value(for: "coinbase").value(for: "apiKey").string()

        self.coinbase = Coinbase(configuration: .init(bearerTokenProvider: fetchCoinbaseJWT))
    }

    deinit {
        fundingTask?.cancel()
    }
    
    // MARK: - Setters -
    
    private func reset() {
        enteredPhone  = ""
        enteredCode   = ""
        enteredEmail  = ""
        enteredAmount = ""
        
        isResending = false

        coinbaseOrder = nil

        payButtonState = .normal

        navigateToRoot()
    }
    
    func setRegion(_ region: Region) {
        self.region = region
    }
    
    // MARK: - Bindings -
    
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
    
    // MARK: - Navigation -
    
    func navigateToRoot() {
        amountPath = []
        verificationPath = []
    }

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

        navigateToVerificationOrPurchase()
    }

    private func navigateToVerificationOrPurchase() {
        // If we need to verify the phone or
        // email, we'll need to open up the
        // verification flow, otherwise, we
        // can jump straight to the purchase
        if isAccountVerified {
            createOrder()
        } else {
            Analytics.track(event: Analytics.OnrampEvent.showVerificationInfo)
            isShowingVerificationFlow = true
        }
    }
    
    // MARK: - Actions -

    func customAmountEnteredAction() {
        guard let exchangedFiat = enteredFiat else {
            return
        }

        guard let maxPerDay = session.sendLimitFor(currency: exchangedFiat.converted.currencyCode)?.maxPerDay else {
            return
        }

        guard exchangedFiat.converted <= maxPerDay else {
            logger.info("Onramp rejected: amount exceeds limit", metadata: [
                "amount": "\(exchangedFiat.converted.formatted())",
                "max_per_day": "\(maxPerDay.decimalValue)",
                "currency": "\(exchangedFiat.converted.currencyCode)",
            ])
            showAmountTooLargeError()
            return
        }

        guard exchangedFiat.converted.decimalValue >= 5.00 else {
            showAmountTooSmallError()
            return
        }

        // `reset()` clears `enteredAmount` along with verification fields,
        // so stash and restore it.
        let amount = enteredAmount
        reset()
        enteredAmount = amount
        navigateToVerificationOrPurchase()
    }
    
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
        // If the user isn't already parked on the confirm-code screen, jump
        // them there so the API call's result has somewhere to surface.
        if !isShowingVerificationFlow {
            verificationPath = [.confirmEmailCode]
            enteredEmail = verification.email
        }

        Task {
            confirmEmailButtonState = .loading
            defer {
                confirmEmailButtonState = .normal
            }

            do {
                if !isEmailVerified {
                    try await flipClient.checkEmailCode(
                        email: verification.email,
                        code: verification.code,
                        owner: owner
                    )

                    try? await session.updateProfile()
                }

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
    
    // MARK: - Coinbase -
    
    private func createOrder() {
        guard let exchangedFiat = enteredFiat else {
            return
        }

        guard let profile = session.profile, profile.canCreateCoinbaseOrder else {
            return
        }

        Analytics.onrampInvokePayment(amount: exchangedFiat.underlying)

        Task {
            try await createOnrampOrder(
                profile: profile,
                exchangedFiat: exchangedFiat
            )
        }
    }
    
    private func createOnrampOrder(profile: Profile, exchangedFiat: ExchangedFiat) async throws {
        guard let email = profile.email, let phone = profile.phone?.e164 else {
            logger.warning("createOnrampOrder invoked with incomplete profile")
            return
        }

        let id       = UUID()
        let userRef  = "\(email):\(phone)"
        let orderRef = "\(userRef):\(id)"
        
        payButtonState = .loading
        
        let ref = BetaFlags.shared.hasEnabled(.coinbaseSandbox) ? "sandbox-\(userRef)" : userRef
        
        do {
            logger.info("Creating Coinbase order", metadata: [
                "currency": "\(exchangedFiat.converted.currencyCode)",
                "purchase_quarks": "\(exchangedFiat.underlying.quarks)",
                "sandbox": "\(BetaFlags.shared.hasEnabled(.coinbaseSandbox))"
            ])
            
            guard let usdfSwapAccounts = MintMetadata.usdf.timelockSwapAccounts(owner: session.owner.authorityPublicKey) else {
                fatalError("Failed to derive USDF swap accounts")
            }
                        
            let response = try await coinbase.createOrder(request: .init(
                purchaseAmount: "\(exchangedFiat.underlying.decimalValue)",
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
            
            isShowingVerificationFlow = false
            coinbaseOrder = response
            logger.info("Coinbase order created", metadata: [
                "order_id": "\(response.id)"
            ])
        }

        catch let error as OnrampErrorResponse {
            if error.errorType == .guestRegionForbidden {
                showCoinbaseError(
                    title: error.title,
                    subtitle: error.subtitle
                ) { [weak self] in
                    Task {
                        try? await self?.session.unlinkProfile()
                    }
                }
            } else {
                showCoinbaseError(
                    title: error.title,
                    subtitle: error.subtitle
                )
            }

            logger.error("Coinbase order failed", metadata: [
                "error_type": "\(error.errorType)",
                "error_title": "\(error.title)"
            ])
            ErrorReporting.captureError(error)
            payButtonState = .normal
        }

        catch {
            logger.error("Coinbase order failed with unexpected error", metadata: [
                "error": "\(error)"
            ])
            ErrorReporting.captureError(error)
            payButtonState = .normal
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
            payButtonState = .normal
            coinbaseOrder = nil

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

            dialogItem = .init(
                style: .destructive,
                title: title,
                subtitle: subtitle,
                dismissable: true,
            ) {
                .okay(kind: .destructive) { [weak self] in
                    self?.onDismiss()
                }
            }

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
            payButtonState = .normal
        case .none:
            logger.warning("Apple Pay received unknown event", metadata: ["raw_event": "\(event.name)"])
        }
    }
    
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
    
    // MARK: - Buy -

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
        logger.info("Coinbase funding succeeded", metadata: [
            "destination_kind": "\(mode.logKind)",
            "destination_name": "\(displayName)"
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
            // View model was deallocated or task was cancelled mid-poll. The user
            // already navigated away — no UI update needed.
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
            showSandboxOrderCompleted()
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

        guard let exchangedFiat = makeUsdfSwapAmount(from: order) else {
            logger.error("Failed to construct swap amount from order", metadata: [
                "order_id": "\(orderId)"
            ])
            showBuyFailedDialog()
            return
        }

        do {
            let swapId: SwapId
            switch mode {
            case .buyExistingCurrency(let mint):
                swapId = try await session.buyWithExternalFunding(
                    amount: exchangedFiat,
                    of: mint,
                    transactionSignature: signature
                )

            case .launchNewCurrency(let onUsdfReady):
                swapId = try await onUsdfReady(signature, exchangedFiat)
            }
            coinbaseOrder = nil
            Analytics.onrampCompleted(
                amount: exchangedFiat.underlying,
                successful: true,
                error: nil
            )
            amountPath.append(.swapProcessing(
                swapId: swapId,
                currencyName: displayName,
                amount: exchangedFiat
            ))
        } catch {
            logger.error("Buy failed", metadata: ["error": "\(error)"])
            ErrorReporting.captureError(error)
            showBuyFailedDialog()
        }
    }

    // MARK: - Dialog Factories -

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

    // MARK: - Errors -

    private func showCoinbaseError(title: String, subtitle: String, onDismiss: (() -> Void)? = nil) {
        presentDestructiveDialog(title: title, subtitle: subtitle) {
            onDismiss?()
        }
    }

    private func showGenericError(action: @escaping DialogAction.DialogActionHandler = {}) {
        presentDestructiveDialog(
            title: "Something Went Wrong",
            subtitle: "Please try again later",
            action: action
        )
    }

    private func showAmountTooSmallError() {
        presentDestructiveDialog(
            title: "$5 Minimum Purchase",
            subtitle: "Please enter an amount of $5 or higher"
        )
    }

    private func showAmountTooLargeError() {
        presentDestructiveDialog(
            title: "Amount Too Large",
            subtitle: "Please enter a smaller amount"
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

    private func showSandboxOrderCompleted() {
        payButtonState = .normal
        coinbaseOrder = nil
        dialogItem = .init(
            style: .success,
            title: "Sandbox Order Completed",
            subtitle: "The buy is skipped in sandbox mode.",
            dismissable: true,
        ) {
            .okay(kind: .standard) { [weak self] in
                self?.onDismiss()
            }
        }
    }

    private func showBuyFailedDialog() {
        payButtonState = .normal
        coinbaseOrder = nil
        presentDestructiveDialog(
            title: "Couldn't Buy Token",
            subtitle: "Your USDF is in your wallet. Try again from the currency screen."
        ) { [weak self] in
            self?.onDismiss()
        }
    }
}

// MARK: - Paths -

/// Navigation path for `OnrampAmountScreen`'s NavigationStack. Exhaustive on
/// its own — the verification flow has its own path type so the two stacks
/// never bind the same `[Path]` array.
enum OnrampAmountPath: Hashable {
    case swapProcessing(swapId: SwapId, currencyName: String, amount: ExchangedFiat)
}

/// Navigation path for `VerifyInfoScreen`'s NavigationStack.
enum OnrampVerificationPath: Hashable {
    case info
    case enterPhoneNumber
    case confirmPhoneNumberCode
    case enterEmail
    case confirmEmailCode
}

private enum Origin: Int {
    case root
    case info
    case phone
    case email
    case payment
}

// MARK: - Profile -

extension Profile {
    var canCreateCoinbaseOrder: Bool {
        phone != nil && email?.isEmpty == false
    }
}

// MARK: - CharacterSet -

private extension CharacterSet {
    static let numbers: CharacterSet = CharacterSet(charactersIn: "0123456789")
}


// MARK: - OnrampError -

enum OnrampError: Error {
    case coinbaseOrderFailed(status: String)
    case coinbaseOrderPollTimeout
    case missingCoinbaseApiKey
}

