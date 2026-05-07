//
//  SendCashOperation.swift
//  Code
//
//  Created by Dima Bart on 2025-04-15.
//

import Foundation
import FlipcashCore

private let logger = Logger(label: "flipcash.send-cash")

/// Orchestrates a peer-to-peer cash transfer through a rendezvous-based
/// handshake between sender and receiver.
///
/// ## Per-Device Summary
///
/// **Device A (Sender — this operation runs here)**
/// 1. Resolve `VerifiedState` (provided at init or from `RatesController` cache).
/// 2. Advertise the bill: publish mint + exchange data on the rendezvous channel.
/// 3. Listen on the channel for Device B's grab request.
/// 4. Verify destination signature, then transfer funds to Device B's vault.
/// 5. Poll until on-chain settlement confirms.
///
/// **Device B (Receiver)**
/// - **Scan path:** `ScanCashOperation` extracts the `VerifiedState` from
///   Device A's advertisement message — no local cache needed.
/// - **Cash Link path:** `Session.receiveCashLink` subscribes to the mint
///   and passes the cached verified state (if available) as
///   `providedVerifiedState` for the quick-give-and-grab chain.
///
/// ## Lifecycle
///
/// ``start()`` runs the whole flow imperatively — advertise, await grab,
/// verify, transfer, poll settlement. The operation owns a `Task` internally
/// so callers can invoke ``cancel()`` to tear it down without having to
/// track the outer Task themselves.
///
/// ## Not Recoverable
///
/// If ``sendRequestToGiveBill`` fails (network error, server down), the
/// operation terminates immediately. There is no retry — the receiver never
/// got the advertisement, so the stream will never deliver a grab request.
///
/// ## Owned By
///
/// `Session` creates, stores (`sendOperation`), and tears down this
/// operation. The `ignoresStream` flag is toggled by Session when presenting
/// a share sheet to suppress grab-request processing underneath it.
@MainActor
class SendCashOperation {

    /// Submitting a proof older than this is rejected as stale, so we pre-flight the check
    /// to fail fast and surface a specific error in logs and Bugsnag.
    static let maxReserveAge: TimeInterval = 15 * 60

    enum FailurePath: String {
        case advertisement
        case stream
        case transfer
    }

    let payload: CashCode.Payload

    /// When `true`, incoming rendezvous-stream messages are silently dropped.
    /// Session sets this while a share sheet is presented to prevent a grab
    /// request from being processed while the user is mid-share-sheet.
    var ignoresStream = false

    private let client: Client
    private let database: Database
    private let ratesController: RatesController
    private let owner: AccountCluster
    private let exchangedFiat: ExchangedFiat
    private let providedVerifiedState: VerifiedState?

    private var runTask: Task<Void, Swift.Error>?

    // MARK: - Init -

    init(client: Client, database: Database, ratesController: RatesController, owner: AccountCluster, exchangedFiat: ExchangedFiat, verifiedState: VerifiedState? = nil) {
        self.client          = client
        self.database        = database
        self.ratesController = ratesController
        self.owner           = owner
        self.exchangedFiat   = exchangedFiat
        self.providedVerifiedState = verifiedState
        self.payload = .init(
            kind: .cashMulticurrency,
            fiat: exchangedFiat.nativeAmount,
            nonce: .nonce
        )
        logger.info("SendCashOperation opened", metadata: ["rendezvous": "\(payload.rendezvous.publicKey.base58)"])
    }

    isolated deinit {
        logger.info("SendCashOperation closed", metadata: ["rendezvous": "\(payload.rendezvous.publicKey.base58)"])
        runTask?.cancel()
    }

    // MARK: - Lifecycle -

    func start() async throws {
        let task = Task { try await self.run() }
        runTask = task
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    func cancel() {
        runTask?.cancel()
    }

    // MARK: - Run -
    //
    // 1. Resolve verified state (one proof used for the whole op)
    // 2. Advertise bill on rendezvous channel
    // 3. Await grab request from receiver
    // 4. Verify destination signature
    // 5. Transfer funds + poll settlement
    //
    // The same proof is used for advertise and transfer on purpose. `exchangedFiat`
    // bakes in (quarks, nativeAmount) at bill creation time; switching to a
    // different-rate proof for transfer would make the server's
    // `quarks × rate ≈ nativeAmount` check fail with
    // `invalidIntent(native amount does not match expected sell value)`.

    private func run() async throws {
        let rendezvous = payload.rendezvous
        let exchangedFiat = exchangedFiat
        var owner = owner

        if owner.timelock.mint != exchangedFiat.mint {
            guard let vmAuthority = try? database.getVMAuthority(mint: exchangedFiat.mint) else {
                throw Error.missingMintMetadata
            }
            owner = owner.use(mint: exchangedFiat.mint, timeAuthority: vmAuthority)
        }

        let resolution = await resolveAndLogVerifiedState(
            currency: exchangedFiat.nativeAmount.currency,
            mint: exchangedFiat.mint
        )

        do {
            _ = try await client.sendRequestToGiveBill(
                mint: exchangedFiat.mint,
                exchangedFiat: exchangedFiat,
                verifiedState: resolution.state,
                rendezvous: rendezvous
            )
        } catch {
            try Task.checkCancellation()
            handleFailure(error, path: .advertisement, resolution: resolution)
            throw error
        }

        let paymentRequest: PaymentRequest
        do {
            paymentRequest = try await client.awaitGrabRequest(
                rendezvous: rendezvous,
                shouldIgnore: { [weak self] in
                    // Hops to MainActor to read the flag safely — this closure
                    // is invoked from the cooperative executor inside the
                    // stream wait, not from the owning actor.
                    await self?.ignoresStream ?? false
                }
            )
        } catch {
            try Task.checkCancellation()
            handleFailure(error, path: .stream, resolution: resolution)
            throw error
        }

        // Rejects tampered grab requests by checking the rendezvous signature.
        let isValid = client.verifyRequestToGrabBill(
            destination: paymentRequest.account,
            rendezvous: rendezvous.publicKey,
            signature: paymentRequest.signature
        )

        guard isValid else {
            let error = Error.invalidPaymentDestinationSignature
            handleFailure(error, path: .transfer, resolution: resolution)
            throw error
        }

        guard let transferState = resolution.state else {
            let error = Error.missingVerifiedState
            handleFailure(error, path: .transfer, resolution: resolution)
            throw error
        }

        if let reserveTimestamp = transferState.reserveTimestamp {
            let reserveAge = Date().timeIntervalSince(reserveTimestamp)
            if reserveAge >= Self.maxReserveAge {
                let error = Error.reserveProofStale(ageSeconds: reserveAge)
                handleFailure(error, path: .transfer, resolution: resolution)
                throw error
            }
        }

        do {
            try await client.transfer(
                exchangedFiat: exchangedFiat,
                verifiedState: transferState,
                owner: owner,
                destination: paymentRequest.account,
                rendezvous: rendezvous.publicKey
            )

            _ = try await client.pollIntentMetadata(
                owner: owner.authority.keyPair,
                intentID: rendezvous.publicKey
            )
        } catch {
            try Task.checkCancellation()
            handleFailure(error, path: .transfer, resolution: resolution)
            throw error
        }
    }

    // MARK: - Helpers -

    /// Resolves verified state via the shared helper and logs the source +
    /// rate proof age. Logging the source is the primary diagnostic for the
    /// recurring `invalidIntent(native amount does not match expected sell value)`
    /// error — it lets us see where the submitted proof came from on any
    /// given recurrence.
    private func resolveAndLogVerifiedState(currency: CurrencyCode, mint: PublicKey) async -> VerifiedStateResolution {
        let resolution = await resolveVerifiedState(
            provided: providedVerifiedState,
            currency: currency,
            mint: mint,
            cacheLookup: { [ratesController] c, m in
                await ratesController.getVerifiedState(for: c, mint: m)
            }
        )

        var metadata: Logger.Metadata = [
            "source": "\(resolution.sourceLabel)",
            "currency": "\(currency.rawValue)",
            "mint": "\(mint.base58)",
        ]
        if let state = resolution.state {
            let rateAge = Date().timeIntervalSince(state.timestamp)
            metadata["rate"] = "\(state.exchangeRate)"
            metadata["rateAgeSec"] = "\(String(format: "%.1f", rateAge))"
            metadata["hasReserveProof"] = "\(state.reserveProto != nil)"
            if let reserveTimestamp = state.reserveTimestamp {
                let reserveAge = Date().timeIntervalSince(reserveTimestamp)
                metadata["reserveAgeSec"] = "\(String(format: "%.1f", reserveAge))"
            }
        }

        switch resolution {
        case .cacheMiss:
            // TODO: Fall back to `RatesController.ensureMintSubscribed` +
            // `awaitVerifiedState` to recover when a brand-new currency
            // hasn't populated the cache yet.
            logger.warning("Verified state resolution failed", metadata: metadata)
        case .provided, .cacheHit:
            logger.info("Resolved verified state", metadata: metadata)
        }

        return resolution
    }

    private func handleFailure(_ error: Swift.Error, path: FailurePath, resolution: VerifiedStateResolution) {
        // Log before capturing so the entry lands in the trace buffer
        // Bugsnag attaches to the report.
        logger.error("SendCashOperation failed", metadata: [
            "rendezvous": "\(payload.rendezvous.publicKey.base58)",
            "path": "\(path.rawValue)",
            "verifiedStateSource": "\(resolution.sourceLabel)",
            "error": "\(error)",
        ])

        ErrorReporting.capturePayment(
            error: error,
            rendezvous: payload.rendezvous.publicKey,
            exchangedFiat: exchangedFiat,
            verifiedState: resolution.state,
            reason: path.rawValue
        )
    }
}

extension SendCashOperation {
    enum Error: Swift.Error {
        /// The grab request's destination signature did not match the
        /// rendezvous key, indicating a potential man-in-the-middle attack.
        case invalidPaymentDestinationSignature

        /// The outgoing mint doesn't match the owner's timelock mint, and
        /// no VM authority was found in the database for the target mint.
        case missingMintMetadata

        /// No exchange-rate proof was available from either the provided
        /// value at init or the `RatesController` cache. Common for
        /// brand-new currencies that haven't been rate-cached yet.
        case missingVerifiedState

        /// The resolved `VerifiedState` has a reserve-state proof older than
        /// the server tolerates. Submitting it would be rejected — we reject
        /// client-side to surface a specific error.
        case reserveProofStale(ageSeconds: TimeInterval)
    }
}
