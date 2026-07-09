//
//  BuyAmountViewModelTests.swift
//  FlipcashTests
//

import Foundation
import Testing
@testable import FlipcashCore
@testable import Flipcash

@Suite("BuyAmountViewModel — USDF gate")
@MainActor
struct BuyAmountViewModelTests {

    // MARK: - amountEnteredAction gating

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
    /// USDF gate. Without these, `prepareSubmission` returns nil and the flow
    /// short-circuits at the "Rate Unavailable" dialog.
    ///
    /// `currency`/`fx` select the balance currency — pass a non-USD rate to
    /// reproduce FX display rounding (see the CAD regression below).
    private static func makeContainer(
        usdfQuarks: UInt64,
        currency: CurrencyCode = .usd,
        fx: Double = 1.0
    ) async throws -> SessionContainer {
        let holdings: [SessionContainer.Holding] = usdfQuarks == 0
            ? []
            : [.init(mint: MintMetadata.usdf, quarks: usdfQuarks)]

        var sendLimits: [CurrencyCode: SendLimit] = [.usd: testSendLimit]
        sendLimits[currency] = SendLimit(
            nextTransaction: FiatAmount(value: 1000, currency: currency),
            maxPerTransaction: FiatAmount(value: 1000, currency: currency),
            maxPerDay: FiatAmount(value: 1000, currency: currency)
        )

        let container = try SessionContainer.makeTest(
            holdings: holdings,
            limits: Limits(
                sinceDate: .now,
                fetchDate: .now,
                sendLimits: sendLimits
            )
        )

        // Force the balance currency. Without this the rates controller reads
        // `LocalDefaults.balanceCurrency`, which can be polluted by other
        // suites that called `configureTestRates(balanceCurrency: .cad, ...)`.
        container.ratesController.configureTestRates(
            balanceCurrency: currency,
            rates: [Rate(fx: Decimal(fx), currency: currency)]
        )

        // Pin a fresh verified state so prepareSubmission() succeeds.
        await container.ratesController.verifiedProtoService.saveRates([
            .freshRate(currencyCode: currency.rawValue.uppercased(), rate: fx)
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

    @Test(
        "Insufficient USDF surfaces the No Balance dialog instead of buying",
        arguments: [
            (usdfQuarks: UInt64(0),         enteredAmount: "1"),
            (usdfQuarks: UInt64(5_000_000), enteredAmount: "20"),
        ]
    )
    func insufficientBalance_showsNoBalanceDialog(usdfQuarks: UInt64, enteredAmount: String) async throws {
        let container = try await Self.makeContainer(usdfQuarks: usdfQuarks)
        let viewModel = Self.makeViewModel(container: container)
        let router = AppRouter()
        router.present(.balance)

        viewModel.enteredAmount = enteredAmount
        await viewModel.amountEnteredAction(router: router)

        // The standard "No Balance Yet" dialog is surfaced; its "Add Money"
        // action (not fired here) is what presents the deposit picker, so the
        // sheet isn't on the stack yet.
        #expect(container.session.dialogItem?.title == "No Balance Yet")
        #expect(!router.presentedSheets.contains(.addMoney(.buyCurrency)))
    }

    @Test("Empty entered amount does nothing on submit")
    func emptyAmount_noop() async throws {
        let container = try await Self.makeContainer(usdfQuarks: 50_000_000)
        let viewModel = Self.makeViewModel(container: container)
        let router = AppRouter()
        router.present(.balance)

        viewModel.enteredAmount = ""
        await viewModel.amountEnteredAction(router: router)

        #expect(!router.presentedSheets.contains(.addMoney(.buyCurrency)))
        #expect(viewModel.dialogItem == nil)
        // Loading flicker on an empty submit would be a regression.
        #expect(viewModel.actionButtonState == .normal)
    }

    // MARK: - FX rounding regression (deposit 1 CAD, buy 1 CAD)

    /// Regression: a CAD user deposits USDF that *displays* as 1.00 CAD, then
    /// buys 1.00 CAD — the gate must treat that as sufficient. The old raw
    /// `Decimal` compare (`usdfBalance.value >= amount.usdfValue.value`)
    /// rejected it, because 1.00 CAD converts to fractionally more USD than
    /// the truncated 6-decimal balance. The gate must follow
    /// `Session.hasSufficientFunds` (quarks compare + half-denomination
    /// max-send tolerance) like every other spend flow.
    ///
    /// Two balances straddle the quark rounding boundary at fx 1.37/1.36:
    /// one where the entered amount's quarks equal the balance exactly, one
    /// where they land 1 quark over and only the tolerance saves the buy.
    @Test(
        "Displayed-balance max buy in a non-USD currency passes the gate",
        arguments: [
            (usdfQuarks: UInt64(729_927), fx: 1.37),
            (usdfQuarks: UInt64(735_293), fx: 1.36),
        ]
    )
    func maxBuy_nonUSDCurrency_passesGate(usdfQuarks: UInt64, fx: Double) async throws {
        let container = try await Self.makeContainer(usdfQuarks: usdfQuarks, currency: .cad, fx: fx)
        let viewModel = Self.makeViewModel(container: container)
        let router = AppRouter()
        router.present(.balance)

        viewModel.enteredAmount = "1"
        await viewModel.amountEnteredAction(router: router)

        // The gate must NOT route a covered max-buy to Add Money.
        #expect(container.session.dialogItem == nil)
    }

    @Test("Submission quarks are capped to the USDF balance for a max buy")
    func maxBuy_submissionCappedToBalance() async throws {
        let usdfQuarks: UInt64 = 729_927 // displays as 1.00 CAD at 1.37
        let container = try await Self.makeContainer(usdfQuarks: usdfQuarks, currency: .cad, fx: 1.37)
        let viewModel = Self.makeViewModel(container: container)

        viewModel.enteredAmount = "1"
        let submission = await viewModel.prepareSubmission()

        let quarks = try #require(submission).amount.onChainAmount.quarks
        #expect(quarks == usdfQuarks, "A max buy must spend exactly the balance, not overshoot it")
    }
}
