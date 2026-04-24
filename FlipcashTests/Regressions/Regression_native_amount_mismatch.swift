//
//  Regression_native_amount_mismatch.swift
//  FlipcashTests
//
//  Regression coverage for the "native amount does not match sell amount" server error.
//  The root bug: the amount-entry VMs computed quarks against one rate source
//  (the live stream cache) while the submitted intent carried a different rate
//  (the pinned proof). Any drift between the two produced a native/quark
//  mismatch at the server.
//
//  Under pin-at-compute, the VM holds no pin while the user types; display math
//  reads from the live cache. At the moment the user commits (Buy / Next for
//  sell / Withdraw), `prepareSubmission()` fetches the pin and computes the
//  `ExchangedFiat` against *that* pin — one fetch, one rate, handed unchanged
//  to `Session.*`. The two-source problem cannot reappear.
//
//  Invariants proven here:
//  D) `prepareSubmission` computes quarks against the PINNED rate (and the
//     pinned bonded supply where applicable), not the live cache.
//  E) When no fresh pin is cached, `prepareSubmission` returns nil so the
//     submit path bails with the "rate unavailable" dialog instead of silently
//     submitting an intent the server would reject.
//

import Foundation
import Testing
@testable import Flipcash
@testable import FlipcashCore

@MainActor
@Suite(
    "Regression: native amount mismatch — pin-at-compute ties quarks to the submitted pin",
    .timeLimit(.minutes(1))
)
struct Regression_native_amount_mismatch {

    // MARK: - Scenario D (buy)

    @Test("Scenario D (buy): prepareSubmission computes quarks from the PINNED rate, not the live cache")
    func scenarioD_buyPrepareSubmissionUsesPinnedRate() async throws {
        // Pinned rate: 1 USD = 1.35 CAD. Live cache drifted to 1.37 after the pin was captured.
        let sessionContainer = SessionContainer.mock
        sessionContainer.ratesController.configureTestRates(
            entryCurrency: .cad,
            rates: [Rate(fx: 1.37, currency: .cad)]
        )
        await sessionContainer.ratesController.verifiedProtoService.saveRates([
            .freshRate(currencyCode: "CAD", rate: 1.35)
        ])

        let vm = CurrencyBuyViewModel(
            currencyPublicKey: .usdf,
            currencyName: "USDF",
            session: sessionContainer.session,
            ratesController: sessionContainer.ratesController
        )
        vm.enteredAmount = "1"

        let submission = try #require(await vm.prepareSubmission())

        // $1 CAD / 1.35 × 10^6, HALF_UP rounded via scaleUpInt → 740_741 USDF quarks.
        // The buggy live path (1.37) would round to 729_927 quarks — the value
        // the server rejected in production.
        #expect(submission.amount.onChainAmount.quarks == 740_741)
        #expect(submission.amount.currencyRate.fx == Decimal(1.35))
        #expect(submission.pinnedState.exchangeRate == 1.35)
    }

    // MARK: - Scenario D (sell)

    @Test("Scenario D (sell): prepareSubmission computes quarks from the PINNED rate AND supply")
    func scenarioD_sellPrepareSubmissionUsesPinnedRateAndSupply() async throws {
        // Pinned: rate 1.35, supply 1M. Live cache: rate 1.37, supply 1.5M.
        let pinnedSupply: UInt64 = 1_000_000 * 10_000_000_000
        let liveSupply: UInt64 = 1_500_000 * 10_000_000_000

        let sessionContainer = SessionContainer.mock
        sessionContainer.ratesController.configureTestRates(
            entryCurrency: .cad,
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
            entryCurrency: .cad,
            rates: [Rate(fx: 1.37, currency: .cad)]
        )
        await sessionContainer.ratesController.verifiedProtoService.saveRates([
            .freshRate(currencyCode: "CAD", rate: 1.35)
        ])

        let vm = WithdrawViewModel(
            isPresented: .constant(true),
            container: .mock,
            sessionContainer: sessionContainer
        )
        vm.selectedBalance = WithdrawViewModelTestHelpers.createExchangedBalance(quarks: 10_000_000)
        vm.enteredAmount = "1"

        let submission = try #require(await vm.prepareSubmission())

        // $1 CAD / 1.35 × 10^6 → 740_741 USDF quarks.
        #expect(submission.amount.onChainAmount.quarks == 740_741)
        #expect(submission.amount.currencyRate.fx == Decimal(1.35))
        #expect(submission.amount.currencyRate.fx != Decimal(1.37))
        #expect(submission.pinnedState.exchangeRate == 1.35)
    }

    // MARK: - Scenario E (buy)

    @Test("Scenario E (buy): prepareSubmission returns nil when no fresh pin is cached")
    func scenarioE_buyPrepareSubmissionReturnsNilWhenNoPin() async {
        // Live rate is configured, but nothing is seeded in the verified proto
        // service — the submit path has no pin to use and must bail.
        let sessionContainer = SessionContainer.mock
        sessionContainer.ratesController.configureTestRates(
            entryCurrency: .cad,
            rates: [Rate(fx: 1.35, currency: .cad)]
        )

        let vm = CurrencyBuyViewModel(
            currencyPublicKey: .usdf,
            currencyName: "USDF",
            session: sessionContainer.session,
            ratesController: sessionContainer.ratesController
        )
        vm.enteredAmount = "1"

        let submission = await vm.prepareSubmission()

        #expect(submission == nil)
    }

    // MARK: - Scenario E (sell)

    @Test("Scenario E (sell): prepareSubmission returns nil when no fresh pin is cached")
    func scenarioE_sellPrepareSubmissionReturnsNilWhenNoPin() async {
        // Live rate + live metadata supply are present; no pinned proof is.
        let sessionContainer = SessionContainer.mock
        sessionContainer.ratesController.configureTestRates(
            entryCurrency: .cad,
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
            entryCurrency: .cad,
            rates: [Rate(fx: 1.35, currency: .cad)]
        )

        let vm = WithdrawViewModel(
            isPresented: .constant(true),
            container: .mock,
            sessionContainer: sessionContainer
        )
        vm.selectedBalance = WithdrawViewModelTestHelpers.createExchangedBalance(quarks: 10_000_000)
        vm.enteredAmount = "1"

        let submission = await vm.prepareSubmission()

        #expect(submission == nil)
    }
}
