//
//  MockTransactionSigning.swift
//  FlipcashTests
//

import Foundation
@testable import Flipcash
import FlipcashCore

/// Test fake for `TransactionSigning`. Provides:
/// - a controllable `deeplinkEvents` stream (tests yield events into it),
/// - call records for `handshake` / `sendUsdcToUsdfSignRequest`,
/// - optional handlers to throw or stall those methods.
@MainActor
final class MockTransactionSigning: TransactionSigning {

    let deeplinkEvents: AsyncStream<WalletConnection.DeeplinkEvent>
    private let continuation: AsyncStream<WalletConnection.DeeplinkEvent>.Continuation

    private(set) var handshakeCallCount = 0
    private(set) var sendSignRequestCalls: [(usdc: FlipcashCore.TokenAmount, fundingSwapId: SwapId, displayName: String)] = []

    var handshakeHandler: (@MainActor () async throws -> Void)?
    var sendSignRequestHandler: (@MainActor (FlipcashCore.TokenAmount, SwapId, String) async throws -> Void)?

    init() {
        var capturedContinuation: AsyncStream<WalletConnection.DeeplinkEvent>.Continuation!
        self.deeplinkEvents = AsyncStream { continuation in
            capturedContinuation = continuation
        }
        self.continuation = capturedContinuation
    }

    func handshake() async throws {
        handshakeCallCount += 1
        try await handshakeHandler?()
    }

    func sendUsdcToUsdfSignRequest(
        usdc: FlipcashCore.TokenAmount,
        fundingSwapId: SwapId,
        displayName: String
    ) async throws {
        sendSignRequestCalls.append((usdc, fundingSwapId, displayName))
        try await sendSignRequestHandler?(usdc, fundingSwapId, displayName)
    }

    /// Simulates Phantom returning a deeplink callback. Yielding `.signed`
    /// is what unblocks the operation's `awaitSignedTransaction` step.
    func yieldDeeplinkEvent(_ event: WalletConnection.DeeplinkEvent) {
        continuation.yield(event)
    }

    /// Finishes the stream so any pending `for await` loop exits.
    func finishDeeplinkStream() {
        continuation.finish()
    }
}
