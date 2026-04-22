//
//  WalletConnectionStateTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashCore
import SolanaSwift
@testable import Flipcash

@MainActor
@Suite("WalletConnection state machine")
struct WalletConnectionStateTests {

    private static let buyingContext = ExternalSwapProcessing(
        swapId: .generate(),
        currencyName: "Test Coin",
        amount: ExchangedFiat.mockOne
    )

    private static let launchingContext = ExternalLaunchProcessing(
        swapId: .generate(),
        launchedMint: .jeffy,
        currencyName: "New Coin",
        amount: ExchangedFiat.mockOne
    )

    private func makeConnection(rpc: WalletRPC? = nil) -> WalletConnection {
        WalletConnection(owner: .mock, client: .mock, rpc: rpc)
    }

    @Test("`.idle` reports no active processing")
    func idleReportsNoProcessing() {
        let conn = makeConnection()
        #expect(conn.state == .idle)
        #expect(conn.processing == nil)
        #expect(conn.launchProcessing == nil)
        #expect(conn.isProcessingCancelled == false)
    }

    @Test("`.buying` exposes context via `processing`, not `launchProcessing`")
    func buyingExposesProcessing() {
        let conn = makeConnection()
        conn.state = .buying(Self.buyingContext, isFailed: false)
        #expect(conn.processing == Self.buyingContext)
        #expect(conn.launchProcessing == nil)
        #expect(conn.isProcessingCancelled == false)
    }

    @Test("`.launching` exposes context via `launchProcessing`, not `processing`")
    func launchingExposesLaunchProcessing() {
        let conn = makeConnection()
        conn.state = .launching(Self.launchingContext, isFailed: false)
        #expect(conn.launchProcessing == Self.launchingContext)
        #expect(conn.processing == nil)
        #expect(conn.isProcessingCancelled == false)
    }

    @Test(
        "`isFailed: true` surfaces through `isProcessingCancelled`, context preserved",
        arguments: [
            WalletProcessingState.buying(buyingContext, isFailed: true),
            WalletProcessingState.launching(launchingContext, isFailed: true),
        ]
    )
    func failedStateFlipsCancelledFlag(initial: WalletProcessingState) {
        let conn = makeConnection()
        conn.state = initial
        #expect(conn.isProcessingCancelled == true)
        #expect(conn.state == initial)
    }

    @Test("Setting `processing = nil` transitions `.buying` to `.idle`")
    func nillingProcessingWhileBuyingResetsToIdle() {
        let conn = makeConnection()
        conn.state = .buying(Self.buyingContext, isFailed: false)
        conn.processing = nil
        #expect(conn.state == .idle)
    }

    @Test("Setting `processing = nil` while `.launching` is a no-op")
    func nillingProcessingWhileLaunchingIsNoOp() {
        let conn = makeConnection()
        let initial = WalletProcessingState.launching(Self.launchingContext, isFailed: false)
        conn.state = initial
        conn.processing = nil
        #expect(conn.state == initial)
    }

    @Test("Setting `launchProcessing = nil` transitions `.launching` to `.idle`")
    func nillingLaunchProcessingWhileLaunchingResetsToIdle() {
        let conn = makeConnection()
        conn.state = .launching(Self.launchingContext, isFailed: false)
        conn.launchProcessing = nil
        #expect(conn.state == .idle)
    }

    @Test("Setting `launchProcessing = nil` while `.buying` is a no-op")
    func nillingLaunchProcessingWhileBuyingIsNoOp() {
        let conn = makeConnection()
        let initial = WalletProcessingState.buying(Self.buyingContext, isFailed: false)
        conn.state = initial
        conn.launchProcessing = nil
        #expect(conn.state == initial)
    }

    @Test(
        "`dismissProcessing()` resets to `.idle` from any active state",
        arguments: [
            WalletProcessingState.buying(buyingContext, isFailed: false),
            WalletProcessingState.buying(buyingContext, isFailed: true),
            WalletProcessingState.launching(launchingContext, isFailed: false),
            WalletProcessingState.launching(launchingContext, isFailed: true),
        ]
    )
    func dismissProcessingResetsActiveStates(initial: WalletProcessingState) {
        let conn = makeConnection()
        conn.state = initial
        conn.dismissProcessing()
        #expect(conn.state == .idle)
    }

    @Test("`dismissProcessing()` clears `dialogItem` even when `.idle`")
    func dismissProcessingClearsDialog() {
        let conn = makeConnection()
        conn.dialogItem = .init(
            style: .destructive,
            title: "T",
            subtitle: "S",
            dismissable: true
        ) { .okay(kind: .destructive) }
        conn.dismissProcessing()
        #expect(conn.dialogItem == nil)
        #expect(conn.state == .idle)
    }

    // MARK: - Simulation outcome -

    @Test("Preflight rejection returns `.blocked` with a user-facing dialog")
    func simulationRejectionBlocks() async {
        let conn = makeConnection(rpc: StubRPC(simulate: .failure(
            APIClientError.transactionSimulationError(logs: [
                "Program 11111111 invoke [1]",
                "Transfer: insufficient lamports",
                "Program 11111111 failed: custom program error: 0x1",
            ])
        )))

        let outcome = await conn.simulateSignedTransaction("dummyBase64", swapMetadata: [:])

        switch outcome {
        case .proceed:
            Issue.record("Expected .blocked for simulation rejection")
        case .blocked(let dialog):
            #expect(dialog.title == "Transaction Failed")
            #expect(dialog.subtitle?.contains("wouldn't accept") == true)
        }
    }

    @Test("Non-simulation errors pass through as `.proceed`")
    func simulationTransportErrorProceeds() async {
        let conn = makeConnection(rpc: StubRPC(simulate: .failure(URLError(.timedOut))))

        let outcome = await conn.simulateSignedTransaction("dummyBase64", swapMetadata: [:])

        if case .blocked = outcome {
            Issue.record("Transport errors must not block — the RPC may just be flaky")
        }
    }

    @Test("Successful simulation returns `.proceed`")
    func simulationSuccessProceeds() async {
        let conn = makeConnection(rpc: StubRPC(simulate: .succeeds))

        let outcome = await conn.simulateSignedTransaction("dummyBase64", swapMetadata: [:])

        if case .blocked = outcome {
            Issue.record("Successful simulation must proceed to chain submission")
        }
    }

    // MARK: - completeSwap full flow -

    @Test(
        "Any RPC-reported preflight rejection halts the flow before server + chain submit",
        arguments: [
            APIClientError.transactionSimulationError(logs: ["insufficient funds"]),
            APIClientError.responseError(ResponseError(
                code: -32002,
                message: "insufficient funds",
                data: ResponseErrorData(logs: ["Transfer: insufficient lamports"], numSlotsBehind: nil)
            )),
        ]
    )
    func completeSwap_preflightRejectionHaltsFlow(_ rpcError: APIClientError) async {
        let rpc = StubRPC(
            simulate: .failure(rpcError),
            send: .failure(TestError.shouldNotBeCalled)
        )
        let conn = makeConnection(rpc: rpc)
        let pending = Self.makePendingSwap(onCompleted: { _, _ in
            Issue.record("Server notification must not run after preflight rejection")
            throw TestError.shouldNotBeCalled
        })

        await conn.completeSwap(signedTx: Self.validSignedTxBase58(), pending: pending).value

        #expect(conn.state == .idle)
        #expect(conn.dialogItem?.title == "Transaction Failed")
    }

    @Test("Chain submit failure flips `.buying` to isFailed: true")
    func completeSwap_chainSubmitFailureMarksFailed() async {
        let swapId = SwapId.generate()
        let rpc = StubRPC(simulate: .succeeds, send: .failure(URLError(.networkConnectionLost)))
        let conn = makeConnection(rpc: rpc)
        let pending = Self.makePendingSwap(
            fundingSwapId: swapId,
            onCompleted: { _, _ in .buyExisting(swapId: swapId) }
        )

        await conn.completeSwap(signedTx: Self.validSignedTxBase58(), pending: pending).value

        guard case .buying(_, let isFailed) = conn.state else {
            Issue.record("Expected state to remain `.buying` so the processing screen can surface the failure")
            return
        }
        #expect(isFailed == true)
    }

    @Test("Chain submit success for `.buyExisting` leaves `.buying` clean")
    func completeSwap_buyExistingSuccessStaysBuying() async {
        let swapId = SwapId.generate()
        let rpc = StubRPC(simulate: .succeeds, send: .succeeds(signature: "sig-1"))
        let conn = makeConnection(rpc: rpc)
        let pending = Self.makePendingSwap(
            fundingSwapId: swapId,
            onCompleted: { _, _ in .buyExisting(swapId: swapId) }
        )

        await conn.completeSwap(signedTx: Self.validSignedTxBase58(), pending: pending).value

        guard case .buying(let ctx, let isFailed) = conn.state else {
            Issue.record("Expected `.buying` state after successful buy-existing flow")
            return
        }
        #expect(isFailed == false)
        #expect(ctx.swapId == swapId)
    }

    @Test("Chain submit success for `.launch` transitions state to `.launching`")
    func completeSwap_launchSuccessTransitionsToLaunching() async {
        let fundingId = SwapId.generate()
        let buyId = SwapId.generate()
        let mint = PublicKey.mock
        let rpc = StubRPC(simulate: .succeeds, send: .succeeds(signature: "sig-2"))
        let conn = makeConnection(rpc: rpc)
        let pending = Self.makePendingSwap(
            fundingSwapId: fundingId,
            onCompleted: { _, _ in .launch(swapId: buyId, mint: mint) }
        )

        await conn.completeSwap(signedTx: Self.validSignedTxBase58(), pending: pending).value

        guard case .launching(let ctx, let isFailed) = conn.state else {
            Issue.record("Expected `.launching` state after successful launch flow")
            return
        }
        #expect(isFailed == false)
        #expect(ctx.swapId == buyId)
        #expect(ctx.launchedMint == mint)
    }

    @Test("Server notification failure resets to `.idle` without submitting")
    func completeSwap_serverNotificationFailureResetsToIdle() async {
        let rpc = StubRPC(simulate: .succeeds, send: .failure(TestError.shouldNotBeCalled))
        let conn = makeConnection(rpc: rpc)
        let pending = Self.makePendingSwap(onCompleted: { _, _ in
            throw TestError.serverRejected
        })

        await conn.completeSwap(signedTx: Self.validSignedTxBase58(), pending: pending).value

        #expect(conn.state == .idle)
    }

    @Test("Missing pending is a no-op")
    func completeSwap_nilPendingIsNoOp() async {
        let rpc = StubRPC(
            simulate: .failure(TestError.shouldNotBeCalled),
            send: .failure(TestError.shouldNotBeCalled)
        )
        let conn = makeConnection(rpc: rpc)

        await conn.completeSwap(signedTx: Self.validSignedTxBase58(), pending: nil).value

        #expect(conn.state == .idle)
        #expect(conn.dialogItem == nil)
    }

    // MARK: - Helpers -

    private static func makePendingSwap(
        fundingSwapId: SwapId = .generate(),
        displayName: String = "Test Coin",
        amount: ExchangedFiat = .mockOne,
        onCompleted: @escaping @MainActor @Sendable (FlipcashCore.Signature, ExchangedFiat) async throws -> SignedSwapResult
    ) -> WalletConnection.PendingSwap {
        WalletConnection.PendingSwap(
            fundingSwapId: fundingSwapId,
            amount: amount,
            displayName: displayName,
            onCompleted: onCompleted
        )
    }

    /// Produces base58 bytes that round-trip cleanly through
    /// `SolanaTransaction(data:)` — the decode gate inside `didSignTransaction`.
    /// The signatures are zero-filled, which is fine because the production
    /// flow only reads `tx.identifier` (which maps to `signatures[0]`) and
    /// forwards it to the server-notify closure.
    private static func validSignedTxBase58() -> String {
        let tx = SolanaTransaction(
            payer: PublicKey.mock,
            recentBlockhash: nil,
            instructions: [] as [Instruction]
        )
        return Base58.fromBytes([UInt8](tx.encode()))
    }
}

// MARK: - StubRPC -

/// Minimal `WalletRPC` for tests. Both `simulateTransaction` and
/// `sendTransaction` are configurable; `getLatestBlockhash` traps because no
/// current test exercises paths that fetch a blockhash.
private struct StubRPC: WalletRPC {
    enum SimulateBehavior {
        case succeeds
        case failure(Error)
    }

    enum SendBehavior {
        case succeeds(signature: String)
        case failure(Error)
    }

    let simulate: SimulateBehavior
    let send: SendBehavior

    init(simulate: SimulateBehavior, send: SendBehavior = .failure(TestError.shouldNotBeCalled)) {
        self.simulate = simulate
        self.send = send
    }

    func getLatestBlockhash(commitment: Commitment?) async throws -> String {
        fatalError("getLatestBlockhash not stubbed")
    }

    func sendTransaction(transaction: String, configs: RequestConfiguration) async throws -> TransactionID {
        switch send {
        case .succeeds(let signature):
            return signature
        case .failure(let error):
            throw error
        }
    }

    func simulateTransaction(transaction: String, configs: RequestConfiguration) async throws -> SimulationResult {
        switch simulate {
        case .succeeds:
            let payload = Data(#"{"err":null,"logs":[]}"#.utf8)
            return try JSONDecoder().decode(SimulationResult.self, from: payload)
        case .failure(let error):
            throw error
        }
    }
}

private enum TestError: Error {
    case shouldNotBeCalled
    case serverRejected
}
