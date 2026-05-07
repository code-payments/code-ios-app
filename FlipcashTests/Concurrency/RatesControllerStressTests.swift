//
//  RatesControllerStressTests.swift
//  FlipcashTests
//
//  Pre-strip baseline for the Swift 6 / `defaultIsolation = MainActor`
//  migration. `RatesController` is `@MainActor @Observable` and the first
//  app-target stress test in this suite. Production code drives `updateRates`
//  from the `verifiedProtoService.ratesPublisher` chain — the publisher hops
//  back to main via `.receive(on: DispatchQueue.main)`, but the work that
//  *originates* the call lives off-main, so a non-main caller racing a
//  main-actor reader is the realistic shape here.
//
//  With TSan and Main Thread Checker both enabled on the test scheme, a race
//  in the `@Observable` registrar — or in `cachedRates` itself — surfaces as
//  a TSan warning, while a missed actor hop surfaces as a Swift runtime
//  isolation assertion. The test's job is to set up the read/write contention;
//  there's no `#expect` for "values didn't tear" — that's a TSan-only contract.
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@Suite("RatesController concurrent updates", .timeLimit(.minutes(1)))
@MainActor
struct RatesControllerStressTests {

    @Test("Concurrent rate updates do not tear when read on main")
    func concurrentUpdates_doNotTearValues() async {
        let controller = RatesController.mock

        let updater = Task.detached {
            for i in 0..<100 {
                let rate = Rate(fx: Decimal(i + 1) / 100, currency: .usd)
                await MainActor.run {
                    controller.updateRates([rate])
                }
            }
        }

        for _ in 0..<100 {
            _ = controller.rate(for: .usd)
            _ = controller.cachedRates.count
            await Task.yield()
        }

        await updater.value

        // Drain the background SQLite write queue so the controller can
        // tear down without a write outliving the test.
        await controller.awaitPendingRateWrites()
    }

    /// Cancelling the writer mid-flight while a reader is still iterating
    /// must not crash, leak, or strand work on the SQLite write queue.
    @Test("Cancellation tears down cleanly")
    func cancellation_doesNotLeakOrCrash() async {
        let controller = RatesController.mock

        let updater = Task.detached {
            for i in 0..<1_000 {
                let rate = Rate(fx: Decimal(i + 1) / 100, currency: .usd)
                await MainActor.run {
                    controller.updateRates([rate])
                }
            }
        }
        updater.cancel()
        await updater.value

        await controller.awaitPendingRateWrites()
    }
}
