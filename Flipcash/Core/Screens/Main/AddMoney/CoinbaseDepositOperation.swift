//
//  CoinbaseDepositOperation.swift
//  Flipcash
//

import Foundation
import Observation
import FlipcashCore

private let logger = Logger(label: "flipcash.coinbase-deposit")

/// Deposits USDC into the user's wallet via the Coinbase Apple Pay onramp.
/// The onramp delivers USDC to the owner's ATA; converting it to USDF is the
/// in-flow `UsdcSweepOperation`'s job.
@Observable
final class CoinbaseDepositOperation {

    /// Coinbase Onramp's USD floor — orders below this amount are rejected.
    static let minimumPurchaseUSD: Decimal = 5

    private(set) var state: DepositOperationState = .idle

    /// `true` when the idle timer cancelled the run, distinguishing an Apple
    /// Pay timeout from a user cancel after a `CancellationError`.
    private(set) var didTimeOut: Bool = false

    /// The Coinbase order id of the current run, for log correlation.
    private(set) var orderId: String?

    /// Whether the current run's Apple Pay payment was authorized, so a failure after it may
    /// still deliver.
    private(set) var reachedAuthorization = false

    /// The onramp error event that ended the current run, if one did.
    private(set) var terminalError: ApplePayEvent.Event?

    @ObservationIgnored private let coinbaseService: CoinbaseService
    @ObservationIgnored private let session: any (AccountProviding & ProfileProviding)
    @ObservationIgnored private let idleTimer: ApplePayIdleTimer
    @ObservationIgnored private let confirmationTimer: ApplePayIdleTimer?
    @ObservationIgnored private let timer: AddMoneyTimer

    @ObservationIgnored private var runTask: Task<Void, Error>?
    @ObservationIgnored private var onAuthorized: (() -> Void)?

    /// `confirmationTimeout` bounds the wait for Coinbase to report a committed order complete;
    /// past it the run ends as a cancel with ``reachedAuthorization`` set. Nil waits for the report.
    init(
        coinbaseService: CoinbaseService,
        session: any (AccountProviding & ProfileProviding),
        timer: AddMoneyTimer = AddMoneyTimer(),
        applePayIdleTimeout: Duration = .seconds(60),
        confirmationTimeout: Duration? = nil
    ) {
        self.coinbaseService = coinbaseService
        self.session = session
        self.timer = timer
        self.idleTimer = ApplePayIdleTimer(timeout: applePayIdleTimeout)
        self.confirmationTimer = confirmationTimeout.map { ApplePayIdleTimer(timeout: $0) }
    }

    isolated deinit {
        runTask?.cancel()
    }

    // MARK: - Entry

    /// `orderRef` is the order's `partnerOrderRef`, a fresh one per run when nil. `onAuthorized`
    /// runs once, when Apple Pay reports the payment authorized.
    func start(amount: ExchangedFiat, orderRef: String? = nil, onAuthorized: (() -> Void)? = nil) async throws {
        reachedAuthorization = false
        terminalError = nil
        self.onAuthorized = onAuthorized
        let task = Task { try await run(amount, orderRef: orderRef) }
        runTask = task
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: { [weak self] in
            task.cancel()
            Task { @MainActor [weak self] in
                self?.coinbaseService.clearOrder()
            }
        }
    }

    func cancel() {
        runTask?.cancel()
    }

    // MARK: - Run

    /// A `partnerOrderRef` for this user's next order.
    static func makeOrderRef(owner: PublicKey) -> String {
        "\(owner.base58):\(UUID().uuidString)"
    }

    private func run(_ amount: ExchangedFiat, orderRef: String?) async throws {
        // Reset state on any exit — a throw would otherwise strand the host
        // view in `.working`.
        defer { state = .idle }

        try checkRequirements()
        try checkMinimum(amount)

        state = .working
        let order: OnrampOrderResponse
        do {
            order = try await createOrder(for: amount, orderRef: orderRef)
        } catch {
            Self.trackPurchase(amount, error: error)
            throw error
        }
        orderId = order.id
        timer.mark(.orderPlaced)
        Self.trackPurchase(amount, error: nil)
        Analytics.addMoneyPaymentInvoked(method: .coinbase, exchangedFiat: amount)

        coinbaseService.setOrder(order)
        defer { coinbaseService.clearOrder() }

        state = .awaitingExternal(.applePay)
        try await awaitApplePayCompletion(orderId: order.id, rate: amount.currencyRate)
    }

    /// `Token Purchase With Coinbase` at the order's outcome, as Android sends it once the order is
    /// placed. A missing contact or a cancel sends nothing: Android's flow routes to verification
    /// there instead of failing the purchase.
    static func trackPurchase(_ amount: ExchangedFiat, error: Error?) {
        if let error {
            if error is CancellationError { return }
            if case DepositError.requirementUnsatisfied = error { return }
        }
        Analytics.tokenPurchase(method: .coinbase, mint: amount.mint, amount: amount.nativeAmount, error: error)
    }

    private func checkRequirements() throws {
        guard CoinbaseOrderEmail.resolveContact(profile: session.profile, requiresVerification: session.requiresCoinbaseEmailVerification) != nil else {
            throw DepositError.requirementUnsatisfied(.verifiedContact)
        }
    }

    private func checkMinimum(_ amount: ExchangedFiat) throws {
        // Round the converted floor to the displayed denomination first — the
        // check must accept exactly the number the dialog shows; comparing raw
        // USD rejects the displayed minimum itself.
        let minimum = FiatAmount.usd(Self.minimumPurchaseUSD)
            .converting(to: amount.currencyRate)
            .roundedToSmallestUnit()
        guard amount.nativeAmount.value >= minimum.value else {
            logger.info("Coinbase deposit below minimum", metadata: [
                "amount": "\(amount.nativeAmount.formatted())",
                "minimum": "\(minimum.formatted())",
            ])
            throw DepositError.externalRejected(
                title: "\(minimum.formatted()) Minimum Purchase",
                subtitle: "Please enter an amount of \(minimum.formatted()) or higher"
            )
        }
    }

    private func createOrder(for amount: ExchangedFiat, orderRef: String?) async throws -> OnrampOrderResponse {
        guard let (email, phone) = CoinbaseOrderEmail.resolveContact(profile: session.profile, requiresVerification: session.requiresCoinbaseEmailVerification) else {
            throw DepositError.requirementUnsatisfied(.verifiedContact)
        }

        let userRef = session.ownerKeyPair.publicKey.base58
        let orderRef = orderRef ?? "\(userRef):\(UUID().uuidString)"

        do {
            let response = try await coinbaseService.coinbase.createOrder(
                request: OnrampOrderRequest(
                    purchaseAmount: "\(amount.usdfValue.value)",
                    paymentCurrency: "USD",
                    // USDC, not USDF — the sweep converts after deposit.
                    purchaseCurrency: "USDC",
                    isQuote: false,
                    // The user's USDC ATA — the owner authority address.
                    destinationAddress: session.owner.authorityPublicKey,
                    email: email,
                    phoneNumber: phone,
                    partnerOrderRef: orderRef,
                    partnerUserRef: userRef,
                    phoneNumberVerifiedAt: .now,
                    agreementAcceptedAt: .now
                )
            )
            // A stuck deposit must be traceable with Coinbase from the log alone.
            logger.info("Coinbase order created", metadata: [
                "orderId": "\(response.order.orderId)",
                "partnerOrderRef": "\(orderRef)",
                "status": "\(response.order.status)",
                "purchaseAmount": "\(response.order.purchaseAmount ?? "nil")",
                "paymentTotal": "\(response.order.paymentTotal ?? "nil")",
            ])
            return response
        } catch let error as OnrampErrorResponse {
            logger.error("Coinbase createOrder rejected", metadata: [
                "error_type": "\(error.errorType)",
            ])
            throw DepositError.externalRejected(
                title: error.title,
                subtitle: error.errorType.subtitle(at: amount.currencyRate)
            )
        } catch {
            // Network/auth blip — `externalRejected` (no Bugsnag) so we don't
            // alarm on routine Coinbase transport errors.
            logger.error("Coinbase createOrder failed", metadata: ["error": "\(error)"])
            throw DepositError.externalRejected(
                title: "Something Went Wrong",
                subtitle: "Please try again later"
            )
        }
    }

    /// Consumes `coinbaseService.applePayEvents` until Apple Pay reaches a
    /// terminal state, throwing on cancel or error.
    private func awaitApplePayCompletion(orderId: String, rate: Rate) async throws {
        defer {
            idleTimer.disarm()
            confirmationTimer?.disarm()
        }

        // Armed before Apple Pay opens too, so a sheet that never appears can't hold the run.
        armIdleTimer(orderId: orderId)

        for await event in coinbaseService.applePayEvents {
            try Task.checkCancellation()
            switch event.event {
            case .pollingSuccess:
                markAuthorized()
                timer.mark(.paymentCompleted)
                logger.info("Apple Pay onramp completed", metadata: [
                    "orderId": "\(orderId)",
                ])
                return

            case .cancelled:
                logger.info("Apple Pay cancelled", metadata: [
                    "orderId": "\(orderId)",
                ])
                throw CancellationError()

            case .commitError, .pollingError, .loadError:
                terminalError = event.event
                let errorType = OnrampErrorResponse.ErrorType(
                    coinbaseCode: event.data?.errorCode ?? ""
                )
                logger.error("Apple Pay terminal error", metadata: [
                    "orderId": "\(orderId)",
                    "event": "\(event.name)",
                    "code": "\(event.data?.errorCode ?? "nil")",
                    "type": "\(errorType)",
                ])
                throw DepositError.externalRejected(
                    title: errorType.title,
                    subtitle: errorType.subtitle(at: rate)
                )

            case .pendingPaymentAuth:
                armIdleTimer(orderId: orderId)

            case .paymentAuthorized:
                markAuthorized()
                timer.mark(.paymentAuthorized)
                logger.info("Apple Pay onramp progressed", metadata: [
                    "orderId": "\(orderId)",
                    "event": "\(event.name)",
                ])
                idleTimer.disarm()

            case .commitSuccess, .pollingStart:
                markAuthorized()
                logger.info("Apple Pay onramp progressed", metadata: [
                    "orderId": "\(orderId)",
                    "event": "\(event.name)",
                ])
                idleTimer.disarm()
                // Coinbase has the order by now, so stopping the wait can't undo the charge.
                confirmationTimer?.arm { [weak self] in
                    logger.info("Coinbase order completion not seen in time, cancelling", metadata: [
                        "orderId": "\(orderId)",
                    ])
                    self?.runTask?.cancel()
                }

            case .loadPending, .loadSuccess, .applePayButtonPressed, .none:
                continue
            }
        }
        logger.warning("Apple Pay event stream ended without a terminal event", metadata: [
            "orderId": "\(orderId)",
        ])
        throw CancellationError()
    }

    private func armIdleTimer(orderId: String) {
        idleTimer.arm { [weak self] in
            logger.info("Apple Pay sheet idle timeout, cancelling", metadata: [
                "orderId": "\(orderId)",
            ])
            self?.didTimeOut = true
            self?.runTask?.cancel()
        }
    }

    private func markAuthorized() {
        guard !reachedAuthorization else { return }
        reachedAuthorization = true
        onAuthorized?()
        onAuthorized = nil
    }
}
