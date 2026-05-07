//
//  LiveMintDataStreamerStressTests.swift
//  FlipcashTests
//
//  Pre-strip baseline for the Swift 6 / `defaultIsolation = MainActor`
//  migration. `LiveMintDataStreamer` is the actor that bridges the
//  bidirectional gRPC stream for rates + reserves into the rest of the app.
//  Its public mutators (`start`, `stop`, `updateMints`, `ensureConnected`)
//  are dispatched as fire-and-forget Tasks from `RatesController`, so they
//  can race in production. With TSan and Main Thread Checker both enabled
//  on the test scheme, a real data race or actor-isolation violation here
//  will surface as a TSan warning or runtime assertion.
//
//  The test uses empty mint sets so `openStream()` early-returns without
//  dialing a real gRPC stream — we're stressing the actor's serialization
//  model under contention, not the network path.
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@Suite("LiveMintDataStreamer concurrent access", .timeLimit(.minutes(1)))
struct LiveMintDataStreamerStressTests {

    @Test("Concurrent start/stop/updateMints/ensureConnected do not crash")
    @MainActor
    func concurrentMutators_doNotCrash() async {
        let streamer = Client.mock.createLiveMintDataStreamer(
            verifiedProtoService: VerifiedProtoService(store: InMemoryVerifiedProtoStore())
        )

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                group.addTask {
                    await streamer.start(mints: [])
                    await streamer.updateMints([])
                    if i.isMultiple(of: 2) {
                        await streamer.ensureConnected()
                    }
                    await streamer.stop()
                }
            }
        }

        // If we got here without TSan warnings or actor-isolation
        // assertions, the actor's isolation holds under the burst pattern
        // that `RatesController` produces during foreground/background and
        // mint-subscription churn.
    }

    @Test("Cancellation tears down cleanly")
    @MainActor
    func cancellation_doesNotLeakOrCrash() async {
        let streamer = Client.mock.createLiveMintDataStreamer(
            verifiedProtoService: VerifiedProtoService(store: InMemoryVerifiedProtoStore())
        )

        let task = Task {
            for _ in 0..<1_000 {
                await streamer.start(mints: [])
                await streamer.stop()
            }
        }
        task.cancel()
        await task.value
    }
}
