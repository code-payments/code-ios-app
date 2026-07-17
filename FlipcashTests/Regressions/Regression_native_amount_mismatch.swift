//
//  Regression_native_amount_mismatch.swift
//  FlipcashTests
//
//  Regression coverage for the "native amount does not match sell amount"
//  server error. Invariants:
//  - Submission paths compute quarks against the pinned rate (and supply
//    where applicable), not the live cache.
//  - When no fresh pin is cached, the submission path bails with a dialog
//    instead of submitting an intent the server rejects.
//

import Foundation
import Testing
import FlipcashUI
@testable import Flipcash
@testable import FlipcashCore

@MainActor
@Suite(
    "Regression: native amount mismatch — pin-at-compute ties quarks to the submitted pin",
    .timeLimit(.minutes(1))
)
struct Regression_native_amount_mismatch {

    // MARK: - Scenario D (buy)

    @Test("Scenario D (buy): the payment compute uses the PINNED rate, not the live cache")
    func scenarioD_buyPaymentComputeUsesPinnedRate() async throws {
        // Pinned rate: 1 USD = 1.35 CAD. Live cache drifted to 1.37 after the
        // pin was captured. The payment-currency step pins the rate on row
        // selection and computes quarks against it; the balance is ample so
        // the USDF cap can't interfere.
        let sessionContainer = try SessionContainer.makeTest(
            holdings: [.init(mint: MintMetadata.usdf, quarks: 50_000_000)]
        )
        sessionContainer.ratesController.configureTestRates(
            balanceCurrency: .cad,
            rates: [Rate(fx: 1.37, currency: .cad)]
        )
        await sessionContainer.ratesController.verifiedProtoService.saveRates([
            .freshRate(currencyCode: "CAD", rate: 1.35)
        ])

        let vm = BuyPaymentCurrencyViewModel(
            targetMint: .jeffy,
            targetName: "Jeffy",
            entered: FiatAmount(value: 1, currency: .cad),
            session: sessionContainer.session,
            ratesController: sessionContainer.ratesController
        )

        let usdfBalance = try #require(sessionContainer.session.balance(for: .usdf))
        let pin = try #require(await sessionContainer.ratesController.currentPinnedState(for: .cad, mint: .usdf))
        let amount = try #require(vm.computePaymentAmount(for: usdfBalance, pin: pin))

        // $1 CAD / 1.35 × 10^6, HALF_UP rounded via scaleUpInt → 740_741 USDF quarks.
        // The buggy live path (1.37) would round to 729_927 quarks — the value
        // the server rejected in production.
        #expect(amount.onChainAmount.quarks == 740_741)
        #expect(amount.currencyRate.fx == Decimal(1.35))
        #expect(pin.exchangeRate == 1.35)
    }

    // MARK: - Scenario D (sell)

    @Test("Scenario D (sell): prepareSubmission computes quarks from the PINNED rate AND supply")
    func scenarioD_sellPrepareSubmissionUsesPinnedRateAndSupply() async throws {
        // Pinned: rate 1.35, supply 1M. Live cache: rate 1.37, supply 1.5M.
        let pinnedSupply: UInt64 = 1_000_000 * 10_000_000_000
        let liveSupply: UInt64 = 1_500_000 * 10_000_000_000

        let sessionContainer = SessionContainer.mock
        sessionContainer.ratesController.configureTestRates(
            balanceCurrency: .cad,
            rates: [Rate(fx: 1.37, currency: .cad)]
        )
        await sessionContainer.ratesController.verifiedProtoService.saveRates([
            .freshRate(currencyCode: "CAD", rate: 1.35)
        ])
        await sessionContainer.ratesController.verifiedProtoService.saveReserveStates([
            .freshReserve(mint: .jeffy, supplyFromBonding: pinnedSupply)
        ])

        let metadata = StoredMintMetadata(MintMetadata.makeLaunchpad(
            supplyFromBonding: liveSupply
        ))

        let vm = CurrencySellViewModel(
            currencyMetadata: metadata,
            session: sessionContainer.session,
            ratesController: sessionContainer.ratesController
        )
        vm.enteredAmount = "1"

        let submission = try #require(await vm.prepareSubmission())

        // The rate baked into the submitted ExchangedFiat must be the pinned
        // one (1.35), not the live cache (1.37).
        #expect(submission.amount.currencyRate.fx == Decimal(1.35))
        #expect(submission.amount.currencyRate.fx != Decimal(1.37))

        // And the VerifiedState carried to Session.sell must be the pinned
        // proof — with pinned supply, not the live metadata supply.
        #expect(submission.pinnedState.exchangeRate == 1.35)
        #expect(submission.pinnedState.supplyFromBonding == pinnedSupply)
    }

    // MARK: - Scenario D (withdraw)

    @Test("Scenario D (withdraw, USDF): prepareSubmission computes quarks from the PINNED rate")
    func scenarioD_withdrawPrepareSubmissionUsesPinnedRate() async throws {
        // Pinned CAD rate 1.35; live cache drifted to 1.37.
        let sessionContainer = SessionContainer.mock
        sessionContainer.ratesController.configureTestRates(
            balanceCurrency: .cad,
            rates: [Rate(fx: 1.37, currency: .cad)]
        )
        await sessionContainer.ratesController.verifiedProtoService.saveRates([
            .freshRate(currencyCode: "CAD", rate: 1.35)
        ])

        let vm = WithdrawViewModel(
            container: .mock,
            sessionContainer: sessionContainer
        )
        vm.kind = .sameMint(WithdrawViewModelTestHelpers.createExchangedBalance(quarks: 10_000_000))
        vm.enteredAmount = "1"

        let submission = try #require(await vm.prepareSubmission())

        // $1 CAD / 1.35 × 10^6 → 740_741 USDF quarks.
        #expect(submission.amount.onChainAmount.quarks == 740_741)
        #expect(submission.amount.currencyRate.fx == Decimal(1.35))
        #expect(submission.amount.currencyRate.fx != Decimal(1.37))
        #expect(submission.pinnedState.exchangeRate == 1.35)
    }

    // MARK: - Scenario E (buy)

    @Test("Scenario E (buy): selecting a payment currency surfaces Rate Unavailable when no fresh pin is cached")
    func scenarioE_buyPaymentSelectionSurfacesRateUnavailableWhenNoPin() async throws {
        // The account holds ample USDF; a live rate is configured, but nothing
        // is seeded in the verified proto service — the selection path has no
        // pin to carry to the summary and must bail without pushing.
        let sessionContainer = try SessionContainer.makeTest(
            holdings: [.init(mint: MintMetadata.usdf, quarks: 50_000_000)]
        )
        sessionContainer.ratesController.configureTestRates(
            balanceCurrency: .cad,
            rates: [Rate(fx: 1.35, currency: .cad)]
        )

        let vm = BuyPaymentCurrencyViewModel(
            targetMint: .jeffy,
            targetName: "Jeffy",
            entered: FiatAmount(value: 1, currency: .cad),
            session: sessionContainer.session,
            ratesController: sessionContainer.ratesController
        )

        let router = AppRouter()
        router.present(.balance)
        router.presentNested(.buy(.jeffy))

        let usdfRow = try #require(vm.rows.first { $0.stored.mint == .usdf })
        await vm.select(usdfRow, router: router)

        #expect(vm.dialogItem?.title == "Rate Unavailable")
        #expect(router[.buy].isEmpty, "A pinless selection must not push the summary")
    }

    // MARK: - Scenario E (sell)

    @Test("Scenario E (sell): prepareSubmission returns nil when no fresh pin is cached")
    func scenarioE_sellPrepareSubmissionReturnsNilWhenNoPin() async {
        // Live rate + live metadata supply are present; no pinned proof is.
        let sessionContainer = SessionContainer.mock
        sessionContainer.ratesController.configureTestRates(
            balanceCurrency: .cad,
            rates: [Rate(fx: 1.35, currency: .cad)]
        )

        let metadata = StoredMintMetadata(MintMetadata.makeLaunchpad(
            supplyFromBonding: 1_000_000 * 10_000_000_000
        ))

        let vm = CurrencySellViewModel(
            currencyMetadata: metadata,
            session: sessionContainer.session,
            ratesController: sessionContainer.ratesController
        )
        vm.enteredAmount = "1"

        let submission = await vm.prepareSubmission()

        #expect(submission == nil)
    }

    // MARK: - Scenario E (withdraw)

    @Test("Scenario E (withdraw): prepareSubmission returns nil when no fresh pin is cached")
    func scenarioE_withdrawPrepareSubmissionReturnsNilWhenNoPin() async {
        let sessionContainer = SessionContainer.mock
        sessionContainer.ratesController.configureTestRates(
            balanceCurrency: .cad,
            rates: [Rate(fx: 1.35, currency: .cad)]
        )

        let vm = WithdrawViewModel(
            container: .mock,
            sessionContainer: sessionContainer
        )
        vm.kind = .sameMint(WithdrawViewModelTestHelpers.createExchangedBalance(quarks: 10_000_000))
        vm.enteredAmount = "1"

        let submission = await vm.prepareSubmission()

        #expect(submission == nil)
    }

    // MARK: - Scenario G (give)

    @Test("Scenario G (give): prepareSubmission computes quarks from the PINNED rate AND supply")
    func scenarioG_givePrepareSubmissionUsesPinnedRateAndSupply() async throws {
        // Pinned: rate 1.35, supply 1M. Live cache: rate 1.37, supply 1.5M.
        let pinnedSupply: UInt64 = 1_000_000 * 10_000_000_000
        let liveSupply: UInt64 = 1_500_000 * 10_000_000_000

        let sessionContainer = SessionContainer.mock
        sessionContainer.ratesController.configureTestRates(
            balanceCurrency: .cad,
            rates: [Rate(fx: 1.37, currency: .cad)]
        )
        await sessionContainer.ratesController.verifiedProtoService.saveRates([
            .freshRate(currencyCode: "CAD", rate: 1.35)
        ])
        await sessionContainer.ratesController.verifiedProtoService.saveReserveStates([
            .freshReserve(mint: .jeffy, supplyFromBonding: pinnedSupply)
        ])

        let vm = GiveViewModel(
            container: .mock,
            sessionContainer: sessionContainer,
            mint: nil
        )
        vm.selectCurrencyAction(
            exchangedBalance: WithdrawViewModelTestHelpers.createBondedBalance(
                supplyFromBonding: liveSupply
            )
        )
        vm.enteredAmount = "1"

        let submission = try #require(await vm.prepareSubmission())

        // The rate baked into the submitted ExchangedFiat must be the pinned
        // one (1.35), not the live cache (1.37).
        #expect(submission.amount.currencyRate.fx == Decimal(1.35))
        #expect(submission.amount.currencyRate.fx != Decimal(1.37))

        // And the VerifiedState carried into Session.showCashBill →
        // SendCashOperation / createCashLink must be the pinned proof — with
        // pinned supply, not the live `selectedBalance.stored.supplyFromBonding`.
        #expect(submission.pinnedState.exchangeRate == 1.35)
        #expect(submission.pinnedState.supplyFromBonding == pinnedSupply)
    }

    @Test("Scenario G (give): prepareSubmission returns nil when no fresh pin is cached")
    func scenarioG_givePrepareSubmissionReturnsNilWhenNoPin() async {
        // Live rate is configured, but nothing is seeded in the verified proto
        // service — the submit path has no pin to use and must bail.
        let sessionContainer = SessionContainer.mock
        sessionContainer.ratesController.configureTestRates(
            balanceCurrency: .cad,
            rates: [Rate(fx: 1.35, currency: .cad)]
        )

        let vm = GiveViewModel(
            container: .mock,
            sessionContainer: sessionContainer,
            mint: nil
        )
        vm.selectCurrencyAction(
            exchangedBalance: WithdrawViewModelTestHelpers.createBondedBalance(
                supplyFromBonding: 1_000_000 * 10_000_000_000
            )
        )
        vm.enteredAmount = "1"

        let submission = await vm.prepareSubmission()

        #expect(submission == nil)
    }
}
