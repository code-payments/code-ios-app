//
//  WalletProcessingStateTests.swift
//  FlipcashTests
//

import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("WalletProcessingState")
struct WalletProcessingStateTests {

    // nonisolated: referenced from @Test(arguments:) array literals which
    // must evaluate at type init, before MainActor context is available.
    nonisolated private static let buyingContext = ExternalSwapProcessing(
        swapId: .generate(),
        currencyName: "Test Coin",
        amount: ExchangedFiat.mockOne
    )

    // nonisolated: referenced from @Test(arguments:) array literals which
    // must evaluate at type init, before MainActor context is available.
    nonisolated private static let launchingContext = ExternalLaunchProcessing(
        swapId: .generate(),
        launchedMint: .jeffy,
        currencyName: "New Coin",
        amount: ExchangedFiat.mockOne
    )

    @Test("`.idle.markedFailed()` is `.idle`")
    func markedFailedIdleIsFixedPoint() {
        #expect(WalletProcessingState.idle.markedFailed() == .idle)
    }

    @Test(
        "`markedFailed()` flips `isFailed` while preserving the active context",
        arguments: [
            (WalletProcessingState.buying(buyingContext, isFailed: false),
             WalletProcessingState.buying(buyingContext, isFailed: true)),
            (WalletProcessingState.launching(launchingContext, isFailed: false),
             WalletProcessingState.launching(launchingContext, isFailed: true)),
        ]
    )
    func markedFailedFlipsFlag(initial: WalletProcessingState, expected: WalletProcessingState) {
        #expect(initial.markedFailed() == expected)
    }

    @Test(
        "`markedFailed()` is idempotent on already-failed states",
        arguments: [
            WalletProcessingState.buying(buyingContext, isFailed: true),
            WalletProcessingState.launching(launchingContext, isFailed: true),
        ]
    )
    func markedFailedIdempotent(failedState: WalletProcessingState) {
        #expect(failedState.markedFailed() == failedState)
    }
}
