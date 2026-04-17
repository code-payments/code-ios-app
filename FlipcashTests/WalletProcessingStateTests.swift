//
//  WalletProcessingStateTests.swift
//  FlipcashTests
//

import Testing
import FlipcashCore
@testable import Flipcash

@Suite("WalletProcessingState")
struct WalletProcessingStateTests {

    private static let buyingContext = ExternalSwapProcessing(
        swapId: .generate(),
        currencyName: "Test Coin",
        amount: ExchangedFiat(underlying: 10_00_00, converted: 10_00_00, mint: .usdf)
    )

    private static let launchingContext = ExternalLaunchProcessing(
        swapId: .generate(),
        launchedMint: .jeffy,
        currencyName: "New Coin",
        amount: ExchangedFiat(underlying: 10_00_00, converted: 10_00_00, mint: .usdf)
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
