//
//  PhantomDepositOperationTests.swift
//  FlipcashTests
//

import Foundation
import Testing
@testable import Flipcash
import FlipcashCore

@Suite("PhantomDepositOperation") @MainActor
struct PhantomDepositOperationTests {

    @Test("Deposit happy path: connect handshakes, then sign submits a deposit-targeted swap to chain")
    func happyPath() async throws {
        let session = MockSession()
        let wallet = MockTransactionSigning()
        let rpc = MockSolanaRPC()
        let calls = CallLog()
        rpc.simulateHandler = { _ in calls.record("simulate"); return SolanaSimulationResult() }
        rpc.sendHandler = { _ in calls.record("send"); return .mock }

        let op = PhantomDepositOperation(walletConnection: wallet, session: session, rpc: rpc)

        // Education screen: connect.
        try await op.connect()
        #expect(wallet.handshakeCallCount == 1)
        #expect(op.state == .idle)

        // Amount screen: sign + submit.
        let task = Task { try await op.signAndSubmit(amount: .tenUSDF) }
        try await waitUntil(op) { $0.state == .awaitingExternal(.phantomSign) }
        wallet.yieldDeeplinkEvent(.signed(Self.validSignedTransactionBase58))
        try await task.value

        #expect(wallet.depositSignRequestCalls.count == 1)
        // Chain submit runs strictly after simulate.
        #expect(calls.log == ["simulate", "send"])
        #expect(op.state == .idle)
    }

    @Test("signAndSubmit signs against the connect session and never re-handshakes")
    func signAndSubmit_doesNotReHandshake() async throws {
        let wallet = MockTransactionSigning()
        let rpc = MockSolanaRPC()
        rpc.simulateHandler = { _ in SolanaSimulationResult() }
        rpc.sendHandler = { _ in .mock }
        let op = PhantomDepositOperation(walletConnection: wallet, session: MockSession(), rpc: rpc)

        let task = Task { try await op.signAndSubmit(amount: .tenUSDF) }
        try await waitUntil(op) { $0.state == .awaitingExternal(.phantomSign) }
        wallet.yieldDeeplinkEvent(.signed(Self.validSignedTransactionBase58))
        try await task.value

        #expect(wallet.handshakeCallCount == 0)
        #expect(wallet.depositSignRequestCalls.count == 1)
    }

    @Test("Sign request targets the user's USDF VM deposit account")
    func signRequestTargetsDepositAddress() async throws {
        let session = MockSession()
        let wallet = MockTransactionSigning()
        let op = PhantomDepositOperation(walletConnection: wallet, session: session, rpc: MockSolanaRPC())

        let task = Task { try await op.signAndSubmit(amount: .tenUSDF) }
        try await waitUntil(op) { $0.state == .awaitingExternal(.phantomSign) }
        wallet.yieldDeeplinkEvent(.signed(Self.validSignedTransactionBase58))
        try await task.value

        let request = try #require(wallet.depositSignRequestCalls.first)
        #expect(request.destination == Self.expectedDepositATA(owner: session.owner.authorityPublicKey))
        #expect(request.usdc == ExchangedFiat.tenUSDF.onChainAmount)
    }

    @Test("Connect user-cancel throws userCancelled")
    func connectUserCancelled_throws() async {
        let wallet = MockTransactionSigning()
        wallet.handshakeHandler = { throw WalletConnectionError.userCancelledConnect }
        let op = PhantomDepositOperation(walletConnection: wallet, session: MockSession(), rpc: MockSolanaRPC())

        await #expect(throws: DepositError.userCancelled) {
            try await op.connect()
        }
        #expect(wallet.depositSignRequestCalls.isEmpty)
        #expect(op.state == .idle)
    }

    @Test("Sign user-cancel throws userCancelled")
    func signUserCancelled_throws() async throws {
        let wallet = MockTransactionSigning()
        let op = PhantomDepositOperation(walletConnection: wallet, session: MockSession(), rpc: MockSolanaRPC())

        let task = Task { try await op.signAndSubmit(amount: .tenUSDF) }
        try await waitUntil(op) { $0.state == .awaitingExternal(.phantomSign) }
        wallet.yieldDeeplinkEvent(.userCancelled)

        await #expect(throws: DepositError.userCancelled) {
            try await task.value
        }
        #expect(op.state == .idle)
    }
}

// MARK: - Fixtures + helpers

private extension ExchangedFiat {
    static let tenUSDF = ExchangedFiat(nativeAmount: .usd(10), rate: .oneToOne)
}

private extension PhantomDepositOperationTests {

    /// Base58 of a real SolanaTransaction so the operation's
    /// `SolanaTransaction(data:)` decode succeeds and drives simulate + submit
    /// through the default success-returning `MockSolanaRPC`.
    static let validSignedTransactionBase58: String = {
        let instructions = SwapInstructionBuilder.buildUsdcToUsdfSwapInstructions(
            sender: PublicKey.mock,
            owner: PublicKey.mock,
            amount: 1_000_000,
            pool: .usdf,
            swapId: PublicKey.mock,
            destination: .vmDeposit
        )
        let tx = SolanaTransaction(
            payer: PublicKey.mock,
            recentBlockhash: Hash.mock,
            instructions: instructions
        )
        return Base58.fromBytes(Array(tx.encode()))
    }()

    /// Independently recomputes the USDF VM deposit ATA the operation should
    /// target, from the same public FlipcashCore derivation APIs.
    static func expectedDepositATA(owner: PublicKey) -> PublicKey {
        let vm = MintMetadata.usdf.vmMetadata!
        let lockout = Byte(exactly: vm.lockDurationInDays)!
        let depositPda = PublicKey.deriveDepositAccount(
            owner: owner, mint: .usdf, timeAuthority: vm.authority, lockout: lockout
        )!
        return PublicKey.deriveAssociatedAccount(from: depositPda.publicKey, mint: .usdf)!.publicKey
    }
}

/// Ordered, thread-safe call recorder — the RPC handlers run off the main
/// actor. Reads happen only after the operation has fully returned.
private final class CallLog: @unchecked Sendable {
    private(set) var log: [String] = []
    func record(_ name: String) { log.append(name) }
}
