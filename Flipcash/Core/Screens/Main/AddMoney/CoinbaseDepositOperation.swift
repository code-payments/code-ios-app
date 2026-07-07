//
//  CoinbaseDepositOperation.swift
//  Flipcash
//

import Foundation
import Observation
import FlipcashCore

private let logger = Logger(label: "flipcash.coinbase-deposit")

/// Deposits USDC into the user's wallet via the Coinbase Apple Pay onramp.
///
/// The onramp delivers **USDC** to the user's USDC ATA (the owner-authority
/// address — the same one `DepositScreen` shows for "Other Wallet"). The
/// in-flow `UsdcSweepOperation` converts it to USDF afterward; Geyser
/// auto-credits the balance server-side. No buy or launch intent is recorded.
///
/// Flow:
/// 1. `checkRequirements()` — throws `.requirementUnsatisfied(.verifiedContact)`
///    if the profile lacks a verified phone + a usable email (see
///    `CoinbaseOrderEmail`).
/// 2. `$5` minimum gate — Coinbase rejects sub-$5 orders with a generic error.
/// 3. `state = .working` — `coinbase.createOrder(...)` (purchaseCurrency USDC).
/// 4. Order published to `CoinbaseService`, mounting the WebView overlay.
/// 5. `state = .awaitingExternal(.applePay)` — consume `applePayEvents` until
///    `pollingSuccess`, `cancelled`, or a terminal error.
@Observable
final class CoinbaseDepositOperation {

    /// Coinbase Onramp's USD floor — orders below this amount fail with a
    /// generic error, so the deposit flow gates ahead of the Apple Pay sheet.
    static let minimumPurchaseUSD: Decimal = 5

    private(set) var state: DepositOperationState = .idle

    /// `true` when the idle timer cancelled the run because the user left the
    /// Apple Pay sheet sitting on screen past the timeout. Callers read this
    /// in their `catch is CancellationError` arm to distinguish a timeout from
    /// a silent user-dismiss.
    private(set) var didTimeOut: Bool = false

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
        // Reset state on any exit (return or throw). Without this, a throw from
        // createOrder / the Apple Pay event loop leaves state at `.working` or
        // `.awaitingExternal(.applePay)` and the host view never re-enables.
        defer { state = .idle }

        try checkRequirements()
        try checkMinimum(amount)

        state = .working
        let order = try await createOrder(for: amount)

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
        // Convert the USD floor into the user's currency ONCE, rounded to the
        // denomination the dialog renders — the check accepts exactly the
        // number it displays. Comparing raw USD instead rejects the displayed
        // minimum itself ($5 → "7.08 CAD" display, but 7.08 CAD → $4.9986).
        let minimum = FiatAmount(
            value: FiatAmount.usd(Self.minimumPurchaseUSD)
                .converting(to: amount.currencyRate)
                .value
                .rounded(to: amount.currencyRate.currency.maximumFractionDigits),
            currency: amount.currencyRate.currency
        )
        guard amount.nativeAmount.value >= minimum.value else {
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
                    // USDC, not USDF — the onramp deposits USDC to the user's
                    // ATA; the in-flow sweep converts it afterward.
                    purchaseCurrency: "USDC",
                    isQuote: false,
                    // The user's USDC ATA = owner authority address, the same
                    // address DepositScreen / Other Wallet shows.
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
            // Everything Coinbase support needs to trace the order — a stuck
            // deposit must be debuggable from the log alone.
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

    /// Consumes `coinbaseService.applePayEvents` until Apple Pay reports a
    /// terminal state. `pollingSuccess` resolves the wait; `cancelled` or an
    /// error event throws. Arms `idleTimer` on `.pendingPaymentAuth`, disarms
    /// once the user authenticates so a slow commit doesn't trip the timeout.
    /// Every log line carries `orderId` so a stuck or disputed deposit can be
    /// traced with Coinbase from the log alone.
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
                    logger.info("Apple Pay sheet idle timeout, cancelling")
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
        // Stream finished without a terminal event — treat as cancel.
        throw CancellationError()
    }
}
