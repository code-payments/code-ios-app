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
/// Linear flow:
/// 1. `.launch` only — preflight `session.launchCurrency` so server-side
///    rejections (denied / nameExists / invalidIcon) throw before we hand
///    the user off to Phantom.
/// 2. `state = .awaitingUserAction(.education)` — view shows the education
///    screen; CTA invokes `confirm()`.
/// 3. `state = .awaitingExternal(.phantom)` — `walletConnection.handshake()`
///    deeplinks to Phantom and suspends until the connect callback returns.
/// 4. `state = .awaitingUserAction(.confirm)` — view shows the confirm
///    screen; CTA invokes `confirm()` again.
/// 5. `state = .awaitingExternal(.phantom)` — sign request deeplinks to
///    Phantom and we suspend on `deeplinkEvents` for `.signed` / `.userCancelled`
///    / `.failed`.
/// 6. `state = .working` — simulate the signed tx, notify the server (records
///    the swap), submit to chain. Throws on any failure.
///
/// `launchedMint` is populated immediately after a successful preflight so
/// callers can detect "launch succeeded, downstream step threw" if `start()`
/// throws mid-flow.
@Observable
final class PhantomFundingOperation: FundingOperation {

    private(set) var state: FundingOperationState = .idle
    let requirements: [FundingRequirement] = []

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
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: { [weak self] in
            task.cancel()
            Task { @MainActor [weak self] in
                self?.confirmContinuation?.resume(throwing: CancellationError())
                self?.confirmContinuation = nil
            }
        }
    }

    func confirm() {
        confirmContinuation?.resume()
        confirmContinuation = nil
    }

    func cancel() {
        runTask?.cancel()
    }

    // MARK: - Run

    private func run(_ operation: PaymentOperation) async throws -> StartedSwap {
        // Reset state on any exit (return or throw). Without this, a throw
        // from `handshake()` / `sendUsdcToUsdfSignRequest()` /
        // `awaitSignedTransaction()` leaves state at `.awaitingExternal`,
        // and the prompt screen's CTA stays in its "Connecting…" /
        // "Waiting for Phantom…" spinner forever.
        defer { state = .idle }

        try await preflightLaunchIfNeeded(operation)

        state = .awaitingUserAction(.education(operation))
        try await waitForConfirm()

        state = .awaitingExternal(.phantom)
        try await walletConnection.handshake()

        state = .awaitingUserAction(.confirm(operation))
        try await waitForConfirm()

        let fundingSwapId = SwapId.generate()
        state = .awaitingExternal(.phantom)
        try await walletConnection.sendUsdcToUsdfSignRequest(
            usdc: operation.displayAmount.onChainAmount,
            fundingSwapId: fundingSwapId,
            displayName: operation.currencyName
        )

        let signedTx = try await awaitSignedTransaction()

        state = .working
        return try await submitAndNotify(
            signedTx: signedTx,
            operation: operation,
            fundingSwapId: fundingSwapId
        )
    }

    private func preflightLaunchIfNeeded(_ operation: PaymentOperation) async throws {
        switch operation {
        case .buy:
            return
        case .launch(let payload):
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
