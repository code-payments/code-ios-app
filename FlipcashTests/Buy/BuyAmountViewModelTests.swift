//
//  BuyAmountViewModelTests.swift
//  FlipcashTests
//

import Foundation
import Testing
@testable import FlipcashCore
@testable import Flipcash

@Suite("BuyAmountViewModel — balance cap")
@MainActor
struct BuyAmountViewModelTests {

    private static let testSendLimit = SendLimit(
        nextTransaction: FiatAmount(value: 1000, currency: .usd),
        maxPerTransaction: FiatAmount(value: 1000, currency: .usd),
        maxPerDay: FiatAmount(value: 1000, currency: .usd)
    )

    /// Builds a `SessionContainer` with the given holdings and seeds fresh
    /// rates so the cap and pin lookups work.
    private static func makeContainer(
        holdings: [SessionContainer.Holding],
        currency: CurrencyCode = .usd,
        fx: Double = 1.0
    ) async throws -> SessionContainer {
        let container = try SessionContainer.makeTest(
            holdings: holdings,
            limits: Limits(
                sinceDate: .now,
                fetchDate: .now,
                sendLimits: [currency: SendLimit(
                    nextTransaction: FiatAmount(value: 1000, currency: currency),
                    maxPerTransaction: FiatAmount(value: 1000, currency: currency),
                    maxPerDay: FiatAmount(value: 1000, currency: currency)
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

        return container
    }

    private static func makeViewModel(
        mint: PublicKey = .jeffy,
        currencyName: String = "Jeffy",
        container: SessionContainer,
        collectsUSDFFee: Bool = false
    ) -> BuyAmountViewModel {
        BuyAmountViewModel(
            mint: mint,
            currencyName: currencyName,
            session: container.session,
            ratesController: container.ratesController,
            collectsUSDFFee: collectsUSDFFee
        )
    }

    @Test("Cap follows the default Dollars payment source")
    func cap_defaultsToDollars() async throws {
        // Dollars is the default source whenever it's spendable, whatever the
        // other holdings are worth.
        let container = try await Self.makeContainer(holdings: [
            .init(mint: .usdf, quarks: 30_000_000),
            .init(mint: .makeLaunchpad(address: .jeffy), quarks: 10_000_000_000), // 1 token ≈ $0.01
        ])
        let viewModel = Self.makeViewModel(mint: .usdcAuthority, container: container)

        #expect(viewModel.paymentMint == .usdf)
        #expect(viewModel.maxPossibleAmount.nativeAmount.formatted() == "$30.00")
        #expect(!viewModel.isBalanceEmpty)
        #expect(viewModel.actionTitle == "Next")
    }

    @Test("The target currency is excluded from the cap")
    func cap_excludesTarget() async throws {
        // Jeffy is the largest holding but is also the buy target — the cap
        // must fall back to the USDF balance.
        let jeffyQuarks: UInt64 = 2_000 * 10_000_000_000 // ≈ $20 of curve value
        let container = try await Self.makeContainer(holdings: [
            .init(mint: .usdf, quarks: 5_000_000),
            .init(mint: .makeLaunchpad(address: .jeffy), quarks: jeffyQuarks),
        ])
        let viewModel = Self.makeViewModel(mint: .jeffy, container: container)

        #expect(viewModel.maxPossibleAmount.nativeAmount.formatted() == "$5.00")
    }

    @Test("Selecting a launchpad source lifts the cap above the Dollars balance")
    func cap_followsSelectedPaymentSource() async throws {
        let jeffyQuarks: UInt64 = 2_000 * 10_000_000_000 // ≈ $20 of curve value
        let container = try await Self.makeContainer(holdings: [
            .init(mint: .usdf, quarks: 5_000_000),
            .init(mint: .makeLaunchpad(address: .jeffy), quarks: jeffyQuarks),
        ])
        let viewModel = Self.makeViewModel(mint: .usdcAuthority, container: container)

        #expect(viewModel.maxPossibleAmount.nativeAmount.formatted() == "$5.00")

        viewModel.paymentMint = .jeffy

        let jeffyValue = try #require(container.session.balance(for: .jeffy))
            .computeExchangedValue(with: container.ratesController.rateForBalanceCurrency())
        #expect(viewModel.maxPossibleAmount.nativeAmount == jeffyValue.nativeAmount)
        #expect(viewModel.maxPossibleAmount.nativeAmount.value > 5)
    }

    @Test("Without Dollars the largest eligible balance becomes the source")
    func defaultSource_fallsBackToLargestBalance() async throws {
        let container = try await Self.makeContainer(holdings: [
            .init(mint: .makeLaunchpad(address: .jeffy), quarks: 2_000 * 10_000_000_000),
            .init(mint: .makeLaunchpad(address: .testMint(index: 1)), quarks: 10_000_000_000),
        ])
        let viewModel = Self.makeViewModel(mint: .usdcAuthority, container: container)

        #expect(viewModel.paymentMint == .jeffy)
    }

    @Test("Zero eligible balance flips the button to Add Money")
    func zeroBalance_addMoneyCTA() async throws {
        let container = try await Self.makeContainer(holdings: [])
        let viewModel = Self.makeViewModel(container: container)

        #expect(viewModel.isBalanceEmpty)
        #expect(viewModel.actionTitle == "Add Money")
        #expect(viewModel.actionEnabled("") == true)
    }

    @Test("Holding only the target currency flips the button to Add Money")
    func onlyTargetHolding_addMoneyCTA() async throws {
        // The buy target can't pay for itself, so the sole holding leaves no
        // eligible source — the flow never reaches the payment selector.
        let jeffyQuarks: UInt64 = 2_000 * 10_000_000_000
        let container = try await Self.makeContainer(holdings: [
            .init(mint: .makeLaunchpad(address: .jeffy), quarks: jeffyQuarks),
        ])
        let viewModel = Self.makeViewModel(mint: .jeffy, container: container)

        #expect(viewModel.isBalanceEmpty)
        #expect(viewModel.actionTitle == "Add Money")
    }

    @Test("Add Money CTA presents the Add Money sheet")
    func zeroBalance_primaryActionPresentsAddMoney() async throws {
        let container = try await Self.makeContainer(holdings: [])
        let viewModel = Self.makeViewModel(container: container)
        let router = AppRouter()
        router.present(.balance)

        viewModel.primaryAction(router: router)

        #expect(router.presentedSheets.contains(.addMoney(.buyCurrency)))
    }

    @Test("Next pushes the payment confirmation with the validated amount")
    func next_pushesPaymentConfirmation() async throws {
        let container = try await Self.makeContainer(holdings: [
            .init(mint: .usdf, quarks: 30_000_000),
        ])
        let viewModel = Self.makeViewModel(container: container)
        let router = AppRouter()
        router.present(.balance)
        router.presentNested(.buy(.jeffy))

        viewModel.enteredAmount = "10"
        viewModel.primaryAction(router: router)

        // The push lands after the async pin fetch, not on the calling turn.
        try await waitUntil(router) { $0[.buy].count == 1 }
        #expect(viewModel.dialogItem == nil)
    }

    @Test("An invalid entered amount does not push")
    func invalidAmount_noop() async throws {
        let container = try await Self.makeContainer(holdings: [
            .init(mint: .usdf, quarks: 30_000_000),
        ])
        let viewModel = Self.makeViewModel(container: container)
        let router = AppRouter()
        router.present(.balance)
        router.presentNested(.buy(.jeffy))

        viewModel.enteredAmount = ""
        viewModel.primaryAction(router: router)

        #expect(router[.buy].isEmpty)
    }

    @Test("Entering beyond the cap disables Next; the cap itself is allowed")
    func overCap_disabled() async throws {
        let container = try await Self.makeContainer(holdings: [
            .init(mint: .usdf, quarks: 30_000_000),
        ])
        let viewModel = Self.makeViewModel(container: container)

        #expect(viewModel.actionEnabled("30") == true)
        #expect(viewModel.actionEnabled("31") == false)
    }

    // MARK: - Fee-affordable entry

    @Test("Paying the whole Dollars balance drops the entry to what the on-top fee leaves")
    func wholeDollarsBalance_isCorrected() async throws {
        let container = try await Self.makeContainer(holdings: [
            .init(mint: .usdf, quarks: 10_000_000), // $10.00
        ])
        let viewModel = Self.makeViewModel(mint: .usdcAuthority, container: container, collectsUSDFFee: true)
        viewModel.enteredAmount = "10"

        viewModel.correctEntryToAffordable()

        // $10.00 / 1.01 = $9.90099, floored to the cent so the debit fits.
        #expect(viewModel.enteredAmount == "9.90")
    }

    @Test("A Dollars entry with room for its fee is left exactly as typed")
    func dollarsEntryWithRoom_isLeftAlone() async throws {
        let container = try await Self.makeContainer(holdings: [
            .init(mint: .usdf, quarks: 10_000_000), // $10.00
        ])
        let viewModel = Self.makeViewModel(mint: .usdcAuthority, container: container, collectsUSDFFee: true)
        viewModel.enteredAmount = "5"

        viewModel.correctEntryToAffordable()

        #expect(viewModel.enteredAmount == "5")
    }

    @Test("Without the USDF fee the whole Dollars balance stays spendable")
    func wholeDollarsBalance_feeFreeUI_isLeftAlone() async throws {
        let container = try await Self.makeContainer(holdings: [
            .init(mint: .usdf, quarks: 10_000_000), // $10.00
        ])
        let viewModel = Self.makeViewModel(mint: .usdcAuthority, container: container, collectsUSDFFee: false)
        viewModel.enteredAmount = "10"

        viewModel.correctEntryToAffordable()

        #expect(viewModel.enteredAmount == "10")
    }

    @Test("Paying the whole token balance drops the entry to what the pool fee leaves")
    func wholeTokenBalance_isCorrected() async throws {
        let container = try await Self.makeContainer(holdings: [
            .init(mint: .makeLaunchpad(address: .jeffy), quarks: 2_000 * 10_000_000_000), // ≈ $20
        ])
        let viewModel = Self.makeViewModel(mint: .usdcAuthority, container: container)
        let balance = viewModel.maxPossibleAmount.nativeAmount
        let displayed = balance.value.rounded(to: CurrencyCode.usd.maximumFractionDigits)
        viewModel.enteredAmount = "\(displayed)"

        viewModel.correctEntryToAffordable()

        let corrected = try #require(AmountValidator().validate(viewModel.enteredAmount))
        #expect(corrected < displayed)
        // The entry is grossed up by the pool fee to form the debit — it must fit.
        let debit = FiatAmount(value: corrected, currency: .usd).grossingUpLaunchpadSellFee(bps: 100)
        #expect(debit.value <= balance.value)
    }
}
