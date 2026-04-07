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

@MainActor @Observable
class OnrampViewModel {

    var isOnrampPresented: Bool = false

    var isShowingVerificationFlow: Bool = false

    var onrampPath: [OnrampPath] = [] {
        didSet {
            if onrampPath.isEmpty && !oldValue.isEmpty {
                reset()
            }
        }
    }

    var emailVerificationDescription: VerificationDescription? {
        didSet {
            if emailVerificationDescription == nil {
                reset()
            }
        }
    }

    var coinbaseOrder: OnrampOrderResponse?

    var dialogItem: DialogItem?

    private(set) var pendingBuyDestination: BuyDestination?

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

        let currency = ratesController.entryCurrency

        guard let rate = ratesController.rate(for: currency) else {
            logger.error("Rate not found", metadata: ["currency": "\(currency)"])
            return nil
        }

        guard let converted = try? Quarks(fiatDecimal: amount, currencyCode: currency, decimals: PublicKey.usdf.mintDecimals) else {
            return nil
        }

        return try? ExchangedFiat(
            converted: converted,
            rate: rate,
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
    
    @ObservationIgnored private let container: Container
    @ObservationIgnored private let session: Session
    @ObservationIgnored private let ratesController: RatesController
    @ObservationIgnored private let flipClient: FlipClient
    @ObservationIgnored private let owner: KeyPair

    @ObservationIgnored private var coinbase: Coinbase!

    @ObservationIgnored private var pendingCoinbaseOrderId: String?

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
    
    init(container: Container, session: Session, ratesController: RatesController) {
        self.container = container
        self.session = session
        self.ratesController = ratesController
        self.owner = session.ownerKeyPair
        self.flipClient = container.flipClient
        self.region = phoneFormatter.currentRegion

        self.coinbase = Coinbase(configuration: .init(bearerTokenProvider: fetchCoinbaseJWT))
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
    
    // MARK: - Root -
    
    func applePayWebView() -> AnyView {
        if let order = coinbaseOrder {
            AnyView(
                ApplePayWebView(url: order.paymentLink.url) { [weak self] event in
                    self?.didReceiveApplePayEvent(event: event)
                }
                .frame(width: 300, height: 300)
                .opacity(0)
                .id(order.id)
            )
        } else {
            AnyView(EmptyView())
        }
    }
    
    // MARK: - Navigation -
    
    func navigateToRoot() {
        onrampPath = []
    }
    
    func navigateToInitialVerification() {
        navigateToAmount(from: .info)
    }
    
    private func navigateToAmount(from origin: Origin) {
        if origin.rawValue < Origin.info.rawValue, (!isPhoneVerified || !isEmailVerified) {
            onrampPath.append(.info)
            return
        }
        
        if origin.rawValue < Origin.phone.rawValue, !isPhoneVerified {
            Analytics.track(event: Analytics.OnrampEvent.showEnterPhone)
            onrampPath.append(.enterPhoneNumber)
            return
        }
        
        if origin.rawValue < Origin.email.rawValue, !isEmailVerified {
            Analytics.track(event: Analytics.OnrampEvent.showEnterEmail)
            onrampPath.append(.enterEmail)
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
    
    // MARK: - Presentation -

    func presentForBuy(destination: BuyDestination) {
        pendingBuyDestination = destination
        isOnrampPresented = true
    }

    /// Clears the pending buy destination. Must be called from the Onramp sheet's
    /// `.onDisappear` rather than from `reset()` — the destination needs to survive
    /// across the internal `reset()` calls that fire during the purchase flow
    /// (e.g., when `customAmountEnteredAction` resets verification state before
    /// navigating). Stage 4 reads `pendingBuyDestination` after these resets.
    func clearPendingBuy() {
        pendingBuyDestination = nil
        pendingCoinbaseOrderId = nil
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

        // Reset stale verification state from any prior attempt, then restore the
        // amount the user just typed so `enteredFiat` resolves correctly when
        // `createOrder` reads it. `pendingBuyDestination` survives `reset()` —
        // see `clearPendingBuy()`.
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
                onrampPath.append(.confirmPhoneNumberCode)
                
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
                onrampPath.append(.confirmEmailCode)
                
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
    
    func confirmEmailFromDeeplinkAction(verification: VerificationDescription) {
        // Check to see if the user is already in the
        // verification flow. If not, we'll skip them
        // over to the email confirmation screen
        if !isShowingVerificationFlow {
            // TODO: Verify this works
            emailVerificationDescription = verification
            onrampPath = [.confirmEmailCode]
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
                
                try await Task.delay(milliseconds: 500)
            } catch ErrorCheckEmailCode.invalidCode {
                showInvalidVerificationLinkError { [weak self] in
                    Task {
                        try await self?.resendEmailCodeAction()
                    }
                } cancel: { [weak self] in
                    self?.emailVerificationDescription = nil
                }
            } catch ErrorCheckEmailCode.noVerification {
                showExpiredVerificationLinkError { [weak self] in
                    Task {
                        try await self?.resendEmailCodeAction()
                    }
                } cancel: { [weak self] in
                    self?.emailVerificationDescription = nil
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
        
        Analytics.onrampInvokePaymentCustom(amount: exchangedFiat.underlying)
        
        Task {
            try await createOnrampOrder(
                profile: profile,
                exchangedFiat: exchangedFiat
            )
        }
    }
    
    private func createOnrampOrder(profile: Profile, exchangedFiat: ExchangedFiat) async throws {
        let id       = UUID()
        let email    = profile.email!
        let phone    = profile.phone!.e164
        let userRef  = "\(email):\(phone)"
        let orderRef = "\(userRef):\(id)"
        
        payButtonState = .loading
        
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        
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
                paymentAmount: nil,
                paymentCurrency: "USD",
                purchaseAmount: f.string(from: exchangedFiat.underlying.decimalValue),
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
            pendingCoinbaseOrderId = response.order.orderId
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

            ErrorReporting.captureError(error)
            logger.error("Coinbase order failed", metadata: [
                "error_type": "\(error.errorType)",
                "error_title": "\(error.title)"
            ])
            payButtonState = .normal
        }

        catch {
            ErrorReporting.captureError(error)
            logger.error("Coinbase order failed with unexpected error", metadata: [
                "error": "\(error)"
            ])
            payButtonState = .normal
        }
    }
    
    private func didReceiveApplePayEvent(event: ApplePayEvent) {
        func errorMetadata(_ event: ApplePayEvent) -> Logger.Metadata {
            [
                "error_code": "\(event.data?.errorCode ?? "nil")",
                "error_message": "\(event.data?.errorMessage ?? "nil")"
            ]
        }

        func handleEventError(_ event: ApplePayEvent) {
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
                    self?.isOnrampPresented = false
                }
            }

            ErrorReporting.captureError(event.event!)
        }

        switch event.event {
        case .loadPending:
            logger.info("Apple Pay load pending")
        case .loadSuccess:
            logger.info("Apple Pay loaded")
        case .loadError:
            logger.error("Apple Pay load failed", metadata: errorMetadata(event))
            handleEventError(event)

        case .commitSuccess:
            logger.info("Apple Pay commit succeeded")
        case .commitError:
            logger.error("Apple Pay commit failed", metadata: errorMetadata(event))
            handleEventError(event)
        case .pollingStart:
            logger.info("Apple Pay polling started")
        case .pollingSuccess:
            logger.info("Apple Pay polling succeeded")
            Task {
                await handleCoinbaseFundingSuccess()
            }
        case .pollingError:
            logger.error("Apple Pay polling failed", metadata: errorMetadata(event))
            Analytics.onrampCompleted(
                amount: nil,
                successful: false,
                error: nil
            )
            handleEventError(event)
        case .cancelled:
            logger.info("Apple Pay cancelled")
            coinbaseOrder = nil
            payButtonState = .normal
        case .none:
            logger.warning("Apple Pay received unknown event", metadata: ["raw_event": "\(event.name)"])
        }
    }
    
    private func fetchCoinbaseJWT(method: String, path: String) async throws -> String {
        let coinbaseApiKey = try! InfoPlist.value(for: "coinbase").value(for: "apiKey").string()

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
            try await Task.sleep(for: .milliseconds(delayMs))
        }

        throw lastError ?? OnrampError.coinbaseOrderPollTimeout
    }

    /// Decodes a Coinbase-reported `txHash` as a Solana base58 transaction signature.
    /// Returns `nil` if the input is too short, contains non-base58 characters, or
    /// doesn't decode to the expected 64-byte signature length. Belt + suspenders for
    /// sandbox: the placeholder "sandbox_tx_hash" is 15 chars, real Solana signatures
    /// are 87-88 chars base58.
    private func decodeSolanaSignature(from txHash: String) -> Signature? {
        guard txHash.count >= 85, txHash.count <= 90 else {
            return nil
        }
        let bytes = Base58.toBytes(txHash)
        guard bytes.count == 64 else {
            return nil
        }
        // Force-try is safe: Key64.init only throws on invalid byte count, which the
        // guard above already excludes.
        return try! Signature(bytes)
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
              let decimal = Decimal(string: purchaseAmountString) else {
            return nil
        }

        let rate = ratesController.rateForEntryCurrency()
        guard let underlying = try? Quarks(
            fiatDecimal: decimal,
            currencyCode: .usd,
            decimals: PublicKey.usdf.mintDecimals
        ) else {
            return nil
        }

        return try? ExchangedFiat(
            underlying: underlying,
            rate: rate,
            mint: .usdf
        )
    }

    private func handleCoinbaseFundingSuccess() async {
        let destination = pendingBuyDestination

        logger.info("Coinbase funding succeeded", metadata: [
            "destination_mint": "\(destination?.mint.base58 ?? "nil")",
            "destination_name": "\(destination?.name ?? "nil")"
        ])

        guard let destination else {
            logger.warning("Funding succeeded with no pendingBuyDestination — closing sheet")
            coinbaseOrder = nil
            isOnrampPresented = false
            return
        }

        guard let orderId = pendingCoinbaseOrderId else {
            logger.error("pollingSuccess fired with no pendingCoinbaseOrderId")
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

        guard let signature = decodeSolanaSignature(from: txHash) else {
            logger.error("Failed to decode txHash as Solana signature", metadata: [
                "tx_hash": "\(txHash)",
                "tx_hash_length": "\(txHash.count)"
            ])
            showBuyFailedDialog()
            return
        }

        logger.info("Decoded Coinbase signature", metadata: [
            "tx_hash_length": "\(txHash.count)"
        ])

        guard let exchangedFiat = makeUsdfSwapAmount(from: order) else {
            logger.error("Failed to construct swap amount from order", metadata: [
                "order_id": "\(orderId)"
            ])
            showBuyFailedDialog()
            return
        }

        do {
            let swapId = try await session.buyWithExternalFunding(
                amount: exchangedFiat,
                of: destination.mint,
                transactionSignature: signature
            )
            logger.info("Buy initiated", metadata: [
                "swap_id": "\(swapId.publicKey.base58)",
                "destination_mint": "\(destination.mint.base58)",
                "exchanged_fiat_quarks": "\(exchangedFiat.underlying.quarks)"
            ])
            coinbaseOrder = nil
            Analytics.onrampCompleted(
                amount: exchangedFiat.underlying,
                successful: true,
                error: nil
            )
            onrampPath.append(.swapProcessing(
                swapId: swapId,
                currencyName: destination.name,
                amount: exchangedFiat
            ))
        } catch {
            logger.error("Buy failed", metadata: ["error": "\(error)"])
            ErrorReporting.captureError(error)
            showBuyFailedDialog()
        }
    }

    // MARK: - Errors -

    private func showCoinbaseError(title: String, subtitle: String, onDismiss: (() -> Void)? = nil) {
        dialogItem = .init(
            style: .destructive,
            title: title,
            subtitle: subtitle,
            dismissable: true,
        ) {
            .okay(kind: .destructive) {
                onDismiss?()
            }
        }
    }

    private func showGenericError(action: @escaping DialogAction.DialogActionHandler = {}) {
        dialogItem = .init(
            style: .destructive,
            title: "Something Went Wrong",
            subtitle: "Please try again later",
            dismissable: true,
        ) {
            .okay(kind: .destructive, action: action)
        }
    }
    
    private func showAmountTooSmallError() {
        dialogItem = .init(
            style: .destructive,
            title: "$5 Minimum Purchase",
            subtitle: "Please enter an amount of $5 or higher",
            dismissable: true,
        ) {
            .okay(kind: .destructive)
        }
    }
    
    private func showAmountTooLargeError() {
        dialogItem = .init(
            style: .destructive,
            title: "Amount Too Large",
            subtitle: "Please enter a smaller amount",
            dismissable: true,
        ) {
            .okay(kind: .destructive)
        }
    }
    
    private func showUnsupportedPhoneNumberError() {
        dialogItem = .init(
            style: .destructive,
            title: "Unsupported Phone Number",
            subtitle: "Please use a different phone number and try again",
            dismissable: true,
        ) {
            .okay(kind: .destructive)
        }
    }
    
    private func showInvalidEmailError() {
        dialogItem = .init(
            style: .destructive,
            title: "Invalid Email",
            subtitle: "Please enter a different email and try again",
            dismissable: true,
        ) {
            .okay(kind: .destructive)
        }
    }
    
    private func showInvalidCodeError() {
        dialogItem = .init(
            style: .destructive,
            title: "Invalid Code",
            subtitle: "Please enter the verification code that was sent to your phone number or request a new code",
            dismissable: true,
        ) {
            .okay(kind: .destructive)
        }
    }
    
    private func showInvalidVerificationLinkError(resendAction: @escaping () -> Void, cancel: @escaping () -> Void) {
        dialogItem = .init(
            style: .destructive,
            title: "Verification Link Invalid",
            subtitle: "This verification link is invalid. Please try again",
            dismissable: true,
        ) {
            .destructive("Resend Verification Code") {
                resendAction()
            };
            .cancel {
                cancel()
            }
        }
    }
    
    private func showExpiredVerificationLinkError(resendAction: @escaping () -> Void, cancel: @escaping () -> Void) {
        dialogItem = .init(
            style: .destructive,
            title: "Verification Link Expired",
            subtitle: "This verification link has expired. Please try again",
            dismissable: true,
        ) {
            .destructive("Resend Verification Code") {
                resendAction()
            };
            .cancel {
                cancel()
            }
        }
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
                self?.isOnrampPresented = false
            }
        }
    }

    private func showBuyFailedDialog() {
        payButtonState = .normal
        coinbaseOrder = nil
        dialogItem = .init(
            style: .destructive,
            title: "Couldn't Buy Token",
            subtitle: "Your USDF is in your wallet. Try again from the currency screen.",
            dismissable: true,
        ) {
            .okay(kind: .destructive) { [weak self] in
                self?.isOnrampPresented = false
            }
        }
    }
}

// MARK: - Path -

enum OnrampPath: Hashable {
    case info
    case enterPhoneNumber
    case confirmPhoneNumberCode
    case enterEmail
    case confirmEmailCode
    case swapProcessing(swapId: SwapId, currencyName: String, amount: ExchangedFiat)
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

// MARK: - BuyDestination -

extension OnrampViewModel {
    struct BuyDestination: Equatable {
        let mint: PublicKey
        let name: String
    }
}

// MARK: - OnrampError -

enum OnrampError: Error {
    case coinbaseOrderFailed(status: String)
    case coinbaseOrderPollTimeout
}

// MARK: - Mock -

extension OnrampViewModel {
    static let mock: OnrampViewModel = .init(
        container: .mock,
        session: .mock,
        ratesController: .mock
    )
}
