//
//  PhantomDepositOperation.swift
//  Flipcash
//

import Foundation
import Observation
import FlipcashCore

private let logger = Logger(label: "flipcash.phantom-deposit")

/// Deposits USDF through Phantom: `connect()` establishes the wallet session
/// from the education screen, then `signAndSubmit(amount:)` has Phantom sign a
/// USDC→USDF swap into the user's USDF VM deposit account and submits it to
/// chain — Geyser credits the balance server-side, no intent is recorded.
/// Both throw `DepositError`; retry is a caller concern.
@Observable
final class PhantomDepositOperation {

    private(set) var state: DepositOperationState = .idle

    /// The signature of the last successfully submitted deposit transaction.
    private(set) var submittedSignature: String?

    @ObservationIgnored private let walletConnection: any TransactionSigning
    @ObservationIgnored private let rpc: any SolanaRPC

    @ObservationIgnored private var runTask: Task<Void, Error>?

    init(
        walletConnection: any TransactionSigning,
        rpc: any SolanaRPC = SolanaJSONRPCClient()
    ) {
        self.walletConnection = walletConnection
        self.rpc = rpc
    }

    isolated deinit {
        runTask?.cancel()
    }

    // MARK: - Entry

    /// Establishes the Phantom wallet session that `signAndSubmit(amount:)`
    /// signs against.
    func connect() async throws {
        let task = Task { try await runConnect() }
        runTask = task
        defer { runTask = nil }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    /// Has Phantom sign the USDC→USDF swap and submits it to chain. Requires
    /// a live session from a prior `connect()`; it does not re-handshake.
    func signAndSubmit(amount: ExchangedFiat) async throws {
        let task = Task { try await runSignAndSubmit(amount) }
        runTask = task
        defer { runTask = nil }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    func cancel() {
        runTask?.cancel()
    }

    // MARK: - Run

    private func runConnect() async throws {
        // Reset state on any exit so the host view's spinner clears even on a
        // thrown connect.
        defer { state = .idle }

        state = .awaitingExternal(.phantomConnect)
        do {
            try await walletConnection.handshake()
        } catch WalletConnectionError.userCancelledConnect {
            throw DepositError.userCancelled
        } catch WalletConnectionError.connectFailed(let code) {
            logger.error("Phantom connect failed", metadata: ["code": "\(code)"])
            throw DepositError.externalRejected(
                title: "Couldn't Connect",
                subtitle: "Please try again from your wallet"
            )
        }
    }

    private func runSignAndSubmit(_ amount: ExchangedFiat) async throws {
        // Reset state on any exit.
        defer { state = .idle }

        let swapId = SwapId.generate()

        state = .awaitingExternal(.phantomSign)
        try await walletConnection.sendUsdcToUsdfSignRequest(
            usdc: amount.onChainAmount,
            swapId: swapId
        )
        Analytics.addMoneyPaymentInvoked(method: .phantom, exchangedFiat: amount)

        let signedTx = try await awaitSignedTransaction(swapId: swapId)

        state = .working
        try await submit(signedTx: signedTx, swapId: swapId)
    }

    /// Consumes `deeplinkEvents` until the signed transaction arrives, throwing
    /// on cancel or wallet error.
    private func awaitSignedTransaction(swapId: SwapId) async throws -> String {
        for await event in walletConnection.deeplinkEvents {
            try Task.checkCancellation()
            switch event {
            case .signed(let signedTx):
                return signedTx
            case .userCancelled:
                throw DepositError.userCancelled
            case .failed(let code):
                logger.error("Phantom returned error", metadata: [
                    "code": "\(code)",
                    "swapId": "\(swapId.publicKey.base58)",
                ])
                throw DepositError.externalRejected(
                    title: "Transaction Failed",
                    subtitle: "Your wallet rejected the transaction. Please try again."
                )
            }
        }
        logger.warning("Deeplink stream ended without a terminal event", metadata: [
            "swapId": "\(swapId.publicKey.base58)",
        ])
        throw CancellationError()
    }

    // MARK: - Submit

    private func submit(signedTx: String, swapId: SwapId) async throws {
        let rawData = Data(Base58.toBytes(signedTx))
        guard SolanaTransaction(data: rawData) != nil else {
            // An undecodable payload is a Phantom contract violation.
            logger.error("Failed to decode signed transaction", metadata: [
                "swapId": "\(swapId.publicKey.base58)",
            ])
            throw DepositError.unexpectedFailure(reason: "Couldn't decode signed transaction from Phantom")
        }

        let txBase64 = rawData.base64EncodedString()
        try await simulate(txBase64, swapId: swapId)

        do {
            let signature = try await rpc.sendTransaction(
                txBase64,
                configuration: SolanaSendTransactionConfig()
            )
            submittedSignature = signature.base58
            logger.info("Submitted deposit transaction", metadata: [
                "signature": "\(signature.base58)",
                "swapId": "\(swapId.publicKey.base58)",
            ])
        } catch let SolanaRPCError.responseError(response) {
            // The node refused the transaction at its preflight — commonly an
            // expired blockhash after a slow Phantom approval — so nothing was
            // submitted and the user can simply retry.
            logger.error("Chain submission rejected at preflight", metadata: [
                "code": "\(response.code ?? -1)",
                "message": "\(response.message ?? "nil")",
                "swapId": "\(swapId.publicKey.base58)",
            ])
            throw DepositError.externalRejected(
                title: "Transaction Failed",
                subtitle: "The transaction simulation failed. Check your Phantom wallet and try again."
            )
        } catch {
            logger.error("Chain submission failed", metadata: [
                "error": "\(error)",
                "swapId": "\(swapId.publicKey.base58)",
            ])
            throw DepositError.chainSubmitFailed("\(error)")
        }
    }

    /// Pre-flights the signed transaction, throwing only on an explicit RPC
    /// rejection. Transport-level failures proceed to submit — a flaky RPC
    /// must not block a valid deposit.
    private func simulate(_ txBase64: String, swapId: SwapId) async throws {
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
                "swapId": "\(swapId.publicKey.base58)",
            ])
            throw DepositError.externalRejected(
                title: "Transaction Rejected",
                subtitle: "The network wouldn't accept this transaction"
            )
        } catch SolanaRPCError.responseError(let response) {
            logger.error("Phantom signed transaction rejected at preflight", metadata: [
                "code": "\(response.code ?? -1)",
                "message": "\(response.message ?? "nil")",
                "swapId": "\(swapId.publicKey.base58)",
            ])
            throw DepositError.externalRejected(
                title: "Transaction Rejected",
                subtitle: response.message ?? "Preflight rejected by the network"
            )
        } catch {
            logger.warning("Simulation RPC failed, proceeding to submit", metadata: ["error": "\(error)"])
        }
    }
}
