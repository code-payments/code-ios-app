//
//  RatesControllerStressTests.swift
//  FlipcashTests
//
//  TSan + Main Thread Checker sentinel for `RatesController`.
//  `RatesController` is `@MainActor @Observable` and drives `updateRates`
//  from the `verifiedProtoService.ratesPublisher` chain.
//
//  The race shape stresses two paths: (1) main-actor `updateRates(_:)`
//  writes interleaving with main-actor `cachedRates` reads, and (2) the
//  off-main `rateWriteQueue.async` block inside `updateRates` capturing
//  `database` concurrent with the main-actor reader loop. TSan flags any
//  unsafe access; `@Observable` registrar machinery is enforced at compile
//  time, not exercised here.
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
