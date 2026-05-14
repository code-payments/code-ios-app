//
//  PhantomCoordinator.swift
//  Flipcash
//
//  Created by Raul Riera on 2026-05-14.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

private let logger = Logger(label: "flipcash.phantom-coordinator")

/// Owns the Phantom-funded operation lifecycle from picker tap through to
/// post-signing chain submission. Mirrors `OnrampCoordinator` so funding
/// paths follow the same shape (operation + state + completion).
///
/// Always-connect policy: `start(_:)` unconditionally invokes the Phantom
/// connect handshake. We never trust a cached Keychain session — the user
/// could have revoked us in Phantom since last time. A warm session returns
/// inside ~1 second; a cold session prompts the user. Either way we know we
/// have a live session before requesting a signature.
@Observable
@MainActor
final class PhantomCoordinator {

    // MARK: - Public state

    /// The operation being funded. Set by `start(_:)`, cleared by `cancel()`
    /// or when the operation completes.
    private(set) var operation: PaymentOperation?

    /// Drives picker / education / confirm UI.
    private(set) var state: State = .idle

    /// Single source of truth for external-wallet processing state. Invalid
    /// combinations — "cancelled flag set with no active context", "both
    /// buy-existing and launch contexts populated simultaneously" — are
    /// unrepresentable by construction.
    private(set) var processingState: WalletProcessingState = .idle

    /// Buy-existing context, exposed for `.fullScreenCover(item:)`. Writing
    /// `nil` (SwiftUI dismiss) transitions back to `.idle` only if currently
    /// buying.
    var processing: ExternalSwapProcessing? {
        get {
            if case .buying(let p, _) = processingState { return p }
            return nil
        }
        set {
            if newValue == nil, case .buying = processingState {
                processingState = .idle
            }
        }
    }

    /// Launch context, exposed for `.fullScreenCover(item:)`.
    var launchProcessing: ExternalLaunchProcessing? {
        get {
            if case .launching(let l, _) = processingState { return l }
            return nil
        }
        set {
            if newValue == nil, case .launching = processingState {
                processingState = .idle
            }
        }
    }

    /// True iff the active processing context has been marked failed.
    /// `SwapProcessingScreen` observes this via `.onChange(of:initial:)`.
    var isProcessingCancelled: Bool {
        switch processingState {
        case .idle:                                                 return false
        case .buying(_, let isFailed), .launching(_, let isFailed): return isFailed
        }
    }

    /// True while a signing request has been sent and the user hasn't yet
    /// returned with a signed transaction. Used by the buy nested sheet to
    /// block swipe-dismissal so the user can't accidentally lose the
    /// in-flight signature.
    var isAwaitingExternalSwap: Bool { pendingSwap != nil }

    /// Launch flows assign a handler before opening the picker. Coordinator
    /// invokes it after Phantom signs to chain `launchCurrency` +
    /// `buyNewCurrencyWithExternalFunding` and return a `SignedSwapResult`.
    /// Buy flows don't need a handler — buy completion is built in.
    var launchHandler: (@MainActor @Sendable (FlipcashCore.Signature, ExchangedFiat) async throws -> SignedSwapResult)?

    enum State: Equatable {
        /// No operation in flight.
        case idle
        /// Handshake deeplink sent; waiting for Phantom return. Always runs,
        /// even if a Keychain session exists.
        case connecting
        /// Phantom is connected. Waiting for the user to tap Confirm on the
        /// `PhantomConfirmScreen`.
        case awaitingConfirm
        /// Signing deeplink sent; waiting for Phantom return.
        case signing
        /// Connect or signing failed. Surfaces a dialog; user can retry.
        case failed(reason: String)
    }

    // MARK: - Dependencies

    private let walletConnection: WalletConnection
    private let session: Session
    private let client: Client
    private let rpc: any SolanaRPC

    // MARK: - Init

    init(walletConnection: WalletConnection, session: Session, client: Client, rpc: any SolanaRPC = SolanaJSONRPCClient()) {
        self.walletConnection = walletConnection
        self.session = session
        self.client = client
        self.rpc = rpc
        startEventStreamConsumer()
    }

    // No `deinit` task cancellation: Swift 6 makes `deinit` nonisolated and
    // it can't touch `eventTask` (main-actor isolated). The consumer Task
    // exits when `WalletConnection.deinit` calls `deeplinkContinuation
    // .finish()`, which ends the `for await` loop cleanly. Both objects are
    // session-scoped on `SessionContainer`, so the stream and the task
    // share a lifetime.

    // MARK: - Lifecycle

    /// Entry point — picker calls this when the user taps Phantom.
    /// Unconditionally deeplinks Phantom for connect.
    func start(_ operation: PaymentOperation) {
        cancelInternalTasks()
        pendingSwap = nil
        // Drop any stale launch handler when starting a buy. The wizard sets
        // `launchHandler` right before pushing into the picker for `.launch`;
        // a `.buy` start must not inherit a leftover handler from a prior
        // wizard attempt that didn't run to completion.
        if case .buy = operation {
            launchHandler = nil
        }
        self.operation = operation
        state = .connecting
        connectTask = Task { [weak self] in
            guard let self else { return }
            await self.runHandshake()
        }
    }

    /// Called from `PhantomConfirmScreen` when the user taps Confirm.
    func confirm() {
        guard state == .awaitingConfirm, let operation else { return }
        cancelInternalTasks()
        state = .signing
        signTask = Task { [weak self] in
            guard let self else { return }
            await self.runSwapRequest(for: operation)
        }
    }

    /// Discards in-flight pre-signing state. Safe to call from any
    /// `.onDisappear` — no-ops when nothing is pending. Active processing
    /// contexts (`processingState != .idle`) are owned by the cover and
    /// untouched here; only the pre-sign lifecycle is reset.
    func cancel() {
        cancelInternalTasks()
        pendingSwap = nil
        operation = nil
        launchHandler = nil
        state = .idle
    }

    /// Dismisses the processing cover. Callers (BuyAmountScreen, wizard)
    /// invoke this from the cover's `dismissParentContainer` env value.
    func dismissProcessing() {
        processingState = .idle
        operation = nil
        launchHandler = nil
        state = .idle
    }

    // MARK: - Pending swap state

    /// Context for resolving a signed transaction. Set in `runSwapRequest`,
    /// consumed in `handleSignedTransaction`.
    private var pendingSwap: PendingSwap?

    /// Captures everything `handleSignedTransaction` needs to dispatch the
    /// post-sign chain submission. The `onCompleted` closure is set by the
    /// coordinator itself (buy uses a built-in `client.buyWithExternalFunding`
    /// call; launch defers to `launchHandler`).
    struct PendingSwap {
        let fundingSwapId: SwapId
        let amount: ExchangedFiat
        let displayName: String
        let onCompleted: @MainActor @Sendable (FlipcashCore.Signature, ExchangedFiat) async throws -> SignedSwapResult
    }

    // MARK: - Internal tasks

    private var connectTask: Task<Void, Never>?
    private var signTask: Task<Void, Never>?
    private var eventTask: Task<Void, Never>?

    private func cancelInternalTasks() {
        connectTask?.cancel()
        connectTask = nil
        signTask?.cancel()
        signTask = nil
    }

    /// Subscribes to `WalletConnection.deeplinkEvents` for the lifetime of
    /// this coordinator. Exits when the stream finishes (in
    /// `WalletConnection.deinit`).
    private func startEventStreamConsumer() {
        let stream = walletConnection.deeplinkEvents
        eventTask = Task { [weak self] in
            for await event in stream {
                await self?.handle(event)
            }
        }
    }

    // MARK: - Handshake + sign request

    private func runHandshake() async {
        do {
            try await walletConnection.handshake()
            try Task.checkCancellation()
            state = .awaitingConfirm
        } catch is CancellationError {
            // Local cancel — view dismissed, coordinator reset, etc.
            // Silent reset is correct here; the user didn't act, the app did.
            await reset()
        } catch WalletConnectionError.userCancelledConnect {
            // User dismissed the connect prompt in Phantom. Surface a dialog
            // so the education screen shows feedback; user can tap Connect
            // again to retry.
            state = .failed(reason: "You cancelled the connection in your wallet. Tap Connect again to retry.")
        } catch {
            logger.error("Phantom handshake failed", metadata: ["error": "\(error)"])
            state = .failed(reason: "We couldn't connect to your Phantom wallet. Please try again.")
        }
    }

    private func runSwapRequest(for operation: PaymentOperation) async {
        let fundingSwapId = SwapId.generate()
        let onCompleted: @MainActor @Sendable (FlipcashCore.Signature, ExchangedFiat) async throws -> SignedSwapResult

        switch operation {
        case .buy(let payload):
            let token: MintMetadata
            do {
                token = try await session.fetchMintMetadata(mint: payload.mint).metadata
                try Task.checkCancellation()
            } catch is CancellationError {
                await reset()
                return
            } catch {
                logger.error("Failed to load mint metadata for Phantom buy", metadata: ["error": "\(error)"])
                state = .failed(reason: "We couldn't load the currency. Please try again.")
                return
            }
            let client = self.client
            let owner = walletConnection.owner
            onCompleted = { signature, amount in
                try await client.buyWithExternalFunding(
                    swapId: fundingSwapId,
                    amount: amount,
                    of: token,
                    owner: owner,
                    transactionSignature: signature
                )
                return .buyExisting(swapId: fundingSwapId)
            }

        case .launch:
            guard let launchHandler else {
                logger.error("Launch confirm reached without a registered launchHandler")
                state = .failed(reason: "We couldn't start the launch. Please try again.")
                return
            }
            // The caller-provided handler chains launchCurrency +
            // buyNewCurrencyWithExternalFunding and returns the buy swap id.
            onCompleted = launchHandler
        }

        let usdc: FlipcashCore.TokenAmount = operation.displayAmount.onChainAmount
        pendingSwap = PendingSwap(
            fundingSwapId: fundingSwapId,
            amount: operation.displayAmount,
            displayName: operation.currencyName,
            onCompleted: onCompleted
        )

        do {
            try await walletConnection.sendUsdcToUsdfSignRequest(
                usdc: usdc,
                fundingSwapId: fundingSwapId,
                displayName: operation.currencyName
            )
        } catch is CancellationError {
            pendingSwap = nil
            await reset()
        } catch {
            pendingSwap = nil
            logger.error("Phantom sign request failed", metadata: ["error": "\(error)"])
            state = .failed(reason: "We couldn't initiate the transaction. Please try again.")
        }
    }

    // MARK: - Deeplink event handling

    private func handle(_ event: WalletConnection.DeeplinkEvent) async {
        switch event {
        case .signed(let signedTx):
            let pending = pendingSwap
            pendingSwap = nil
            await handleSignedTransaction(signedTx: signedTx, pending: pending)
        case .userCancelled:
            pendingSwap = nil
            // Cancel happened during the sign step (pre-`buying`/`launching`)
            // → re-enable the confirm button so the user can retry. If we'd
            // already entered processing, flip the active context to failed
            // so the processing screen surfaces the error.
            if case .idle = processingState {
                if operation != nil {
                    state = .awaitingConfirm
                }
                session.dialogItem = .init(
                    style: .destructive,
                    title: "Transaction Cancelled",
                    subtitle: "The transaction was cancelled in your wallet",
                    dismissable: true
                ) { .okay(kind: .destructive) }
            } else {
                processingState = processingState.markedFailed()
            }
        case .failed:
            pendingSwap = nil
            if case .idle = processingState {
                if operation != nil {
                    state = .awaitingConfirm
                }
                session.dialogItem = .init(
                    style: .destructive,
                    title: "Transaction Failed",
                    subtitle: "Your wallet returned an error. Please try again.",
                    dismissable: true
                ) { .okay(kind: .destructive) }
            } else {
                processingState = processingState.markedFailed()
            }
        }
    }

    /// Decodes the signed transaction, runs preflight simulation,
    /// notifies the server, transitions to the processing context, and
    /// submits to the chain. Server-notify is intentionally before chain
    /// submit: a server rejection skips submission so no USDC moves without
    /// a recorded swap.
    private func handleSignedTransaction(signedTx: String, pending: PendingSwap?) async {
        guard let pending else {
            logger.warning("Received signed transaction but no pending swap context")
            return
        }

        let swapMetadata: [String: String] = [
            "swapId": pending.fundingSwapId.publicKey.base58,
            "amount": pending.amount.nativeAmount.formatted(),
            "name": pending.displayName,
        ]

        let rawData = Data(Base58.toBytes(signedTx))
        guard let tx = SolanaTransaction(data: rawData) else {
            logger.error("Failed to decode signed transaction")
            ErrorReporting.captureError(WalletConnection.Error.invalidURL, reason: "Failed to decode signed transaction", metadata: swapMetadata)
            return
        }

        let txBase64 = rawData.base64EncodedString()
        switch await simulateSignedTransaction(txBase64, swapMetadata: swapMetadata) {
        case .proceed:
            break
        case .blocked(let dialog):
            session.dialogItem = dialog
            return
        }

        // Present the generic processing screen via the .buying context.
        // The server callback may transition this to .launching when the
        // caller is launching a new currency; early-exit failures transition
        // back to .idle so no cover presents for a swap the server never
        // recorded.
        processingState = .buying(
            ExternalSwapProcessing(
                swapId: pending.fundingSwapId,
                currencyName: pending.displayName,
                amount: pending.amount
            ),
            isFailed: false
        )

        // Notify server before submitting to chain — if the server rejects,
        // skip chain submission so no USDC is spent without a swap state.
        do {
            let result = try await pending.onCompleted(tx.identifier, pending.amount)
            switch result {
            case .buyExisting(let swapId):
                if swapId != pending.fundingSwapId {
                    processingState = .buying(
                        ExternalSwapProcessing(
                            swapId: swapId,
                            currencyName: pending.displayName,
                            amount: pending.amount
                        ),
                        isFailed: false
                    )
                }
            case .launch(let swapId, let mint):
                processingState = .launching(
                    ExternalLaunchProcessing(
                        swapId: swapId,
                        launchedMint: mint,
                        currencyName: pending.displayName,
                        amount: pending.amount
                    ),
                    isFailed: false
                )
            }
            logger.info("Server notified of swap funding")
        } catch {
            logger.error("Server notification failed", metadata: ["error": "\(error)"])
            ErrorReporting.captureError(error, reason: "Server notification failed", metadata: swapMetadata)
            processingState = .idle
            return
        }

        // Server accepted — submit to chain. Failure here keeps the context
        // and flips `isFailed` so the processing screen surfaces the error.
        do {
            let signature = try await rpc.sendTransaction(
                txBase64,
                configuration: SolanaSendTransactionConfig()
            )
            logger.info("Transaction sent", metadata: ["signature": "\(signature.base58)"])
            Analytics.track(event: Analytics.WalletEvent.transactionsSubmitted)
        } catch {
            logger.error("Chain submission failed", metadata: ["error": "\(error)"])
            ErrorReporting.captureError(error, reason: "Chain submission failed", metadata: swapMetadata)
            processingState = processingState.markedFailed()
        }
    }

    // MARK: - Simulation

    private enum SimulationOutcome {
        case proceed
        case blocked(DialogItem)
    }

    /// Transport failures (URL errors, decode errors) pass through as
    /// `.proceed` — a flaky RPC blip must not block a user with valid funds.
    /// Only explicit RPC rejections block.
    private func simulateSignedTransaction(
        _ txBase64: String,
        swapMetadata: [String: String]
    ) async -> SimulationOutcome {
        do {
            _ = try await rpc.simulateTransaction(
                txBase64,
                configuration: SolanaSimulateTransactionConfig(
                    commitment: .confirmed,
                    encoding: .base64,
                    replaceRecentBlockhash: true
                )
            )
            return .proceed
        } catch SolanaRPCError.transactionSimulationError(let logs) {
            return blockedOutcome(
                reason: "Phantom signed transaction failed simulation",
                logs: logs,
                extraMetadata: ["kind": "simulationErr"],
                swapMetadata: swapMetadata
            )
        } catch SolanaRPCError.responseError(let response) {
            var extra: [String: String] = ["kind": "preflightRejection"]
            if let code = response.code { extra["code"] = "\(code)" }
            if let message = response.message { extra["message"] = message }
            return blockedOutcome(
                reason: "Phantom signed transaction rejected at preflight",
                logs: response.data?.logs ?? [],
                extraMetadata: extra,
                swapMetadata: swapMetadata
            )
        } catch {
            logger.warning("Simulation RPC failed, proceeding to submit", metadata: ["error": "\(error)"])
            return .proceed
        }
    }

    private func blockedOutcome(
        reason: String,
        logs: [String],
        extraMetadata: [String: String],
        swapMetadata: [String: String]
    ) -> SimulationOutcome {
        logger.error("Blocking signed transaction after RPC rejection", metadata: [
            "kind": "\(extraMetadata["kind"] ?? "unknown")",
            "code": "\(extraMetadata["code"] ?? "")",
            "message": "\(extraMetadata["message"] ?? "")",
            "logs": "\(logs.suffix(5).joined(separator: " | "))",
        ])
        ErrorReporting.captureError(
            WalletConnection.Error.simulationFailed(logs: logs),
            reason: reason,
            metadata: swapMetadata.merging(extraMetadata) { current, _ in current }
        )
        return .blocked(.init(
            style: .destructive,
            title: "Transaction Failed",
            subtitle: "The Solana network wouldn't accept this transaction from your wallet. No funds were moved. Please try again.",
            dismissable: true
        ) {
            .okay(kind: .destructive)
        })
    }

    private func reset() async {
        operation = nil
        launchHandler = nil
        pendingSwap = nil
        state = .idle
    }
}

// MARK: - WalletProcessingState

/// External-wallet processing state. Variants differ by flow (buy-existing vs
/// currency launch) and each carries an `isFailed` flag that drives the
/// processing screen's "cancelled" display without requiring a separate flag
/// that could drift out of sync with the active context.
enum WalletProcessingState: Hashable {
    case idle
    case buying(ExternalSwapProcessing, isFailed: Bool)
    case launching(ExternalLaunchProcessing, isFailed: Bool)

    /// Returns a new state with the same context but `isFailed = true`.
    /// No-op for `.idle`.
    func markedFailed() -> WalletProcessingState {
        switch self {
        case .idle:                                return .idle
        case .buying(let context, _):              return .buying(context, isFailed: true)
        case .launching(let context, _):           return .launching(context, isFailed: true)
        }
    }
}
