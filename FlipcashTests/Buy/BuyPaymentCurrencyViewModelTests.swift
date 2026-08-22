//
//  BuyPaymentCurrencyViewModelTests.swift
//  FlipcashTests
//
//  Payment-source selection and gross-debit compute now live inline on
//  `BuyAmountViewModel` (the standalone `BuyPaymentCurrencyViewModel` was
//  removed). These cover the row membership and `computePaymentAmount` behavior
//  that step used to own. The push-on-select paths are covered by
//  `BuyAmountViewModelTests`.
//

import Foundation
import Testing
@testable import FlipcashCore
@testable import Flipcash

@Suite("BuyAmountViewModel — payment source & compute")
@MainActor
struct BuyPaymentCurrencyViewModelTests {

    private static let jeffySupply: UInt64 = 50_000 * 10_000_000_000
    private static let jeffyQuarks: UInt64 = 2_000 * 10_000_000_000 // ≈ $20 of curve value
    /// A freshly launched currency: the creator holds the entire ≈ $10 curve.
    private static let soleHolderSupply: UInt64 = 9_996_054_730_448

    private static func makeContainer(
        holdings: [SessionContainer.Holding],
        currency: CurrencyCode = .usd,
        fx: Double = 1.0,
        jeffySupply: UInt64 = jeffySupply
    ) async throws -> SessionContainer {
        let container = try SessionContainer.makeTest(holdings: holdings)

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

    private static func makeViewModel(
        targetMint: PublicKey = .usdcAuthority,
        currency: CurrencyCode = .usd,
        container: SessionContainer
    ) -> BuyAmountViewModel {
        BuyAmountViewModel(
            mint: targetMint,
            currencyName: "Moony",
            session: container.session,
            ratesController: container.ratesController
        )
    }

    // MARK: - Payment source membership

    @Test("The target currency never appears in the payment list")
    func targetRow_removed() async throws {
        let container = try await Self.makeContainer(holdings: [
            .init(mint: .usdf, quarks: 30_000_000),
            .init(mint: .makeLaunchpad(address: .jeffy, supplyFromBonding: Self.jeffySupply), quarks: Self.jeffyQuarks),
        ])
        let viewModel = Self.makeViewModel(targetMint: .jeffy, container: container)

        #expect(viewModel.paymentOptions.allSatisfy { $0.stored.mint != .jeffy })
        #expect(viewModel.paymentOptions.contains { $0.stored.mint == .usdf })
    }

    @Test("An underfunded balance stays listed and selectable")
    func underfunded_staysListed() async throws {
        // Even a balance worth far less than any plausible entry stays in the
        // list — selecting it re-caps the entry, and the amount screen trims
        // anything the fee can't cover.
        let container = try await Self.makeContainer(holdings: [
            .init(mint: .usdf, quarks: 30_000_000),
            .init(mint: .makeLaunchpad(address: .jeffy, supplyFromBonding: Self.jeffySupply), quarks: Self.jeffyQuarks),
        ])
        let viewModel = Self.makeViewModel(container: container)

        #expect(viewModel.paymentOptions.contains { $0.stored.mint == .jeffy })
    }

    @Test("A zero-value USDF balance is not offered as a payment source")
    func zeroValueUSDF_removed() async throws {
        let container = try await Self.makeContainer(holdings: [
            .init(mint: .usdf, quarks: 0),
            .init(mint: .makeLaunchpad(address: .jeffy, supplyFromBonding: Self.jeffySupply), quarks: Self.jeffyQuarks),
        ])
        let viewModel = Self.makeViewModel(container: container)

        // The jeffy anchor keeps this from passing vacuously on an empty list.
        #expect(viewModel.paymentOptions.contains { $0.stored.mint == .jeffy })
        #expect(viewModel.paymentOptions.allSatisfy { $0.stored.mint != .usdf })
    }

    // MARK: - Payment compute

    @Test("USDF payment computes a balance-capped amount with no fee")
    func usdfCompute_capped() async throws {
        let container = try await Self.makeContainer(holdings: [
            .init(mint: .usdf, quarks: 30_000_000),
        ])
        let viewModel = Self.makeViewModel(container: container)
        let usdfBalance = try #require(container.session.balance(for: .usdf))
        let pin = try #require(await container.ratesController.currentPinnedState(for: .usd, mint: .usdf))

        let amount = try #require(viewModel.computePaymentAmount(for: usdfBalance, entered: FiatAmount(value: 10, currency: .usd), pin: pin))

        #expect(amount.onChainAmount.quarks == 10_000_000)
        #expect(amount.mint == .usdf)
    }

    @Test("USDF entered above the displayed balance is deliberately uncapped so the gate can surface the shortfall")
    func usdfCompute_aboveDisplayedBalance_uncapped() async throws {
        let container = try await Self.makeContainer(holdings: [
            .init(mint: .usdf, quarks: 630_000), // $0.63
        ])
        let viewModel = Self.makeViewModel(container: container)
        let usdfBalance = try #require(container.session.balance(for: .usdf))
        let pin = try #require(await container.ratesController.currentPinnedState(for: .usd, mint: .usdf))

        let amount = try #require(viewModel.computePaymentAmount(for: usdfBalance, entered: FiatAmount(value: Decimal(string: "0.74")!, currency: .usd), pin: pin))

        // The summary must show the true entered amount, not a silently
        // shrunken one — the confirmation's gate then surfaces the sheet. (The
        // entry itself is trimmed upstream by `correctEntryToAffordable`.)
        #expect(amount.onChainAmount.quarks == 740_000)
        #expect(amount.onChainAmount.quarks > usdfBalance.quarks)
    }

    /// Regression port (deposit 1.00 CAD, buy 1.00 CAD): the USDF compute must
    /// cap the quarks to the balance so FX display rounding can't overshoot
    /// the spendable reserves.
    @Test(
        "Displayed-balance max buy in a non-USD currency stays within the balance",
        arguments: [
            (usdfQuarks: UInt64(729_927), fx: 1.37),
            (usdfQuarks: UInt64(735_293), fx: 1.36),
        ]
    )
    func usdfCompute_nonUSDMaxBuy_cappedToBalance(usdfQuarks: UInt64, fx: Double) async throws {
        let container = try await Self.makeContainer(
            holdings: [.init(mint: .usdf, quarks: usdfQuarks)],
            currency: .cad,
            fx: fx
        )
        let viewModel = Self.makeViewModel(currency: .cad, container: container)
        let usdfBalance = try #require(container.session.balance(for: .usdf))
        let pin = try #require(await container.ratesController.currentPinnedState(for: .cad, mint: .usdf))

        let amount = try #require(viewModel.computePaymentAmount(for: usdfBalance, entered: FiatAmount(value: 1, currency: .cad), pin: pin))

        #expect(amount.onChainAmount.quarks == usdfQuarks, "A max buy must spend exactly the balance, not overshoot or shrink")
    }

    @Test("Token payment grosses up by the pool fee and is deliberately uncapped")
    func tokenCompute_grossedUp() async throws {
        let container = try await Self.makeContainer(holdings: [
            .init(mint: .usdf, quarks: 30_000_000),
            .init(mint: .makeLaunchpad(address: .jeffy, supplyFromBonding: Self.jeffySupply), quarks: Self.jeffyQuarks),
        ])

        let rate = container.ratesController.rateForBalanceCurrency()
        let jeffyBalance = try #require(container.session.balance(for: .jeffy))
        let jeffyDisplayed = jeffyBalance
            .computeExchangedValue(with: rate)
            .nativeAmount.value
            .rounded(to: CurrencyCode.usd.maximumFractionDigits)

        let viewModel = Self.makeViewModel(container: container)
        let pin = try #require(await container.ratesController.currentPinnedState(for: .usd, mint: .jeffy))

        let amount = try #require(viewModel.computePaymentAmount(for: jeffyBalance, entered: FiatAmount(value: jeffyDisplayed, currency: .usd), pin: pin))

        // Entering the full displayed balance must overshoot it by the fee —
        // that overshoot is exactly what `correctEntryToAffordable` trims away
        // before this compute ever runs in production.
        #expect(amount.onChainAmount.quarks > jeffyBalance.quarks)
        #expect(amount.mint == .jeffy)
    }

    /// Regression (2026-07-20 log): paying with a freshly created currency the
    /// user wholly owns. The entered value exceeds the curve's entire TVL, so
    /// the uncapped compute used to fail and dead-ended in a "Rate Unavailable"
    /// dialog the user could never escape.
    @Test("Token payment beyond the curve TVL clamps instead of failing")
    func tokenCompute_overTVL_returnsClampedQuote() async throws {
        let container = try await Self.makeContainer(
            holdings: [
                .init(mint: .makeLaunchpad(address: .jeffy, supplyFromBonding: Self.soleHolderSupply), quarks: Self.soleHolderSupply),
            ],
            currency: .cad,
            fx: 1.37,
            jeffySupply: Self.soleHolderSupply
        )
        let viewModel = Self.makeViewModel(currency: .cad, container: container)
        let jeffyBalance = try #require(container.session.balance(for: .jeffy))
        let pin = try #require(await container.ratesController.currentPinnedState(for: .cad, mint: .jeffy))

        let amount = try #require(viewModel.computePaymentAmount(for: jeffyBalance, entered: FiatAmount(value: 50, currency: .cad), pin: pin))

        // The maximum extractable quote: the whole curve, i.e. the whole balance.
        #expect(amount.onChainAmount.quarks == jeffyBalance.quarks)
        #expect(amount.mint == .jeffy)
    }

    @Test("A pin without reserve supply fails the token compute")
    func missingSupply_nilCompute() async throws {
        let container = try await Self.makeContainer(holdings: [
            .init(mint: .makeLaunchpad(address: .jeffy, supplyFromBonding: Self.jeffySupply), quarks: Self.jeffyQuarks),
        ])
        let viewModel = Self.makeViewModel(container: container)
        let jeffyBalance = try #require(container.session.balance(for: .jeffy))

        let rateOnly = VerifiedState.fresh(bonded: false)

        #expect(viewModel.computePaymentAmount(for: jeffyBalance, entered: FiatAmount(value: 1, currency: .usd), pin: rateOnly) == nil)
    }
}
