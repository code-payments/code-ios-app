//
//  BuyConfirmationViewModelTests.swift
//  FlipcashTests
//

import Foundation
import Testing
@testable import FlipcashCore
@testable import Flipcash

@Suite("BuyConfirmationViewModel")
@MainActor
struct BuyConfirmationViewModelTests {

    private static let jeffySupply: UInt64 = 50_000 * 10_000_000_000
    private static let jeffyQuarks: UInt64 = 2_000 * 10_000_000_000 // ≈ $20 of curve value

    private static func makeContainer(
        holdings: [SessionContainer.Holding],
        currency: CurrencyCode = .usd,
        fx: Double = 1.0,
        maxPerDay: Decimal = 1_000
    ) async throws -> SessionContainer {
        let container = try SessionContainer.makeTest(
            holdings: holdings,
            limits: Limits(
                sinceDate: .now,
                fetchDate: .now,
                sendLimits: [currency: SendLimit(
                    nextTransaction: FiatAmount(value: 1000, currency: currency),
                    maxPerTransaction: FiatAmount(value: 1000, currency: currency),
                    maxPerDay: FiatAmount(value: maxPerDay, currency: currency)
                )]
            )
        )

        container.ratesController.configureTestRates(
            balanceCurrency: currency,
            rates: [Rate(fx: Decimal(fx), currency: currency)]
        )

        await container.ratesController.verifiedProtoService.saveRates([
            .freshRate(currencyCode: currency.rawValue.uppercased(), rate: fx)
        ])
        await container.ratesController.verifiedProtoService.saveReserveStates([
            .freshReserve(mint: .jeffy, supplyFromBonding: jeffySupply)
        ])

        return container
    }

    /// Runs the amount screen's real compute so the confirmation sees the same
    /// gross amount production would.
    private static func makePaymentAmount(
        entered: Decimal,
        balance: StoredBalance,
        pin: VerifiedState,
        container: SessionContainer,
        currency: CurrencyCode = .usd
    ) throws -> ExchangedFiat {
        let amountViewModel = BuyAmountViewModel(
            mint: .usdcAuthority,
            currencyName: "Moony",
            session: container.session,
            ratesController: container.ratesController
        )
        return try #require(amountViewModel.computePaymentAmount(
            for: balance,
            entered: FiatAmount(value: entered, currency: currency),
            pin: pin
        ))
    }

    /// `collectsUSDFFee` is pinned rather than left to `BetaFlags.shared`, whose
    /// persisted value varies by simulator — every case here states the fee
    /// branch it means to exercise.
    private static func makeViewModel(
        payment: StoredBalance,
        paymentAmount: ExchangedFiat,
        pin: VerifiedState,
        collectsUSDFFee: Bool = false
    ) -> BuyConfirmationViewModel {
        BuyConfirmationViewModel(
            targetMint: .usdcAuthority,
            targetName: "Moony",
            payment: payment,
            paymentAmount: paymentAmount,
            pinnedState: pin,
            collectsUSDFFee: collectsUSDFFee
        )
    }

    // MARK: - Boundary gate

    /// The amount screen trims an entry to what the fee leaves, so an amount
    /// this short only reaches here when the balance moved under the quote.
    /// The gate must still catch it rather than submit.
    @Test("An amount the balance can no longer cover surfaces the insufficient sheet, not a submit")
    func boundary_showsSheet() async throws {
        let container = try await Self.makeContainer(holdings: [
            .init(mint: .makeLaunchpad(address: .jeffy, supplyFromBonding: Self.jeffySupply), quarks: Self.jeffyQuarks),
        ])
        let rate = container.ratesController.rateForBalanceCurrency()
        let jeffyBalance = try #require(container.session.balance(for: .jeffy))
        let displayed = jeffyBalance.computeExchangedValue(with: rate)
            .nativeAmount.value.rounded(to: CurrencyCode.usd.maximumFractionDigits)
        let pin = try #require(await container.ratesController.currentPinnedState(for: .usd, mint: .jeffy))
        let paymentAmount = try Self.makePaymentAmount(entered: displayed, balance: jeffyBalance, pin: pin, container: container)

        let viewModel = Self.makeViewModel(payment: jeffyBalance, paymentAmount: paymentAmount, pin: pin)
        let router = AppRouter()
        router.present(.balance)
        router.presentNested(.buy(.usdcAuthority))

        await viewModel.buyAction(session: container.session, router: router)

        #expect(viewModel.dialogItem?.title == "Insufficient Balance")
        #expect(viewModel.actionButtonState == .normal)
        #expect(router[.buy].isEmpty, "A short buy must never reach the processing push")
    }

    // MARK: - USDF variant

    @Test("Fee-free USDF payments show no fee and amountToBuy equals the payment")
    func usdfVariant_noFee() async throws {
        let container = try await Self.makeContainer(holdings: [
            .init(mint: .usdf, quarks: 30_000_000),
        ])
        let usdfBalance = try #require(container.session.balance(for: .usdf))
        let pin = try #require(await container.ratesController.currentPinnedState(for: .usd, mint: .usdf))
        let paymentAmount = try Self.makePaymentAmount(entered: 10, balance: usdfBalance, pin: pin, container: container)

        let viewModel = Self.makeViewModel(payment: usdfBalance, paymentAmount: paymentAmount, pin: pin)

        #expect(viewModel.isUSDF)
        #expect(!viewModel.chargesFee)
        #expect(viewModel.amountToBuy == viewModel.paymentAmount)
    }

    @Test(
        "An underfunded USDF payment surfaces the insufficient sheet under either fee branch",
        arguments: [false, true]
    )
    func usdfUnderfunded_showsSheet(collectsUSDFFee: Bool) async throws {
        let container = try await Self.makeContainer(holdings: [
            .init(mint: .usdf, quarks: 630_000), // $0.63
        ])
        let usdfBalance = try #require(container.session.balance(for: .usdf))
        let pin = try #require(await container.ratesController.currentPinnedState(for: .usd, mint: .usdf))
        let paymentAmount = try Self.makePaymentAmount(entered: Decimal(string: "0.74")!, balance: usdfBalance, pin: pin, container: container)

        let viewModel = Self.makeViewModel(
            payment: usdfBalance,
            paymentAmount: paymentAmount,
            pin: pin,
            collectsUSDFFee: collectsUSDFFee
        )
        let router = AppRouter()
        router.present(.balance)
        router.presentNested(.buy(.usdcAuthority))

        await viewModel.buyAction(session: container.session, router: router)

        #expect(viewModel.dialogItem?.title == "Insufficient Balance")
        #expect(router[.buy].isEmpty)
        #expect(viewModel.grossDebit.onChainAmount.quarks > usdfBalance.quarks)
    }

    /// Regression: the funds gate must value the balance at the REQUESTED
    /// amount's rate. The confirmation feeds it a pinned-rate amount; with a
    /// drifted live cache the old live-rate compare tripped
    /// `ExchangedFiat.subtracting`'s same-rate precondition and crashed at the
    /// exact boundary this feature is built around.
    @Test("A rate drift between pin and Buy gates as insufficient instead of crashing")
    func rateDrift_boundaryGatesInsufficient() async throws {
        let container = try await Self.makeContainer(holdings: [
            .init(mint: .makeLaunchpad(address: .jeffy, supplyFromBonding: Self.jeffySupply), quarks: Self.jeffyQuarks),
        ], currency: .cad, fx: 1.35)
        let rate = container.ratesController.rateForBalanceCurrency()
        let jeffyBalance = try #require(container.session.balance(for: .jeffy))
        let displayed = jeffyBalance.computeExchangedValue(with: rate)
            .nativeAmount.value.rounded(to: CurrencyCode.cad.maximumFractionDigits)
        let pin = try #require(await container.ratesController.currentPinnedState(for: .cad, mint: .jeffy))
        let paymentAmount = try Self.makePaymentAmount(
            entered: displayed,
            balance: jeffyBalance,
            pin: pin,
            container: container,
            currency: .cad
        )

        // The live cache drifts after the pin was captured.
        container.ratesController.configureTestRates(
            balanceCurrency: .cad,
            rates: [Rate(fx: Decimal(1.37), currency: .cad)]
        )

        let viewModel = Self.makeViewModel(payment: jeffyBalance, paymentAmount: paymentAmount, pin: pin)
        let router = AppRouter()
        router.present(.balance)
        router.presentNested(.buy(.usdcAuthority))

        await viewModel.buyAction(session: container.session, router: router)

        #expect(viewModel.dialogItem?.title == "Insufficient Balance")
        #expect(router[.buy].isEmpty)
    }

    /// Regression port (deposit 1.00 CAD, buy 1.00 CAD): a covered max-buy in
    /// a non-USD currency must clear the canonical funds gate. Asserted
    /// directly against `hasSufficientFunds` — the old "stops at the limit
    /// check" proxy no longer proves it since the limit now runs first.
    /// Previously covered by `BuyAmountViewModelTests.maxBuy_nonUSDCurrency_passesGate`.
    @Test(
        "Displayed-balance max buy in a non-USD currency passes the gate",
        arguments: [
            (usdfQuarks: UInt64(729_927), fx: 1.37),
            (usdfQuarks: UInt64(735_293), fx: 1.36),
        ]
    )
    func maxBuy_nonUSDCurrency_passesGate(usdfQuarks: UInt64, fx: Double) async throws {
        let container = try await Self.makeContainer(
            holdings: [.init(mint: .usdf, quarks: usdfQuarks)],
            currency: .cad,
            fx: fx
        )
        let usdfBalance = try #require(container.session.balance(for: .usdf))
        let pin = try #require(await container.ratesController.currentPinnedState(for: .cad, mint: .usdf))
        let paymentAmount = try Self.makePaymentAmount(
            entered: 1,
            balance: usdfBalance,
            pin: pin,
            container: container,
            currency: .cad
        )

        switch container.session.hasSufficientFunds(for: paymentAmount) {
        case .sufficient:
            break
        case .insufficient:
            Issue.record("A displayed-balance max buy must pass the funds gate")
        }
    }

    @Test("A stale pin disables the Buy button")
    func stalePin_disables() async throws {
        let container = try await Self.makeContainer(holdings: [
            .init(mint: .usdf, quarks: 30_000_000),
        ])
        let usdfBalance = try #require(container.session.balance(for: .usdf))

        let viewModel = Self.makeViewModel(
            payment: usdfBalance,
            paymentAmount: ExchangedFiat(nativeAmount: FiatAmount.usd(1), rate: .oneToOne),
            pin: .stale()
        )

        #expect(viewModel.canPerformAction == false)
    }
}
