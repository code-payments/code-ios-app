//
//  PhantomDepositOperation.swift
//  Flipcash
//

import Foundation
import Observation
import FlipcashCore

private let logger = Logger(label: "flipcash.phantom-deposit")

/// Deposits USDF into the user's Flipcash wallet through Phantom's connect +
/// sign flow. Phantom signs a USDC→USDF swap whose output lands directly in
/// the user's USDF VM deposit account; Geyser credits the balance server-side.
/// No buy or launch intent is recorded — this is a pure funding deposit.
///
/// Split across the two Add Money screens:
/// - `connect()` — the education screen's CTA. Deeplinks Phantom to establish
///   the Keychain session (`state = .awaitingExternal(.phantomConnect)`).
/// - `signAndSubmit(amount:)` — the amount screen's "Confirm in Phantom".
///   Deeplinks the deposit-targeted USDC→USDF sign request
///   (`state = .awaitingExternal(.phantomSign)`), suspends on `deeplinkEvents`
///   until the signed transaction returns, then simulates and submits to chain
///   (`state = .working`). No re-handshake — the session from `connect()` is
///   seconds old, so signing is a single Phantom round-trip. No server-notify.
///
/// Both throw on wallet-side cancel (`DepositError.userCancelled`), external
/// rejection, or chain submit failure. Retry is a caller concern.
@Observable
final class PhantomDepositOperation {

    private(set) var state: DepositOperationState = .idle

    @ObservationIgnored private let walletConnection: any TransactionSigning
    @ObservationIgnored private let session: any AccountProviding
    @ObservationIgnored private let rpc: any SolanaRPC

    @ObservationIgnored private var runTask: Task<Void, Error>?

    init(
        walletConnection: any TransactionSigning,
        session: any AccountProviding,
        rpc: any SolanaRPC = SolanaJSONRPCClient()
    ) {
        self.walletConnection = walletConnection
        self.session = session
        self.rpc = rpc
    }

    isolated deinit {
        runTask?.cancel()
    }

    // MARK: - Entry

    /// Connects the Phantom wallet — the education screen's CTA. Establishes the
    /// Keychain session `signAndSubmit(amount:)` later signs against.
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

    /// Signs the deposit-targeted USDC→USDF swap and submits it — the amount
    /// screen's "Confirm in Phantom". Assumes a live session from a prior
    /// `connect()`; it does not re-handshake.
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
        // Reset state on any exit (return or throw). Without this, a throw from
        // the sign request / submit leaves state at `.awaitingExternal`, so the
        // host view's spinner never clears.
        defer { state = .idle }

        let destination = try usdfDepositDestination()
        let fundingSwapId = SwapId.generate()

        state = .awaitingExternal(.phantomSign)
        try await walletConnection.sendUsdcToUsdfDepositSignRequest(
            usdc: amount.onChainAmount,
            destination: destination,
            fundingSwapId: fundingSwapId,
            displayName: "USDF"
        )

        let signedTx = try await awaitSignedTransaction()

        state = .working
        try await submit(signedTx: signedTx)
    }

    /// The user's USDF VM deposit token account — where Phantom's signed swap
    /// deposits the converted USDF. Geyser watches this account and credits the
    /// balance server-side.
    private func usdfDepositDestination() throws -> PublicKey {
        guard let vm = MintMetadata.usdf.vmMetadata,
              let lockout = Byte(exactly: vm.lockDurationInDays) else {
            logger.error("USDF metadata missing VM info")
            throw DepositError.unexpectedFailure(reason: "USDF VM metadata unavailable")
        }
        guard let depositPda = PublicKey.deriveDepositAccount(
            owner: session.owner.authorityPublicKey,
            mint: .usdf,
            timeAuthority: vm.authority,
            lockout: lockout
        ), let depositATA = PublicKey.deriveAssociatedAccount(
            from: depositPda.publicKey,
            mint: .usdf
        ) else {
            logger.error("Failed to derive USDF deposit account")
            throw DepositError.unexpectedFailure(reason: "Couldn't derive USDF deposit account")
        }
        return depositATA.publicKey
    }

    /// Consumes `deeplinkEvents` until the signed-tx event arrives. Throws
    /// `.userCancelled` on a wallet 4001 and `.externalRejected` on any other
    /// wallet error.
    private func awaitSignedTransaction() async throws -> String {
        for await event in walletConnection.deeplinkEvents {
            try Task.checkCancellation()
            switch event {
            case .signed(let signedTx):
                return signedTx
            case .userCancelled:
                throw DepositError.userCancelled
            case .failed(let code):
                logger.error("Phantom returned error", metadata: ["code": "\(code)"])
                throw DepositError.externalRejected(
                    title: "Transaction Failed",
                    subtitle: "Your wallet rejected the transaction. Please try again."
                )
            }
        }
        // Stream ended without delivering an event — treat as cancellation.
        throw CancellationError()
    }

    // MARK: - Submit

    private func submit(signedTx: String) async throws {
        let rawData = Data(Base58.toBytes(signedTx))
        guard SolanaTransaction(data: rawData) != nil else {
            // Phantom returned a payload we can't decode — wallet contract
            // violation, worth Bugsnagging.
            logger.error("Failed to decode signed transaction")
            throw DepositError.unexpectedFailure(reason: "Couldn't decode signed transaction from Phantom")
        }

        let txBase64 = rawData.base64EncodedString()
        try await simulate(txBase64)

        // No server-notify: the deposit is credited by Geyser once the swap
        // lands in the USDF deposit account. Submit straight to chain.
        do {
            _ = try await rpc.sendTransaction(
                txBase64,
                configuration: SolanaSendTransactionConfig()
            )
        } catch {
            logger.error("Chain submission failed", metadata: ["error": "\(error)"])
            throw DepositError.chainSubmitFailed("\(error)")
        }
    }

    /// Pre-flights the signed tx. Treats transport-level failures as proceed —
    /// a flaky RPC blip must not block a user with valid funds; only explicit
    /// RPC rejections throw.
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
            throw DepositError.externalRejected(
                title: "Transaction Rejected",
                subtitle: "The network wouldn't accept this transaction"
            )
        } catch SolanaRPCError.responseError(let response) {
            logger.error("Phantom signed transaction rejected at preflight", metadata: [
                "code": "\(response.code ?? -1)",
                "message": "\(response.message ?? "nil")",
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
