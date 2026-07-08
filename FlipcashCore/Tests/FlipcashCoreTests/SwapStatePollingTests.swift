//
//  SwapStatePollingTests.swift
//  FlipcashCoreTests
//

import Foundation
import Testing
@testable import FlipcashCore

@Suite("Swap state polling")
struct SwapStatePollingTests {

    // MARK: - Fixtures

    private static func testKey(_ seed: Int) -> PublicKey {
        try! PublicKey([UInt8](repeating: UInt8(seed), count: 32))
    }

    private static let swapId = SwapId.generate()
    private static let signature = try! Signature(Array(repeating: Byte(0), count: 64))

    private static func metadata(state: SwapState) -> SwapMetadata {
        SwapMetadata(
            verifiedMetadata: VerifiedSwapMetadata(
                clientParameters: VerifiedSwapMetadata.ClientParameters(
                    id: swapId,
                    fromMint: .usdf,
                    toMint: testKey(10),
                    amount: TokenAmount(quarks: 1_000_000, mint: .usdf),
                    fundingSource: .submitIntent(id: testKey(18))
                ),
                serverParameters: VerifiedSwapMetadata.ServerParameters(
                    nonce: testKey(2),
                    blockhash: try! Hash([UInt8](repeating: 3, count: 32))
                )
            ),
            state: state,
            signature: signature
        )
    }

    // MARK: - Terminal states

    @Test("Returns as soon as a terminal state is fetched", arguments: [SwapState.finalized, .failed, .cancelled])
    func returnsOnTerminalState(_ terminalState: SwapState) async throws {
        let attemptLog = AttemptLog()

        let result = try await pollSwapTerminalState(
            swapId: Self.swapId,
            maxAttempts: 5,
            pollInterval: .milliseconds(1),
            fetch: {
                let n = attemptLog.incrementAndGet()
                return Self.metadata(state: n < 3 ? .funding : terminalState)
            }
        )

        #expect(result.state == terminalState)
        #expect(attemptLog.count == 3)
    }

    // MARK: - Poll exhaustion

    @Test("Returns the last-fetched metadata when the budget is exhausted in an intermediate state")
    func exhaustionReturnsLastMetadata() async throws {
        let attemptLog = AttemptLog()

        let result = try await pollSwapTerminalState(
            swapId: Self.swapId,
            maxAttempts: 3,
            pollInterval: .milliseconds(1),
            fetch: {
                _ = attemptLog.incrementAndGet()
                return Self.metadata(state: .submitting)
            }
        )

        #expect(result.state == .submitting)
        #expect(attemptLog.count == 3)
    }

    @Test("Throws pollLimitReached only when no swap state was ever fetched")
    func exhaustionWithoutMetadataThrows() async {
        let attemptLog = AttemptLog()

        await #expect(throws: ClientError.pollLimitReached) {
            _ = try await pollSwapTerminalState(
                swapId: Self.swapId,
                maxAttempts: 3,
                pollInterval: .milliseconds(1),
                fetch: {
                    _ = attemptLog.incrementAndGet()
                    throw ErrorGetSwap.notFound
                }
            )
        }
        #expect(attemptLog.count == 3)
    }

    // MARK: - State changes

    @Test("Notifies onStateChange only when the state transitions")
    func onStateChangeFiresOnTransitionsOnly() async throws {
        let attemptLog = AttemptLog()
        let stateLog = StateLog()

        let states: [SwapState] = [.funding, .funding, .submitting, .submitting, .finalized]
        let result = try await pollSwapTerminalState(
            swapId: Self.swapId,
            maxAttempts: states.count,
            pollInterval: .milliseconds(1),
            onStateChange: { stateLog.append($0) },
            fetch: { Self.metadata(state: states[attemptLog.incrementAndGet() - 1]) }
        )

        #expect(result.state == .finalized)
        #expect(stateLog.states == [.funding, .submitting, .finalized])
    }

    // MARK: - Test helpers

    private final class AttemptLog: @unchecked Sendable {
        private let lock = NSLock()
        private var counter = 0
        var count: Int {
            lock.lock(); defer { lock.unlock() }
            return counter
        }
        func incrementAndGet() -> Int {
            lock.lock(); defer { lock.unlock() }
            counter += 1
            return counter
        }
    }

    private final class StateLog: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [SwapState] = []
        var states: [SwapState] {
            lock.lock(); defer { lock.unlock() }
            return storage
        }
        func append(_ state: SwapState) {
            lock.lock(); defer { lock.unlock() }
            storage.append(state)
        }
    }
}
