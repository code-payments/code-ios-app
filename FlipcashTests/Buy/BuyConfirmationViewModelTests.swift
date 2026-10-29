//
//  BuyConfirmationViewModelTests.swift
//  FlipcashTests
//

import Foundation
import Testing
@testable import FlipcashCore
import FlipcashStore
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

    private static func makeViewModel(
        payment: StoredBalance,
        paymentAmount: ExchangedFiat,
        pin: VerifiedState
    ) -> BuyConfirmationViewModel {
        BuyConfirmationViewModel(
            targetMint: .usdcAuthority,
            targetName: "Moony",
            payment: payment,
            paymentAmount: paymentAmount,
            pinnedState: pin
        )
    }

    // MARK: - Boundary gate

    /// The amount screen trims an entry to what the fee leaves, so an amount
    /// this short only reaches here when the balance moved under the quote.
    /// The gate must still catch it rather than submit.
    @Test("An amount the balance can no longer cover surfaces the insufficient sheet, not a submit")
    func boundary_showsSheet() async throws {
        let container = try await Self.makeContainer(holdings: [
            SessionContainer.Holding(mint: .makeLaunchpad(address: .jeffy, supplyFromBonding: Self.jeffySupply), quarks: Self.jeffyQuarks),
        ])
        let rate = container.ratesController.rateForBalanceCurrency()
        let jeffyBalance = try #require(container.session.balance(for: .jeffy))
        let displayed = jeffyBalance.computeExchangedValue(with: rate)
            .nativeAmount.value.rounded(to: CurrencyCode.usd.maximumFractionDigits)
        let pin = try #require(await container.ratesController.currentPinnedState(for: .usd, mint: .jeffy))
        let paymentAmount = try Self.makePaymentAmount(entered: displayed, balance: jeffyBalance, pin: pin, container: container)

        let viewModel = Self.makeViewModel(payment: jeffyBalance, paymentAmount: paymentAmount, pin: pin)
        let router = AppRouter()
        router.present(.give)
        router.presentNested(.buy(.usdcAuthority))

        await viewModel.buyAction(session: container.session, router: router)

        #expect(viewModel.dialogItem?.title == "Insufficient Balance")
        #expect(viewModel.actionButtonState == .normal)
        #expect(router[.buy].isEmpty, "A short buy must never reach the processing push")
    }

    // MARK: - USDF variant

    @Test("USDF payments are fee-free: the debit equals the entered amount and no fee row shows")
    func usdfVariant_feeFree() async throws {
        let container = try await Self.makeContainer(holdings: [
            SessionContainer.Holding(mint: .usdf, quarks: 30_000_000),
        ])
        let usdfBalance = try #require(container.session.balance(for: .usdf))
        let pin = try #require(await container.ratesController.currentPinnedState(for: .usd, mint: .usdf))
        let paymentAmount = try Self.makePaymentAmount(entered: 10, balance: usdfBalance, pin: pin, container: container)

        let viewModel = Self.makeViewModel(payment: usdfBalance, paymentAmount: paymentAmount, pin: pin)

        #expect(viewModel.isUSDF)
        #expect(viewModel.feeBps == LaunchpadFee.dollarsFeeBps)
        #expect(viewModel.feeBps == 0)
        #expect(!viewModel.hasFee)
        // The fee is zero quarks, which keeps the swap on the no-fee
        // `TransferForSwap` rather than `TransferForSwapWithFee`.
        #expect(viewModel.fee.onChainAmount.quarks == 0)
        #expect(viewModel.amountToBuy == viewModel.paymentAmount)
        #expect(viewModel.grossDebit == paymentAmount)
    }

    @Test("A token payment still charges its pool's sell fee and shows the fee row")
    func tokenVariant_chargesPoolFee() async throws {
        let container = try await Self.makeContainer(holdings: [
            SessionContainer.Holding(mint: .makeLaunchpad(address: .jeffy, supplyFromBonding: Self.jeffySupply), quarks: Self.jeffyQuarks),
        ])
        let jeffyBalance = try #require(container.session.balance(for: .jeffy))
        let pin = try #require(await container.ratesController.currentPinnedState(for: .usd, mint: .jeffy))
        let paymentAmount = try Self.makePaymentAmount(entered: 1, balance: jeffyBalance, pin: pin, container: container)

        let viewModel = Self.makeViewModel(payment: jeffyBalance, paymentAmount: paymentAmount, pin: pin)

        #expect(!viewModel.isUSDF)
        #expect(viewModel.feeBps == LaunchpadFee.poolSellFeeBps(jeffyBalance.sellFeeBps))
        #expect(viewModel.feeBps > 0)
        #expect(viewModel.hasFee)
    }

    @Test("An underfunded USDF payment surfaces the insufficient sheet")
    func usdfUnderfunded_showsSheet() async throws {
        let container = try await Self.makeContainer(holdings: [
            SessionContainer.Holding(mint: .usdf, quarks: 630_000), // $0.63
        ])
        let usdfBalance = try #require(container.session.balance(for: .usdf))
        let pin = try #require(await container.ratesController.currentPinnedState(for: .usd, mint: .usdf))
        let paymentAmount = try Self.makePaymentAmount(entered: Decimal(string: "0.74")!, balance: usdfBalance, pin: pin, container: container)

        let viewModel = Self.makeViewModel(payment: usdfBalance, paymentAmount: paymentAmount, pin: pin)
        let router = AppRouter()
        router.present(.give)
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
            SessionContainer.Holding(mint: .makeLaunchpad(address: .jeffy, supplyFromBonding: Self.jeffySupply), quarks: Self.jeffyQuarks),
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
        router.present(.give)
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
            SessionContainer.Holding(mint: .usdf, quarks: 30_000_000),
        ])
        let usdfBalance = try #require(container.session.balance(for: .usdf))

        let viewModel = Self.makeViewModel(
            payment: usdfBalance,
            paymentAmount: ExchangedFiat(nativeAmount: FiatAmount.usd(1), rate: .oneToOne),
            pin: .stale()
        )

        #expect(viewModel.canPerformAction == false)
    }

    // MARK: - Inline completion

    private final class DismissCounter { var count = 0 }

    private func inlineContext(
        poll: @escaping () throws -> SwapMetadata
    ) async throws -> (BuyConfirmationViewModel, SessionContainer, AppRouter, DismissCounter) {
        let container = try await Self.makeContainer(holdings: [
            SessionContainer.Holding(mint: .usdf, quarks: 30_000_000),
        ])
        let usdfBalance = try #require(container.session.balance(for: .usdf))
        let pin = try #require(await container.ratesController.currentPinnedState(for: .usd, mint: .usdf))
        let paymentAmount = try Self.makePaymentAmount(entered: 5, balance: usdfBalance, pin: pin, container: container)
        let viewModel = Self.makeViewModel(payment: usdfBalance, paymentAmount: paymentAmount, pin: pin)
        viewModel.swapPoller = { _ in { _, _ in try poll() } }
        viewModel.successHold = .zero
        let router = AppRouter()
        router.present(.give)
        router.presentNested(.buy(.usdcAuthority))
        return (viewModel, container, router, DismissCounter())
    }

    @Test("Inline: fast success skips processing and dismisses once")
    func inline_fastSuccess() async throws {
        let (vm, container, router, dismissed) = try await inlineContext { .makeTest(state: .finalized) }
        await vm.completeInline(swapId: .generate(), swapType: .buyWithReserves, session: container.session, router: router) { dismissed.count += 1 }
        #expect(dismissed.count == 1)
        #expect(vm.actionButtonState == .success)
        #expect(router[.buy].isEmpty)
        #expect(container.session.transactionNotificationPrompt.pending)
    }

    @Test("Inline: pending after the window falls back to the processing screen")
    func inline_pendingFallsBack() async throws {
        let (vm, container, router, dismissed) = try await inlineContext { .makeTest(state: .funding) }
        await vm.completeInline(swapId: .generate(), swapType: .buyWithReserves, session: container.session, router: router) { dismissed.count += 1 }
        #expect(dismissed.count == 0)
        #expect(vm.actionButtonState == .normal)
        #expect(router[.buy].count == 1)
        #expect(!container.session.transactionNotificationPrompt.pending)
    }

    @Test("Inline: terminal failure stays, resets the button, and shows an error")
    func inline_failureStays() async throws {
        let (vm, container, router, dismissed) = try await inlineContext { .makeTest(state: .failed) }
        await vm.completeInline(swapId: .generate(), swapType: .buyWithReserves, session: container.session, router: router) { dismissed.count += 1 }
        #expect(dismissed.count == 0)
        #expect(vm.actionButtonState == .normal)
        #expect(vm.dialogItem != nil)
        #expect(router[.buy].isEmpty)
    }
}
