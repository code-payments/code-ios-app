//
//  Regression_native_amount_mismatch.swift
//  FlipcashTests
//
//  Regression coverage for the "native amount does not match sell amount" server error.
//  The root bug: a stream update mid-flow could replace the VerifiedState the VM had
//  used to compute amounts, causing the intent to be built with a different state than
//  the one reflected in the UI. The fix pins the state at flow-open time.
//
//  Invariants proven here:
//  A) Stream deliveries do not mutate a VM's pinned state.
//  B) Stale cached protos block flow-open (currentPinnedState returns nil).
//  C) A stale pin already held by a VM disables submit (canPerformAction = false).
//  D) Amount-entry compute sources rate (and supply) from the pinned proof,
//     not the live cache — the original root cause of the server error.
//  E) Swapping pinnedState re-renders the VM's computed properties, so an
//     entry-currency switch mid-flow updates the screen.
//

import Foundation
import Testing
@testable import Flipcash
@testable import FlipcashCore

@MainActor
@Suite(
    "Regression: native amount mismatch — pinning prevents drift between UI and intent",
    .timeLimit(.minutes(1))
)
struct Regression_native_amount_mismatch {

    // MARK: - Scenario A

    @Test("Scenario A: stream delivers a newer state mid-flow; the ViewModel's pinned state never swaps")
    func scenarioA_streamUpdateIgnoredMidFlow() async {
        // Make a fresh pinned state at a specific rate.
        let pinnedState = VerifiedState.fresh(bonded: false)

        // SessionContainer.mock is a computed `static var`, so this gives us a
        // fresh, internally-consistent Database / RatesController / Session.
        // saveReserveStates will not leak into any other test.
        let sessionContainer = SessionContainer.mock
        let vm = CurrencyBuyViewModel(
            currencyPublicKey: .usdf,
            currencyName: "USDF",
            pinnedState: pinnedState,
            session: sessionContainer.session
        )

        // Stream delivers a newer reserve state (a different supply) into THIS
        // controller's verifiedProtoService — the same one the VM is bound to.
        // `saveReserveStates` is actor-isolated, so by the time `await`
        // returns the service has finished applying the update.
        await sessionContainer.ratesController.verifiedProtoService.saveReserveStates([
            .freshReserve(mint: .jeffy, supplyFromBonding: 2_000_000)
        ])

        // Nothing in the stream path writes to the VM; only the screen's
        // `.onChange` does. The VM's pinned state must still be the one
        // captured at init.
        #expect(vm.pinnedState == pinnedState)
    }

    // MARK: - Scenario B

    @Test("Scenario B: a stale cached pin cannot be used to construct a ViewModel (currentPinnedState returns nil)")
    func scenarioB_stalePinBlocksOpeningFlow() async {
        // RatesController.mock is now computed — each access builds a fresh
        // graph, so seeding stale protos here can't leak into other suites.
        let controller = RatesController.mock

        // Seed the service with stale protos for both rate and reserve.
        await controller.verifiedProtoService.saveRates([
            .staleRate(currencyCode: "USD", rate: 1.0)
        ])
        await controller.verifiedProtoService.saveReserveStates([
            .staleReserve(mint: .jeffy, supplyFromBonding: 1)
        ])

        // The navigation gate calls currentPinnedState before constructing the VM.
        let pin = await controller.currentPinnedState(for: .usd, mint: .jeffy)

        // Stale protos must not produce a pin — navigation stays blocked.
        #expect(pin == nil)
    }

    // MARK: - Scenario C

    @Test("Scenario C: once the pin ages past clientMaxAge while the screen is open, canSubmit becomes false")
    func scenarioC_pinAgesOutMidFlow_disablesSubmit() {
        // Simulate a pin that became stale while the screen was open.
        let stalePin = VerifiedState.stale(bonded: false)

        let sessionContainer = SessionContainer.mock
        let vm = CurrencyBuyViewModel(
            currencyPublicKey: .usdf,
            currencyName: "USDF",
            pinnedState: stalePin,
            session: sessionContainer.session
        )

        // Enter an amount that would otherwise be valid.
        vm.enteredAmount = "1"

        // canPerformAction must be false — staleness check gates submission.
        #expect(vm.canPerformAction == false)
    }

    // MARK: - Scenario D

    /// This is the invariant the earlier scenarios missed: even when the VM's
    /// `pinnedState` reference is preserved, the UI math has to USE it. If
    /// `enteredFiat` sources its rate from the live cache while the intent
    /// carries the pinned `rateProto`, the server will see (quarks, nativeAmount)
    /// that don't match its rate proof — exactly the production error.
    @Test("Scenario D: enteredFiat computes quarks from the PINNED rate, not the live cache")
    func scenarioD_enteredFiatUsesPinnedRate_buyFlow() throws {
        // Pinned rate: 1 USD = 1.35 CAD. Live rate has drifted to 1.37 after
        // the pin was captured.
        let pinned = VerifiedState.fresh(bonded: false, currencyCode: "CAD", exchangeRate: 1.35)

        let sessionContainer = SessionContainer.mock
        sessionContainer.ratesController.configureTestRates(
            entryCurrency: .cad,
            rates: [Rate(fx: 1.37, currency: .cad)]
        )

        let vm = CurrencyBuyViewModel(
            currencyPublicKey: .usdf,
            currencyName: "USDF",
            pinnedState: pinned,
            session: sessionContainer.session
        )
        vm.enteredAmount = "1"

        // $1 CAD / 1.35 × 10^6, HALF_UP rounded via scaleUpInt → 740_741 USDF quarks.
        // The buggy path (live rate 1.37) would round to 729_927 quarks — the
        // value the server already rejected in production.
        let entered = try #require(vm.enteredFiat)
        #expect(entered.onChainAmount.quarks == 740_741)
        #expect(entered.onChainAmount.quarks != 729_927)
    }

    @Test("Scenario D (withdraw): enteredFiat.currencyRate is the PINNED rate, not the live cache")
    func scenarioD_enteredFiatUsesPinnedRate_withdrawFlow() throws {
        // Pinned CAD rate is 1.35; live cache has drifted to 1.37.
        let pinned = VerifiedState.fresh(
            bonded: true,
            currencyCode: "CAD",
            exchangeRate: 1.35,
            supplyFromBonding: 1_000_000 * 10_000_000_000
        )

        let viewModel = WithdrawViewModelTestHelpers.createViewModel(
            entryCurrency: .cad,
            rates: [Rate(fx: 1.37, currency: .cad)],
            pinnedState: pinned
        )
        viewModel.selectedBalance = WithdrawViewModelTestHelpers.createBondedBalance(
            supplyFromBonding: 1_500_000 * 10_000_000_000
        )
        viewModel.enteredAmount = "1"

        let entered = try #require(viewModel.enteredFiat)
        #expect(entered.currencyRate.fx == Decimal(1.35))
        #expect(entered.currencyRate.fx != Decimal(1.37))
    }

    @Test("Scenario D (withdraw): falls back to live rate when pinnedState is nil, but submit stays gated")
    func scenarioD_withdrawFallbackWhenPinnedStateNil() throws {
        // No pinned state yet (still being fetched). enteredFiat must remain
        // usable for display, but canCompleteWithdrawal must be false — the
        // submit gate is what keeps an intent with a live-rate amount from
        // reaching Session.withdraw.
        let liveRate = Rate(fx: 1.37, currency: .cad)
        let viewModel = WithdrawViewModelTestHelpers.createViewModel(
            entryCurrency: .cad,
            rates: [liveRate],
            pinnedState: nil
        )
        viewModel.selectedBalance = WithdrawViewModelTestHelpers.createExchangedBalance(quarks: 10_000_000)
        viewModel.enteredAmount = "1"
        viewModel.enteredAddress = "11111111111111111111111111111111"
        viewModel.destinationMetadata = WithdrawViewModelTestHelpers.createDestinationMetadata()

        let entered = try #require(viewModel.enteredFiat)
        #expect(entered.currencyRate.fx == Decimal(1.37))
        #expect(viewModel.canCompleteWithdrawal == false)
    }

    @Test("Scenario D (sell): enteredFiat.currencyRate is the PINNED rate, not the live cache")
    func scenarioD_enteredFiatUsesPinnedRate_sellFlow() throws {
        // Pinned CAD rate is 1.35; live cache has drifted to 1.37.
        let pinned = VerifiedState.fresh(
            bonded: true,
            currencyCode: "CAD",
            exchangeRate: 1.35,
            supplyFromBonding: 1_000_000 * 10_000_000_000
        )

        let metadata = StoredMintMetadata(MintMetadata.makeLaunchpad(
            supplyFromBonding: 1_500_000 * 10_000_000_000
        ))

        let sessionContainer = SessionContainer.mock
        sessionContainer.ratesController.configureTestRates(
            entryCurrency: .cad,
            rates: [Rate(fx: 1.37, currency: .cad)]
        )

        let vm = CurrencySellViewModel(
            currencyMetadata: metadata,
            pinnedState: pinned,
            session: sessionContainer.session
        )
        vm.enteredAmount = "1"

        // `currencyRate` on the output ExchangedFiat is the rate that was
        // passed into `compute(fromEntered:rate:…)`. With the fix in place it
        // is the pinned rate (1.35); before the fix it was the live cache
        // (1.37). Comparing `.fx` via Decimal proves which source was used.
        let entered = try #require(vm.enteredFiat)
        #expect(entered.currencyRate.fx == Decimal(1.35))
        #expect(entered.currencyRate.fx != Decimal(1.37))
    }

    // MARK: - Scenario E

    /// Entry-currency switch mid-flow: the bug was that the screen's math
    /// (subtitle, max, quarks) kept showing the original currency's values
    /// because `pinnedState` was `@ObservationIgnored let`. The screen now
    /// fetches a new pin and assigns it; this test guards the VM contract
    /// that makes that assignment actually re-render — `pinnedState` is
    /// observed, and the computed properties that read it re-evaluate.
    @Test("Scenario E (buy): swapping pinnedState flips the computed currency")
    func scenarioE_buyVMReactsToPinSwap() throws {
        let usdPin = VerifiedState.fresh(bonded: false, currencyCode: "USD", exchangeRate: 1.0)
        let cadPin = VerifiedState.fresh(bonded: false, currencyCode: "CAD", exchangeRate: 1.35)

        let sessionContainer = SessionContainer.mock
        let vm = CurrencyBuyViewModel(
            currencyPublicKey: .usdf,
            currencyName: "USDF",
            pinnedState: usdPin,
            session: sessionContainer.session
        )
        vm.enteredAmount = "1"

        let enteredBefore = try #require(vm.enteredFiat)
        #expect(enteredBefore.currencyRate.fx == Decimal(1.0))
        #expect(vm.maxPossibleAmount.nativeAmount.currency == .usd)

        vm.pinnedState = cadPin

        let enteredAfter = try #require(vm.enteredFiat)
        #expect(enteredAfter.currencyRate.fx == Decimal(1.35))
        #expect(vm.maxPossibleAmount.nativeAmount.currency == .cad)
    }

    @Test("Scenario E (sell): swapping pinnedState flips the computed currency")
    func scenarioE_sellVMReactsToPinSwap() {
        let usdPin = VerifiedState.fresh(bonded: true, currencyCode: "USD", exchangeRate: 1.0, supplyFromBonding: 1_000_000 * 10_000_000_000)
        let cadPin = VerifiedState.fresh(bonded: true, currencyCode: "CAD", exchangeRate: 1.35, supplyFromBonding: 1_000_000 * 10_000_000_000)

        let metadata = StoredMintMetadata(MintMetadata.makeLaunchpad(supplyFromBonding: 1_000_000 * 10_000_000_000))
        let sessionContainer = SessionContainer.mock

        let vm = CurrencySellViewModel(
            currencyMetadata: metadata,
            pinnedState: usdPin,
            session: sessionContainer.session
        )

        #expect(vm.maxPossibleAmount.nativeAmount.currency == .usd)

        vm.pinnedState = cadPin

        #expect(vm.maxPossibleAmount.nativeAmount.currency == .cad)
    }
}
