//
//  PhantomFundingOperation.swift
//  Flipcash
//

import Foundation
import Observation
import FlipcashCore

private let logger = Logger(label: "flipcash.phantom-funding")

/// Funds a buy or launch by routing the user through Phantom's deeplink
/// connect + sign flow.
///
/// Flow (the connect and sign steps each loop on wallet-side cancel):
/// 1. `.launch` only — preflight `session.launchCurrency` so server-side
///    rejections (denied / nameExists / invalidIcon) throw before we hand
///    the user off to Phantom.
/// 2. `state = .awaitingUserAction(.education)` — host renders the
///    education panel; CTA invokes `confirm()`.
/// 3. `state = .awaitingExternal(.phantomConnect)` — `handshake()` deeplinks
///    to Phantom. On user-cancel (`userCancelledConnect`), set
///    `lastErrorMessage` and loop back to step 2 so the user can retry
///    without restarting.
/// 4. `state = .awaitingUserAction(.confirm)` — host renders the confirm
///    panel; CTA invokes `confirm()` again.
/// 5. `state = .awaitingExternal(.phantomSign)` — sign request deeplinks
///    to Phantom and we suspend on `deeplinkEvents`. On user-cancel (wallet
///    code 4001 → `FundingOperationError.userCancelled` from
///    `awaitSignedTransaction`), loop back to step 4.
/// 6. `state = .working` — simulate the signed tx, notify the server (records
///    the swap), submit to chain. Throws on any failure.
///
/// `start()` only throws on terminal failures (non-cancel `connectFailed`,
/// server reject, chain submit) or external `cancel()` (CancellationError).
/// `launchedMint` is populated immediately after a successful preflight so
/// callers can detect "launch succeeded, downstream step threw" if `start()`
/// throws mid-flow.
@Observable
final class PhantomFundingOperation: FundingOperation {

    private(set) var state: FundingOperationState = .idle
    let requirements: [FundingRequirement] = []

    /// Last wallet-side cancel reason. Cleared on `confirm()` so the banner
    /// disappears the moment the user taps retry.
    private(set) var lastErrorMessage: String?

    /// Set after a successful `.launch` preflight. Lets callers recover the
    /// minted PublicKey when the post-launch chain dance throws.
    private(set) var launchedMint: PublicKey?

    @ObservationIgnored private let walletConnection: any TransactionSigning
    @ObservationIgnored private let session: any (ExternalFundingBuying & CurrencyLaunching)
    @ObservationIgnored private let rpc: any SolanaRPC

    @ObservationIgnored private var runTask: Task<StartedSwap, Error>?
    @ObservationIgnored private var confirmContinuation: CheckedContinuation<Void, Error>?

    init(
        walletConnection: any TransactionSigning,
        session: any (ExternalFundingBuying & CurrencyLaunching),
        rpc: any SolanaRPC = SolanaJSONRPCClient()
    ) {
        self.walletConnection = walletConnection
        self.session = session
        self.rpc = rpc
    }

    isolated deinit {
        runTask?.cancel()
    }

    // MARK: - FundingOperation

    func start(_ operation: PaymentOperation) async throws -> StartedSwap {
        let task = Task { try await run(operation) }
        runTask = task
        defer { runTask = nil }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: { [weak self] in
            task.cancel()
            Task { @MainActor [weak self] in
                self?.cancelPendingConfirm()
            }
        }
    }

    func confirm() {
        lastErrorMessage = nil
        let continuation = confirmContinuation
        confirmContinuation = nil
        continuation?.resume()
    }

    func cancel() {
        runTask?.cancel()
        // The inner Task's cancellation flag alone doesn't unblock a
        // suspended `CheckedContinuation` — resume it so `run()` wakes,
        // sees the `CancellationError`, and exits the retry loop. The
        // catches in `run()` only match user-cancel variants, so
        // `CancellationError` propagates and `start()` rethrows.
        cancelPendingConfirm()
    }

    /// Shared body for cancellation paths: read-and-clear the slot, then
    /// resume the consumed continuation. Mirrors
    /// `WalletConnection.cancelPendingConnect` for consistency and keeps
    /// the slot empty before the resume so any tardy main-actor hop sees
    /// `nil` rather than a stale continuation.
    private func cancelPendingConfirm() {
        guard let continuation = confirmContinuation else { return }
        confirmContinuation = nil
        continuation.resume(throwing: CancellationError())
    }

    // MARK: - Run

    private func run(_ operation: PaymentOperation) async throws -> StartedSwap {
        // Reset state on any exit (return or throw). Without this, a throw
        // from `sendUsdcToUsdfSignRequest()` / submit leaves state at
        // `.awaitingExternal`, so the host view's spinner never clears.
        defer { state = .idle }

        try await preflightLaunchIfNeeded(operation)

        // Connect step — wallet-side cancel loops back to the education
        // prompt; non-cancel failures propagate. Sets `lastErrorMessage` on
        // each cancel so the host can render an inline banner.
        while true {
            try Task.checkCancellation()
            state = .awaitingUserAction(.education(operation))
            try await waitForConfirm()

            state = .awaitingExternal(.phantomConnect)
            do {
                try await walletConnection.handshake()
                break
            } catch WalletConnectionError.userCancelledConnect {
                lastErrorMessage = "Connection cancelled in Phantom"
                // loop: top of next iteration resets state to .education
            } catch WalletConnectionError.connectFailed(let code) {
                throw FundingOperationError.serverRejected("Wallet connect failed (code: \(code))")
            }
        }

        // Sign step — wallet-side cancel (deeplink code 4001) loops back to
        // the confirm prompt; serverRejected and other terminal failures
        // propagate.
        while true {
            try Task.checkCancellation()
            state = .awaitingUserAction(.confirm(operation))
            try await waitForConfirm()

            let fundingSwapId = SwapId.generate()
            state = .awaitingExternal(.phantomSign)
            try await walletConnection.sendUsdcToUsdfSignRequest(
                usdc: operation.displayAmount.onChainAmount,
                fundingSwapId: fundingSwapId,
                displayName: operation.currencyName
            )

            let signedTx: String
            do {
                signedTx = try await awaitSignedTransaction()
            } catch FundingOperationError.userCancelled {
                lastErrorMessage = "Transaction cancelled in Phantom"
                continue
            }

            state = .working
            return try await submitAndNotify(
                signedTx: signedTx,
                operation: operation,
                fundingSwapId: fundingSwapId
            )
        }
    }

    private func preflightLaunchIfNeeded(_ operation: PaymentOperation) async throws {
        switch operation {
        case .buy:
            return
        case .launch(let payload):
            // Retry from a prior attempt whose launch already succeeded —
            // skip the launch RPC so the server doesn't return `nameExists`.
            if let preLaunched = payload.preLaunchedMint {
                launchedMint = preLaunched
                return
            }
            guard let attestations = payload.attestations else {
                logger.error("Phantom launch invoked without attestations")
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

    private func waitForConfirm() async throws {
        try await withCheckedThrowingContinuation { continuation in
            confirmContinuation = continuation
        }
    }

    /// Consumes events from `walletConnection.deeplinkEvents` until the
    /// awaited signed-tx event arrives. Throws `FundingOperationError.userCancelled`
    /// on a wallet 4001 (so callers can surface a "Transaction Cancelled"
    /// dialog distinct from a silent Task-level cancellation) and
    /// `.serverRejected` on any other wallet error.
    private func awaitSignedTransaction() async throws -> String {
        for await event in walletConnection.deeplinkEvents {
            try Task.checkCancellation()
            switch event {
            case .signed(let signedTx):
                return signedTx
            case .userCancelled:
                throw FundingOperationError.userCancelled
            case .failed(let code):
                throw FundingOperationError.serverRejected("Wallet returned error code \(code)")
            }
        }
        // Stream ended without delivering an event — treat as cancellation.
        throw CancellationError()
    }

    // MARK: - Submit + notify

    private func submitAndNotify(
        signedTx: String,
        operation: PaymentOperation,
        fundingSwapId: SwapId
    ) async throws -> StartedSwap {
        let rawData = Data(Base58.toBytes(signedTx))
        guard let tx = SolanaTransaction(data: rawData) else {
            logger.error("Failed to decode signed transaction")
            throw FundingOperationError.serverRejected("Couldn't decode the signed transaction")
        }

        let txBase64 = rawData.base64EncodedString()
        try await simulate(txBase64)

        // Server-notify FIRST. If the server rejects, skip chain submission
        // entirely so no USDC moves without a recorded swap.
        let swapId: SwapId
        let swapType: SwapType
        let launched: PublicKey?

        switch operation {
        case .buy(let payload):
            swapId = try await session.buyWithExternalFunding(
                swapId: fundingSwapId,
                amount: payload.amount,
                of: payload.mint,
                transactionSignature: tx.identifier
            )
            swapType = .buyWithPhantom
            launched = nil

        case .launch(let payload):
            guard let mint = launchedMint else {
                logger.error("Launch reached submit step without a preflighted mint")
                throw FundingOperationError.serverRejected("Missing launched mint")
            }
            swapId = try await session.buyNewCurrencyWithExternalFunding(
                amount: payload.launchAmount,
                feeAmount: payload.launchFee,
                mint: mint,
                transactionSignature: tx.identifier
            )
            swapType = .launchWithPhantom
            launched = mint
        }

        // Server accepted — submit to chain. Failure here throws and the
        // caller maps to a dialog; the server-recorded swap will surface
        // via its own polling.
        do {
            _ = try await rpc.sendTransaction(
                txBase64,
                configuration: SolanaSendTransactionConfig()
            )
        } catch {
            logger.error("Chain submission failed", metadata: ["error": "\(error)"])
            throw FundingOperationError.chainSubmitFailed("\(error)")
        }

        return StartedSwap(
            swapId: swapId,
            swapType: swapType,
            currencyName: operation.currencyName,
            amount: operation.displayAmount,
            launchedMint: launched
        )
    }

    /// Pre-flights the signed tx against the network. Treats transport-level
    /// failures as `.proceed` — a flaky RPC blip must not block a user with
    /// valid funds; only explicit RPC rejections throw.
    private func simulate(_ txBase64: String) async throws {
        do {
            _ = try await rpc.simulateTransaction(
                txBase64,
                configuration: SolanaSimulateTransactionConfig(
                    commitment: .confirmed,
                    encoding: .base64,
                    replaceRecentBlockhash: true
                )
            )
        } catch SolanaRPCError.transactionSimulationError(let logs) {
            logger.error("Phantom signed transaction failed simulation", metadata: [
                "logs": "\(logs.suffix(5).joined(separator: " | "))",
            ])
            throw FundingOperationError.serverRejected("The network wouldn't accept this transaction")
        } catch SolanaRPCError.responseError(let response) {
            logger.error("Phantom signed transaction rejected at preflight", metadata: [
                "code": "\(response.code ?? -1)",
                "message": "\(response.message ?? "nil")",
            ])
            throw FundingOperationError.serverRejected(response.message ?? "Preflight rejected by the network")
        } catch {
            // Network blip — swallow and continue. The submit step has its
            // own error handling.
            logger.warning("Simulation RPC failed, proceeding to submit", metadata: ["error": "\(error)"])
        }
    }
}

// MARK: - Hashable (identity)

/// Hashable conformance lives in a `nonisolated` extension so the operation
/// can ride inside `AppRouter.Destination` cases — which are `nonisolated`
/// — even though the class is implicitly `@MainActor` (module default).
extension PhantomFundingOperation: @unchecked Sendable {}

nonisolated extension PhantomFundingOperation: Hashable {

    static func == (lhs: PhantomFundingOperation, rhs: PhantomFundingOperation) -> Bool {
        lhs === rhs
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}
