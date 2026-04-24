//
//  Regression_native_amount_mismatch.swift
//  FlipcashTests
//
//  Regression coverage for the "native amount does not match sell amount" server error.
//  The root bug: a stream update mid-flow could replace the VerifiedState the VM had
//  used to compute amounts, causing the intent to be built with a different state than
//  the one reflected in the UI. The fix pins the state at flow-open time.
//
//  Three invariants are proven here:
//  A) A pinned state is immutable across stream deliveries.
//  B) Stale cached protos block flow-open (currentPinnedState returns nil).
//  C) A stale pin already held by a VM disables submit (canPerformAction = false).
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
            session: sessionContainer.session,
            ratesController: sessionContainer.ratesController
        )

        // Stream delivers a newer reserve state (a different supply) into THIS
        // controller's verifiedProtoService — the same one the VM is bound to.
        await sessionContainer.ratesController.verifiedProtoService.saveReserveStates([
            .freshReserve(mint: .jeffy, supplyFromBonding: 2_000_000)
        ])

        // Give any hypothetical stream-subscriber a chance to (incorrectly) re-pin.
        try? await Task.sleep(nanoseconds: 100_000_000)

        // The VM's pinned state MUST be unchanged — it is a `let`, captured at init.
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
            session: sessionContainer.session,
            ratesController: sessionContainer.ratesController
        )

        // Enter an amount that would otherwise be valid.
        vm.enteredAmount = "1"

        // canPerformAction must be false — staleness check gates submission.
        #expect(vm.canPerformAction == false)
    }
}
