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

    @ObservationIgnored private let coinbaseService: CoinbaseService
    @ObservationIgnored private let session: any (AccountProviding & ProfileProviding)
    @ObservationIgnored private let idleTimer: ApplePayIdleTimer

    @ObservationIgnored private var runTask: Task<Void, Error>?

    init(
        coinbaseService: CoinbaseService,
        session: any (AccountProviding & ProfileProviding),
        applePayIdleTimeout: Duration = .seconds(60)
    ) {
        self.coinbaseService = coinbaseService
        self.session = session
        self.idleTimer = ApplePayIdleTimer(timeout: applePayIdleTimeout)
    }

    isolated deinit {
        runTask?.cancel()
    }

    // MARK: - Entry

    func start(amount: ExchangedFiat) async throws {
        let task = Task { try await run(amount) }
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

    private func run(_ amount: ExchangedFiat) async throws {
        // Reset state on any exit — a throw would otherwise strand the host
        // view in `.working`.
        defer { state = .idle }

        try checkRequirements()
        try checkMinimum(amount)

        state = .working
        let order = try await createOrder(for: amount)
        orderId = order.id
        Analytics.addMoneyPaymentInvoked(method: .coinbase, exchangedFiat: amount)

        coinbaseService.setOrder(order)
        defer { coinbaseService.clearOrder() }

        state = .awaitingExternal(.applePay)
        try await awaitApplePayCompletion(orderId: order.id)
    }

    private func checkRequirements() throws {
        guard CoinbaseOrderEmail.resolveContact(profile: session.profile) != nil else {
            throw DepositError.requirementUnsatisfied(.verifiedContact)
        }
    }

    private func checkMinimum(_ amount: ExchangedFiat) throws {
        // Round the converted floor to the displayed denomination first — the
        // check must accept exactly the number the dialog shows; comparing raw
        // USD rejects the displayed minimum itself.
        let minimum = FiatAmount(
            value: FiatAmount.usd(Self.minimumPurchaseUSD)
                .converting(to: amount.currencyRate)
                .value
                .rounded(to: amount.currencyRate.currency.maximumFractionDigits),
            currency: amount.currencyRate.currency
        )
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

    private func createOrder(for amount: ExchangedFiat) async throws -> OnrampOrderResponse {
        guard let (email, phone) = CoinbaseOrderEmail.resolveContact(profile: session.profile) else {
            throw DepositError.requirementUnsatisfied(.verifiedContact)
        }

        let userRef = session.ownerKeyPair.publicKey.base58
        let orderRef = "\(userRef):\(UUID().uuidString)"

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
                ),
                idempotencyKey: nil
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
                subtitle: error.subtitle
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
    private func awaitApplePayCompletion(orderId: String) async throws {
        defer { idleTimer.disarm() }

        for await event in coinbaseService.applePayEvents {
            try Task.checkCancellation()
            switch event.event {
            case .pollingSuccess:
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
                    subtitle: errorType.subtitle
                )

            case .pendingPaymentAuth:
                idleTimer.arm { [weak self] in
                    logger.info("Apple Pay sheet idle timeout, cancelling", metadata: [
                        "orderId": "\(orderId)",
                    ])
                    self?.didTimeOut = true
                    self?.runTask?.cancel()
                }

            case .paymentAuthorized, .commitSuccess, .pollingStart:
                logger.info("Apple Pay onramp progressed", metadata: [
                    "orderId": "\(orderId)",
                    "event": "\(event.name)",
                ])
                idleTimer.disarm()

            case .loadPending, .loadSuccess, .applePayButtonPressed, .none:
                continue
            }
        }
        logger.warning("Apple Pay event stream ended without a terminal event", metadata: [
            "orderId": "\(orderId)",
        ])
        throw CancellationError()
    }
}
