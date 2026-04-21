//
//  WalletConnectionStateTests.swift
//  FlipcashTests
//

import Testing
import FlipcashCore
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

    private func makeConnection() -> WalletConnection {
        WalletConnection(owner: .mock, client: .mock)
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
}
