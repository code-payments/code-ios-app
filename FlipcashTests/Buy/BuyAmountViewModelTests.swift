//
//  BuyAmountViewModelTests.swift
//  FlipcashTests
//
//  Created by Raul Riera on 2026-05-12.
//

import Foundation
import Testing
@testable import FlipcashCore
@testable import Flipcash

@Suite("BuyAmountViewModel — USDF gate")
@MainActor
struct BuyAmountViewModelTests {

    // MARK: - Test fixtures

    /// Server-provided per-day limit that the gate must clear before any
    /// submission. Set high enough that the test entered amounts ($1–$20) all
    /// pass; the only thing varying between tests is the USDF balance.
    private static let testSendLimit = SendLimit(
        nextTransaction: FiatAmount(value: 1000, currency: .usd),
        maxPerTransaction: FiatAmount(value: 1000, currency: .usd),
        maxPerDay: FiatAmount(value: 1000, currency: .usd)
    )

    /// Builds a `SessionContainer` with the given USDF balance and seeds the
    /// fresh verified state + send limits the viewmodel needs to reach the
    /// USDF gate. Without these, `prepareSubmission` returns nil and the
    /// flow short-circuits at `dialogItem = .staleRate`.
    private static func makeContainer(usdfQuarks: UInt64) async throws -> SessionContainer {
        let holdings: [SessionContainer.Holding] = usdfQuarks == 0
            ? []
            : [.init(mint: MintMetadata.usdf, quarks: usdfQuarks)]

        let container = try SessionContainer.makeTest(
            holdings: holdings,
            limits: Limits(
                sinceDate: .now,
                fetchDate: .now,
                sendLimits: [.usd: testSendLimit]
            )
        )

        // Force USD as the balance currency. Without this the rates controller
        // reads `LocalDefaults.balanceCurrency`, which can be polluted by other
        // suites that called `configureTestRates(balanceCurrency: .cad, ...)` —
        // the persisted `.cad` then makes `currentPinnedState(for: .cad)` return
        // nil here (no CAD pin seeded), routing through `.staleRate` instead
        // of the picker.
        container.ratesController.configureTestRates(
            balanceCurrency: .usd,
            rates: [Rate(fx: 1.0, currency: .usd)]
        )

        // Pin a fresh USD verified state so prepareSubmission() succeeds.
        await container.ratesController.verifiedProtoService.saveRates([
            .freshRate(currencyCode: "USD", rate: 1.0)
        ])

        return container
    }

    private static func makeViewModel(
        mint: PublicKey = .usdf,
        currencyName: String = "Jeffy",
        container: SessionContainer
    ) -> BuyAmountViewModel {
        BuyAmountViewModel(
            mint: mint,
            currencyName: currencyName,
            session: container.session,
            ratesController: container.ratesController
        )
    }

    // MARK: - Gate decision tests

    @Test("Sufficient USDF balance does not surface the funding picker")
    func sufficientBalance_doesNotOpenPicker() async throws {
        // $50 USDF (6 decimals) → balance covers $20 entry.
        let container = try await Self.makeContainer(usdfQuarks: 50_000_000)
        let viewModel = Self.makeViewModel(container: container)
        let router = AppRouter()
        router.present(.balance)

        viewModel.enteredAmount = "20"
        await viewModel.amountEnteredAction(router: router)

        // Gate routed to reserve-funded buy, not the picker. The subsequent
        // session.buy network call is out of scope for this unit test —
        // here we only assert the gate decision.
        #expect(viewModel.pendingOperation == nil)
    }

    @Test(
        "Balance below the entered amount opens the funding picker",
        arguments: [
            (usdfQuarks: UInt64(0),         enteredAmount: "1"),
            (usdfQuarks: UInt64(5_000_000), enteredAmount: "20"),
        ]
    )
    func insufficientBalance_opensPicker(usdfQuarks: UInt64, enteredAmount: String) async throws {
        let container = try await Self.makeContainer(usdfQuarks: usdfQuarks)
        let viewModel = Self.makeViewModel(container: container)
        let router = AppRouter()
        router.present(.balance)

        viewModel.enteredAmount = enteredAmount
        await viewModel.amountEnteredAction(router: router)

        let operation = try #require(viewModel.pendingOperation)
        #expect(operation.displayAmount.nativeAmount.value > 0)
        // No push fired — picker is a local sheet, not a stack destination.
        #expect(router[.balance].count == 0)
    }

    @Test("Pinned amount is carried into the PaymentOperation buy payload")
    func pinPropagation() async throws {
        let container = try await Self.makeContainer(usdfQuarks: 0)
        let viewModel = Self.makeViewModel(container: container)
        let router = AppRouter()
        router.present(.balance)

        viewModel.enteredAmount = "10"
        await viewModel.amountEnteredAction(router: router)

        let operation = try #require(viewModel.pendingOperation)
        guard case .buy(let payload) = operation else {
            Issue.record("Expected .buy operation, got \(operation)")
            return
        }
        // Native USD amount round-trips through the pin into the payload.
        #expect(payload.amount.nativeAmount.value == 10)
        #expect(payload.amount.nativeAmount.currency == .usd)
    }

    @Test("Empty entered amount does nothing on submit")
    func emptyAmount_noop() async throws {
        let container = try await Self.makeContainer(usdfQuarks: 50_000_000)
        let viewModel = Self.makeViewModel(container: container)
        let router = AppRouter()
        router.present(.balance)

        viewModel.enteredAmount = ""
        await viewModel.amountEnteredAction(router: router)

        #expect(viewModel.pendingOperation == nil)
        #expect(router[.balance].count == 0)
        #expect(viewModel.dialogItem == nil)
        // Loading flicker on an empty submit would be a regression.
        #expect(viewModel.actionButtonState == .normal)
    }
}
