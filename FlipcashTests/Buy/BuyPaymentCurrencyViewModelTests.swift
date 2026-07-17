//
//  BuyPaymentCurrencyViewModelTests.swift
//  FlipcashTests
//

import Foundation
import Testing
@testable import FlipcashCore
@testable import Flipcash

@Suite("BuyPaymentCurrencyViewModel")
@MainActor
struct BuyPaymentCurrencyViewModelTests {

    private static let jeffySupply: UInt64 = 50_000 * 10_000_000_000
    private static let jeffyQuarks: UInt64 = 2_000 * 10_000_000_000 // ≈ $20 of curve value

    private static func makeContainer(
        holdings: [SessionContainer.Holding],
        currency: CurrencyCode = .usd,
        fx: Double = 1.0
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
        entered: Decimal,
        currency: CurrencyCode = .usd,
        container: SessionContainer
    ) -> BuyPaymentCurrencyViewModel {
        BuyPaymentCurrencyViewModel(
            targetMint: targetMint,
            targetName: "Moony",
            entered: FiatAmount(value: entered, currency: currency),
            session: container.session,
            ratesController: container.ratesController
        )
    }

    // MARK: - Row membership

    @Test("The target currency never appears in the payment list")
    func targetRow_removed() async throws {
        let container = try await Self.makeContainer(holdings: [
            .init(mint: .usdf, quarks: 30_000_000),
            .init(mint: .makeLaunchpad(address: .jeffy, supplyFromBonding: Self.jeffySupply), quarks: Self.jeffyQuarks),
        ])
        let viewModel = Self.makeViewModel(targetMint: .jeffy, entered: 1, container: container)

        #expect(viewModel.rows.allSatisfy { $0.stored.mint != .jeffy })
        #expect(viewModel.rows.contains { $0.stored.mint == .usdf })
    }

    @Test("An underfunded balance stays listed and tappable")
    func underfunded_staysListed() async throws {
        let container = try await Self.makeContainer(holdings: [
            .init(mint: .usdf, quarks: 30_000_000),
            .init(mint: .makeLaunchpad(address: .jeffy, supplyFromBonding: Self.jeffySupply), quarks: Self.jeffyQuarks),
        ])

        let rate = container.ratesController.rateForBalanceCurrency()
        let jeffyDisplayed = try #require(container.session.balance(for: .jeffy))
            .computeExchangedValue(with: rate)
            .nativeAmount.value
            .rounded(to: CurrencyCode.usd.maximumFractionDigits)

        // Entered well above the balance: the row must remain selectable so
        // the confirmation's Buy can offer Buy Maximum Amount.
        let overBalance = Self.makeViewModel(entered: jeffyDisplayed + 5, container: container)
        #expect(overBalance.rows.contains { $0.stored.mint == .jeffy })
    }

    @Test("A zero-value USDF balance is not offered as a payment source")
    func zeroValueUSDF_removed() async throws {
        let container = try await Self.makeContainer(holdings: [
            .init(mint: .usdf, quarks: 0),
            .init(mint: .makeLaunchpad(address: .jeffy, supplyFromBonding: Self.jeffySupply), quarks: Self.jeffyQuarks),
        ])
        let viewModel = Self.makeViewModel(entered: 1, container: container)

        // The jeffy anchor keeps this from passing vacuously on an empty list.
        #expect(viewModel.rows.contains { $0.stored.mint == .jeffy })
        #expect(viewModel.rows.allSatisfy { $0.stored.mint != .usdf })
    }

    @Test("Selecting a funded row pins its state and pushes the confirmation")
    func select_success_pushesConfirmation() async throws {
        let container = try await Self.makeContainer(holdings: [
            .init(mint: .usdf, quarks: 30_000_000),
        ])
        let viewModel = Self.makeViewModel(entered: 10, container: container)
        let router = AppRouter()
        router.present(.balance)
        router.presentNested(.buy(.usdcAuthority))

        let usdfRow = try #require(viewModel.rows.first { $0.stored.mint == .usdf })
        await viewModel.select(usdfRow, router: router)

        #expect(router[.buy].count == 1)
        #expect(viewModel.dialogItem == nil)
    }

    // MARK: - Payment compute

    @Test("USDF payment computes a balance-capped amount with no fee")
    func usdfCompute_capped() async throws {
        let container = try await Self.makeContainer(holdings: [
            .init(mint: .usdf, quarks: 30_000_000),
        ])
        let viewModel = Self.makeViewModel(entered: 10, container: container)
        let usdfBalance = try #require(container.session.balance(for: .usdf))
        let pin = try #require(await container.ratesController.currentPinnedState(for: .usd, mint: .usdf))

        let amount = try #require(viewModel.computePaymentAmount(for: usdfBalance, pin: pin))

        #expect(amount.onChainAmount.quarks == 10_000_000)
        #expect(amount.mint == .usdf)
    }

    @Test("USDF entered above the displayed balance is deliberately uncapped so the gate can offer Buy Maximum")
    func usdfCompute_aboveDisplayedBalance_uncapped() async throws {
        let container = try await Self.makeContainer(holdings: [
            .init(mint: .usdf, quarks: 630_000), // $0.63
        ])
        let viewModel = Self.makeViewModel(entered: Decimal(string: "0.74")!, container: container)
        let usdfBalance = try #require(container.session.balance(for: .usdf))
        let pin = try #require(await container.ratesController.currentPinnedState(for: .usd, mint: .usdf))

        let amount = try #require(viewModel.computePaymentAmount(for: usdfBalance, pin: pin))

        // The summary must show the true entered amount, not a silently
        // shrunken one — the confirmation's gate then surfaces the sheet.
        #expect(amount.onChainAmount.quarks == 740_000)
        #expect(amount.onChainAmount.quarks > usdfBalance.quarks)
    }

    /// Regression port (deposit 1.00 CAD, buy 1.00 CAD): the USDF compute must
    /// cap the quarks to the balance so FX display rounding can't overshoot
    /// the spendable reserves. Previously covered by
    /// `BuyAmountViewModelTests.maxBuy_submissionCappedToBalance`.
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
        let viewModel = Self.makeViewModel(entered: 1, currency: .cad, container: container)
        let usdfBalance = try #require(container.session.balance(for: .usdf))
        let pin = try #require(await container.ratesController.currentPinnedState(for: .cad, mint: .usdf))

        let amount = try #require(viewModel.computePaymentAmount(for: usdfBalance, pin: pin))

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

        let viewModel = Self.makeViewModel(entered: jeffyDisplayed, container: container)
        let pin = try #require(await container.ratesController.currentPinnedState(for: .usd, mint: .jeffy))

        let amount = try #require(viewModel.computePaymentAmount(for: jeffyBalance, pin: pin))

        // Entering the full displayed balance must overshoot it by the fee —
        // that overshoot is what drives the insufficient-after-fees sheet.
        #expect(amount.onChainAmount.quarks > jeffyBalance.quarks)
        #expect(amount.mint == .jeffy)
    }

    @Test("A pin without reserve supply fails the token compute")
    func missingSupply_nilCompute() async throws {
        let container = try await Self.makeContainer(holdings: [
            .init(mint: .makeLaunchpad(address: .jeffy, supplyFromBonding: Self.jeffySupply), quarks: Self.jeffyQuarks),
        ])
        let viewModel = Self.makeViewModel(entered: 1, container: container)
        let jeffyBalance = try #require(container.session.balance(for: .jeffy))

        let rateOnly = VerifiedState.fresh(bonded: false)

        #expect(viewModel.computePaymentAmount(for: jeffyBalance, pin: rateOnly) == nil)
    }
}
