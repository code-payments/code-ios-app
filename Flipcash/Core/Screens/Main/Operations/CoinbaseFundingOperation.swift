//
//  CoinbaseFundingOperation.swift
//  Flipcash
//

import Foundation
import Observation
import FlipcashCore

private let logger = Logger(label: "flipcash.coinbase-funding")

/// Funds a buy or launch via the Coinbase Apple Pay onramp.
///
/// Flow:
/// 1. `.launch` only — preflight `session.launchCurrency` so server-side
///    rejections (denied / nameExists / invalidIcon) throw before we
///    create the Coinbase order.
/// 2. `state = .working` — `coinbase.createOrder(...)` is awaited.
/// 3. Server-side swap is recorded via `session.buyWithCoinbaseOnramp` /
///    `buyNewCurrencyWithCoinbaseOnramp` BEFORE Apple Pay commits, so the
///    backend correlates the Coinbase order with our swap intent.
/// 4. Order is published to `CoinbaseService` — this triggers the root
///    `OnrampHostModifier` to mount its WebView with the payment link.
/// 5. `state = .awaitingExternal(.applePay)` — operation consumes the
///    `applePayEvents` stream until `pollingSuccess`, `cancelled`, or a
///    terminal error.
/// 6. `state = .working` — Apple Pay polling succeeded; return the
///    `StartedSwap`.
///
/// `requirements: [.verifiedContact]` — callers must have run
/// `VerificationOperation` first; the operation throws
/// `FundingOperationError.requirementUnsatisfied(.verifiedContact)` if the
/// profile lacks a verified phone + email at `start()` time.
@Observable
final class CoinbaseFundingOperation: FundingOperation {

    private(set) var state: FundingOperationState = .idle
    let requirements: [FundingRequirement] = [.verifiedContact]

    /// Set after a successful `.launch` preflight. Lets callers recover the
    /// minted PublicKey when the post-launch Apple Pay or chain step throws.
    private(set) var launchedMint: PublicKey?

    @ObservationIgnored private let coinbaseService: CoinbaseService
    @ObservationIgnored private let session: any (AccountProviding & ProfileProviding & OnrampBuying & CurrencyLaunching)

    @ObservationIgnored private var runTask: Task<StartedSwap, Error>?

    init(
        coinbaseService: CoinbaseService,
        session: any (AccountProviding & ProfileProviding & OnrampBuying & CurrencyLaunching)
    ) {
        self.coinbaseService = coinbaseService
        self.session = session
    }

    isolated deinit {
        runTask?.cancel()
    }

    // MARK: - FundingOperation

    func start(_ operation: PaymentOperation) async throws -> StartedSwap {
        let task = Task { try await run(operation) }
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

    /// Apple Pay drives the next step via the events stream, not a
    /// continuation — no user-action confirmation point.
    func confirm() {}

    func cancel() {
        runTask?.cancel()
    }

    // MARK: - Run

    private func run(_ operation: PaymentOperation) async throws -> StartedSwap {
        try await preflightLaunchIfNeeded(operation)
        try checkRequirements()

        state = .working

        let order = try await createOrder(for: operation)
        let (swapId, swapType, launched) = try await recordSwap(for: operation, order: order)

        coinbaseService.setOrder(order)
        defer { coinbaseService.clearOrder() }

        state = .awaitingExternal(.applePay)
        try await awaitApplePayCompletion()

        state = .working
        return StartedSwap(
            swapId: swapId,
            swapType: swapType,
            currencyName: operation.currencyName,
            amount: operation.displayAmount,
            launchedMint: launched
        )
    }

    private func preflightLaunchIfNeeded(_ operation: PaymentOperation) async throws {
        switch operation {
        case .buy:
            return
        case .launch(let payload):
            guard let attestations = payload.attestations else {
                logger.error("Coinbase launch invoked without attestations")
                throw FundingOperationError.serverRejected("Missing launch attestations")
            }
            state = .working
            let mint = try await session.launchCurrency(
                name: payload.currencyName,
                description: attestations.description,
                billColors: attestations.billColors,
                icon: attestations.icon,
                nameAttestation: attestations.nameAttestation,
                descriptionAttestation: attestations.descriptionAttestation,
                iconAttestation: attestations.iconAttestation
            )
            launchedMint = mint
        }
    }

    private func checkRequirements() throws {
        guard let profile = session.profile,
              profile.isPhoneVerified,
              profile.isEmailVerified else {
            throw FundingOperationError.requirementUnsatisfied(.verifiedContact)
        }
    }

    private func createOrder(for operation: PaymentOperation) async throws -> OnrampOrderResponse {
        guard let profile = session.profile,
              let email = profile.email,
              let phone = profile.phone?.e164 else {
            throw FundingOperationError.requirementUnsatisfied(.verifiedContact)
        }
        guard let usdfSwapAccounts = MintMetadata.usdf.timelockSwapAccounts(
            owner: session.owner.authorityPublicKey
        ) else {
            logger.error("Failed to derive USDF swap accounts for Coinbase order")
            throw FundingOperationError.serverRejected("Couldn't derive destination account")
        }

        let userRef = session.ownerKeyPair.publicKey.base58
        let orderRef = "\(userRef):\(UUID().uuidString)"

        do {
            return try await coinbaseService.coinbase.createOrder(
                request: OnrampOrderRequest(
                    purchaseAmount: "\(operation.displayAmount.usdfValue.value)",
                    paymentCurrency: "USD",
                    purchaseCurrency: "USDF",
                    isQuote: false,
                    destinationAddress: usdfSwapAccounts.pda.publicKey,
                    email: email,
                    phoneNumber: phone,
                    partnerOrderRef: orderRef,
                    partnerUserRef: userRef,
                    phoneNumberVerifiedAt: .now,
                    agreementAcceptedAt: .now
                ),
                idempotencyKey: nil
            )
        } catch let error as OnrampErrorResponse {
            logger.error("Coinbase createOrder rejected", metadata: [
                "error_type": "\(error.errorType)",
            ])
            throw FundingOperationError.serverRejected(error.subtitle)
        } catch {
            logger.error("Coinbase createOrder failed", metadata: ["error": "\(error)"])
            throw FundingOperationError.serverRejected("Couldn't create the Apple Pay order")
        }
    }

    private func recordSwap(
        for operation: PaymentOperation,
        order: OnrampOrderResponse
    ) async throws -> (swapId: SwapId, swapType: SwapType, launchedMint: PublicKey?) {
        switch operation {
        case .buy(let payload):
            let swapId = try await session.buyWithCoinbaseOnramp(
                amount: payload.amount,
                of: payload.mint,
                orderId: order.id
            )
            return (swapId, .buyWithCoinbase, nil)

        case .launch(let payload):
            guard let mint = launchedMint else {
                logger.error("Coinbase launch reached recordSwap without a preflighted mint")
                throw FundingOperationError.serverRejected("Missing launched mint")
            }
            let swapId = try await session.buyNewCurrencyWithCoinbaseOnramp(
                amount: payload.launchAmount,
                feeAmount: payload.launchFee,
                mint: mint,
                orderId: order.id
            )
            return (swapId, .launchWithCoinbase, mint)
        }
    }

    /// Consumes `coinbaseService.applePayEvents` until Apple Pay reports
    /// a terminal state. `pollingSuccess` resolves the wait; `cancelled`
    /// or an error event throws.
    private func awaitApplePayCompletion() async throws {
        for await event in coinbaseService.applePayEvents {
            try Task.checkCancellation()
            switch event.event {
            case .pollingSuccess:
                return

            case .cancelled:
                logger.info("Apple Pay cancelled")
                throw CancellationError()

            case .commitError, .pollingError, .loadError:
                let message = event.data?.errorMessage ?? "Apple Pay failed"
                logger.error("Apple Pay terminal error", metadata: [
                    "event": "\(event.name)",
                    "code": "\(event.data?.errorCode ?? "nil")",
                ])
                throw FundingOperationError.serverRejected(message)

            case .loadPending, .loadSuccess,
                 .applePayButtonPressed, .pendingPaymentAuth,
                 .paymentAuthorized, .commitSuccess, .pollingStart, .none:
                continue
            }
        }
        // Stream finished without a terminal event — treat as cancel.
        throw CancellationError()
    }
}
