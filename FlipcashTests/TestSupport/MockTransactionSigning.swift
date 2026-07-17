//
//  MockTransactionSigning.swift
//  FlipcashTests
//

import Foundation
@testable import Flipcash
import FlipcashCore

/// Test fake for `TransactionSigning`. Provides a controllable
/// `deeplinkEvents` stream, call records, and optional handlers to throw or
/// stall each method.
@MainActor
final class MockTransactionSigning: TransactionSigning {

    let deeplinkEvents: AsyncStream<WalletConnection.DeeplinkEvent>
    private let continuation: AsyncStream<WalletConnection.DeeplinkEvent>.Continuation

    private(set) var handshakeCallCount = 0
    private(set) var sendSignRequestCalls: [(usdc: FlipcashCore.TokenAmount, swapId: SwapId)] = []

    var handshakeHandler: (() async throws -> Void)?
    var sendSignRequestHandler: ((FlipcashCore.TokenAmount, SwapId) async throws -> Void)?

    init() {
        let (stream, continuation) = AsyncStream<WalletConnection.DeeplinkEvent>.makeStream()
        self.deeplinkEvents = stream
        self.continuation = continuation
    }

    func handshake() async throws {
        handshakeCallCount += 1
        try await handshakeHandler?()
    }

    func sendUsdcToUsdfSignRequest(
        usdc: FlipcashCore.TokenAmount,
        swapId: SwapId
    ) async throws {
        sendSignRequestCalls.append((usdc, swapId))
        try await sendSignRequestHandler?(usdc, swapId)
    }

    /// Simulates Phantom returning a deeplink callback. Yielding `.signed`
    /// is what unblocks the operation's `awaitSignedTransaction` step.
    func yieldDeeplinkEvent(_ event: WalletConnection.DeeplinkEvent) {
        continuation.yield(event)
    }
}
