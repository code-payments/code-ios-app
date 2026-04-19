//
//  OnrampCoordinator.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore

private let logger = Logger(label: "flipcash.onramp-coordinator")

@MainActor
@Observable
final class OnrampCoordinator {

    // MARK: - Published state -

    /// Apple Pay order — drives the invisible WebView overlay hosted at root.
    private(set) var coinbaseOrder: OnrampOrderResponse?

    /// Non-nil when a verification sub-flow needs to present at root.
    var verificationSheet: VerificationSheetContext?

    /// Non-nil once the post-onramp swap succeeds. Drives the calling
    /// screen's processing-screen cover.
    var completion: OnrampCompletion?

    // MARK: - Dependencies -

    @ObservationIgnored private let session: Session
    @ObservationIgnored private let flipClient: FlipClient
    @ObservationIgnored private let owner: KeyPair
    @ObservationIgnored private let coinbaseApiKey: String?
    @ObservationIgnored private var coinbase: Coinbase!

    @ObservationIgnored private var pendingOperation: OnrampOperation?
    @ObservationIgnored private var pendingAmount: ExchangedFiat?
    @ObservationIgnored private var fundingTask: Task<Void, Never>?

    // MARK: - Init -

    init(session: Session, flipClient: FlipClient) {
        self.session = session
        self.flipClient = flipClient
        self.owner = session.ownerKeyPair
        self.coinbaseApiKey = try? InfoPlist.value(for: "coinbase").value(for: "apiKey").string()

        self.coinbase = Coinbase(configuration: .init(bearerTokenProvider: fetchCoinbaseJWT))
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
        let operation = OnrampOperation.buy(mint: mint, displayName: displayName, onCompleted: onCompleted)
        pendingOperation = operation
        pendingAmount = amount
        Task { await createOrder(amount: amount, operation: operation) }
    }

    func startLaunch(
        amount: ExchangedFiat,
        displayName: String,
        onCompleted: @escaping @MainActor @Sendable (Signature, ExchangedFiat) async throws -> SignedSwapResult
    ) {
        let operation = OnrampOperation.launch(displayName: displayName, onCompleted: onCompleted)
        pendingOperation = operation
        pendingAmount = amount
        Task { await createOrder(amount: amount, operation: operation) }
    }

    func cancel() {
        fundingTask?.cancel()
        fundingTask = nil
        pendingOperation = nil
        pendingAmount = nil
        coinbaseOrder = nil
        verificationSheet = nil
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
            return
        }

        guard let signature = try? Signature(base58: txHash) else {
            logger.error("Failed to decode txHash as Solana signature", metadata: [
                "tx_hash": "\(txHash)",
                "tx_hash_length": "\(txHash.count)"
            ])
            return
        }

        guard let amount = makeUsdfSwapAmount(from: order) else {
            logger.error("Failed to construct swap amount from order", metadata: [
                "order_id": "\(orderId)"
            ])
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

            pendingOperation = nil
            pendingAmount = nil
            coinbaseOrder = nil
        } catch {
            logger.error("Buy failed", metadata: ["error": "\(error)"])
            ErrorReporting.captureError(error)
        }
    }
}

// MARK: - Supporting types -

struct VerificationSheetContext: Identifiable, Hashable {
    enum Entry { case info, phone, email }

    let id: UUID = UUID()
    let entry: Entry
    let reason: OnrampOperation.LogKindWrapper  // placeholder hashable wrapper
}

extension OnrampOperation {
    /// Hashable wrapper so `OnrampOperation` itself (which carries closures)
    /// doesn't need Hashable conformance.
    struct LogKindWrapper: Hashable {
        let value: String
    }
}
