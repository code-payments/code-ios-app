//
//  CollectionTopUp.swift
//  Flipcash
//

import Foundation
import FlipcashCore

nonisolated private let logger = Logger(label: "flipcash.collection-top-up")

/// How a collection payment's Apple Pay top-up ended.
enum CollectionTopUpOrder: Equatable {

    /// Why nothing was charged.
    enum NotCharged: Equatable {
        /// The user closed Apple Pay.
        case cancelled
        /// Apple Pay wasn't authorized within the operation's idle window.
        case timedOut
        /// Coinbase or a precondition refused the order, with the strings to show.
        case rejected(title: String, subtitle: String)
        /// The order failed before Apple Pay authorized it.
        case failed
    }

    /// Apple Pay charged and Coinbase reported the order complete. The Dollars land after the
    /// USDC sweep.
    case charged
    /// Apple Pay authorized the payment but the order's outcome wasn't seen, so it may still deliver.
    case mayDeliver
    /// Nothing was charged.
    case notCharged(NotCharged)
}

/// Adding Dollars with Apple Pay for a collection payment, so the payment can be tested without
/// Coinbase or a network.
@MainActor
protocol CollectionTopUpping: AnyObject {

    /// A fresh `partnerOrderRef` for the next order.
    func makeOrderRef() -> String

    /// Reloads balances and returns the Dollars balance in USD.
    func dollarsBalance() async throws -> Decimal

    /// Orders `amountUSD` of Dollars, the amount that lands, under `orderRef`. `onAuthorized` runs
    /// once, when Apple Pay reports the payment authorized, with Coinbase's id for the order.
    func order(amountUSD: Decimal, orderRef: String, onAuthorized: @escaping (_ orderID: String?) -> Void) async -> CollectionTopUpOrder

    /// Whether Coinbase reports the order `orderID` ended without delivering. False when it can't
    /// tell, so only an order read back as failed counts.
    func orderFailed(orderID: String) async -> Bool

    /// Waits for the Dollars balance to reach `targetUSD`, and returns whether it did.
    func awaitDollars(reaching targetUSD: Decimal) async -> Bool
}

extension CollectionTopUpOrder {

    /// How an order that threw ended. Coinbase reporting the commit failed means nothing was
    /// bought. Otherwise anything after Apple Pay authorized may still deliver, polling errors and
    /// cancels included, and only a failure before it charged nothing.
    nonisolated static func ended(
        by error: any Error,
        authorized: Bool,
        terminalError: ApplePayEvent.Event?,
        timedOut: Bool
    ) -> CollectionTopUpOrder {
        if terminalError != .commitError, authorized { return .mayDeliver }
        switch error {
        case is CancellationError:
            return .notCharged(timedOut ? .timedOut : .cancelled)
        case DepositError.userCancelled:
            return .notCharged(.cancelled)
        case let DepositError.externalRejected(title, subtitle):
            return .notCharged(.rejected(title: title, subtitle: subtitle))
        default:
            return .notCharged(.failed)
        }
    }
}

/// The Dollars balance that counts as a top-up landed: the baseline plus the order less the
/// onramp's tolerance, as Add Money counts it.
nonisolated enum CollectionTopUpTarget {
    static func target(baselineUSD: Decimal, amountUSD: Decimal) -> Decimal {
        baselineUSD + amountUSD * AddMoneyBalanceTarget.tolerance
    }
}

// MARK: - Session -

/// Top-ups through the Coinbase deposit Add Money uses: an Apple Pay order for USDC, swept into
/// Dollars.
@MainActor
final class SessionCollectionTopUpper: CollectionTopUpping {

    /// How long a committed order waits for Coinbase to report it complete while the pay sheet is
    /// locked; past it the order may still deliver and the Dollars wait takes over.
    static let confirmationTimeout: Duration = .seconds(30)
    /// How long an authorized payment waits for Coinbase to commit the order while the pay sheet is
    /// locked; past it the order may still deliver and the Dollars wait takes over.
    static let authorizationTimeout: Duration = .seconds(60)
    /// How long reading an order back from Coinbase may take while the pay sheet is locked.
    static let orderLookupTimeout: Duration = .seconds(15)

    private let session: Session
    private let coinbaseService: CoinbaseService
    private let sweeper: UsdcSweepOperation

    init(session: Session, coinbaseService: CoinbaseService, sweeper: UsdcSweepOperation) {
        self.session = session
        self.coinbaseService = coinbaseService
        self.sweeper = sweeper
    }

    func makeOrderRef() -> String {
        CoinbaseDepositOperation.makeOrderRef(owner: session.ownerKeyPair.publicKey)
    }

    func dollarsBalance() async throws -> Decimal {
        try await session.fetchBalance()
        return session.balance(for: .usdf)?.usdf.value ?? 0
    }

    func order(amountUSD: Decimal, orderRef: String, onAuthorized: @escaping (_ orderID: String?) -> Void) async -> CollectionTopUpOrder {
        let timer = session.addMoneyTimer
        timer.start()
        let operation = CoinbaseDepositOperation(
            coinbaseService: coinbaseService,
            session: session,
            timer: timer,
            authorizationTimeout: Self.authorizationTimeout,
            confirmationTimeout: Self.confirmationTimeout
        )
        do {
            try await operation.start(
                amount: ExchangedFiat(nativeAmount: .usd(amountUSD), rate: .oneToOne),
                orderRef: orderRef,
                onAuthorized: onAuthorized
            )
            return .charged
        } catch {
            let outcome = CollectionTopUpOrder.ended(
                by: error,
                authorized: operation.reachedAuthorization,
                terminalError: operation.terminalError,
                timedOut: operation.didTimeOut
            )
            if outcome == .notCharged(.failed) {
                ErrorReporting.captureError(error, reason: "Collection top-up failed before authorization")
            }
            return outcome
        }
    }

    func orderFailed(orderID: String) async -> Bool {
        await Self.orderFailed(orderID: orderID, ordering: coinbaseService.coinbase, timeout: Self.orderLookupTimeout)
    }

    /// Whether `ordering` reads the order `orderID` back as failed within `timeout`. Any error,
    /// timeout or status that isn't a failure reads as false.
    static func orderFailed(orderID: String, ordering: any OnrampOrdering, timeout: Duration) async -> Bool {
        do {
            let response = try await withDeadline(.now + timeout) {
                try await ordering.orderStatus(orderID: orderID)
            }
            logger.info("Collection top-up order read back", metadata: [
                "orderId": "\(orderID)",
                "status": "\(response.order.status)",
            ])
            return response.isFailed
        } catch {
            logger.warning("Collection top-up order lookup failed", metadata: [
                "orderId": "\(orderID)",
                "error": "\(error)",
            ])
            return false
        }
    }

    func awaitDollars(reaching targetUSD: Decimal) async -> Bool {
        // The order lands as USDC; the sweep converts it to Dollars while the balance is polled.
        let sweep = Task { [sweeper] in
            _ = await sweeper.sweepUntilConverted(
                maxAttempts: AddMoneyTiming.sweepMaxAttempts,
                backoff: AddMoneyTiming.sweepBackoff
            )
        }
        defer { sweep.cancel() }
        let clock = ContinuousClock()
        let deadline = clock.now + AddMoneyTiming.settlementTimeout
        while clock.now < deadline, !Task.isCancelled {
            try? await session.fetchBalance()
            if (session.balance(for: .usdf)?.usdf.value ?? 0) >= targetUSD { return true }
            try? await Task.sleep(for: AddMoneyTiming.balancePollInterval)
        }
        return false
    }
}
