//
//  UsdcSweepOperationTests.swift
//  FlipcashTests
//

import Foundation
import Testing
@testable import Flipcash
import FlipcashCore
import FlipcashAPI

@Suite("UsdcSweepOperation")
struct UsdcSweepOperationTests {

    // MARK: - Single in-flight

    @Test("Re-entrant start() calls don't double-fire — the second is skipped while the first is still awaiting the fetch")
    func reentrantStartSkipsWhenInFlight() async throws {
        let fetcher = MockAccountFetcher()
        let swapper = MockSwapper()
        let completion = Counter()

        let op = UsdcSweepOperation(
            accountFetcher: fetcher,
            swapper: swapper,
            ownerKeyPair: .mock,
            onSweepCompleted: { await completion.bump() }
        )

        // Park the first fetch on a continuation so the second start() lands
        // mid-flight and can observe the isRunning gate.
        let firstFetchEntered = Expectation()
        await fetcher.setBlockingHandler { firstFetchEntered.fulfill() }

        let firstRun = op.start()

        // Wait until the first sweep is parked inside the fetch.
        await firstFetchEntered.wait()

        // Second start() — should observe isRunning=true and bail without
        // touching the fetcher.
        await op.start().value
        #expect(await fetcher.callCount == 1)

        // Unblock the first run; it returns nil → no swap → no completion call.
        await fetcher.resumeWith(.success(nil))
        await firstRun.value

        #expect(await fetcher.callCount == 1)
        #expect(await swapper.callCount == 0)
        #expect(await completion.value == 0)
    }

    // MARK: - Empty balance

    /// Both "no ATA" (server returned nil) and "ATA with zero quarks" should
    /// short-circuit before the swap. Parameterized over the two cases so
    /// the single expectation is checked uniformly.
    @Test(
        "Empty USDC ATA short-circuits before the swap",
        arguments: [Optional<UInt64>.none, .some(0)]
    )
    func emptyAtaSkipsSwap(quarks: UInt64?) async throws {
        let fetcher = MockAccountFetcher()
        let swapper = MockSwapper()
        let completion = Counter()

        let op = UsdcSweepOperation(
            accountFetcher: fetcher,
            swapper: swapper,
            ownerKeyPair: .mock,
            onSweepCompleted: { await completion.bump() }
        )

        await fetcher.setImmediateHandler {
            guard let quarks else { return nil }
            return try AccountInfo(.usdcAtaInfo(quarks: quarks))
        }
        await op.start().value

        #expect(await fetcher.callCount == 1)
        #expect(await swapper.callCount == 0)
        #expect(await completion.value == 0)
    }
}

// MARK: - Mocks

private actor MockAccountFetcher: AssociatedTokenAccountFetching {

    private(set) var callCount = 0

    private enum Mode {
        case immediate(@Sendable () throws -> AccountInfo?)
        case blocking(@Sendable () -> Void)
    }
    private var mode: Mode?
    private var pendingContinuation: CheckedContinuation<Result<AccountInfo?, Error>, Never>?

    func setImmediateHandler(_ handler: @escaping @Sendable () throws -> AccountInfo?) {
        mode = .immediate(handler)
    }

    func setBlockingHandler(_ onEntered: @escaping @Sendable () -> Void) {
        mode = .blocking(onEntered)
    }

    func resumeWith(_ result: Result<AccountInfo?, Error>) {
        pendingContinuation?.resume(returning: result)
        pendingContinuation = nil
    }

    func fetchAssociatedTokenAccount(owner: KeyPair, mint: PublicKey) async throws -> AccountInfo? {
        callCount += 1
        switch mode {
        case .immediate(let handler):
            return try handler()
        case .blocking(let onEntered):
            onEntered()
            let result: Result<AccountInfo?, Error> = await withCheckedContinuation { c in
                pendingContinuation = c
            }
            return try result.get()
        case nil:
            return nil
        }
    }
}

private actor MockSwapper: StatelessSwapping {

    private(set) var callCount = 0

    func statelessSwap(
        fromMint: MintMetadata,
        toMint: MintMetadata,
        amount: TokenAmount,
        owner: KeyPair
    ) async throws -> StatelessSwapResult {
        callCount += 1
        return .submitted(signature: try Signature(Data(repeating: 0, count: 64)))
    }
}

private actor Counter {
    private(set) var value = 0
    func bump() { value += 1 }
}

/// Async one-shot expectation used to coordinate a test's `await` with a
/// mock's entry point. Backed by a single `CheckedContinuation` — wait()
/// suspends until fulfill() resumes it.
private final class Expectation: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var fulfilled = false

    func fulfill() {
        lock.lock()
        if let c = continuation {
            continuation = nil
            lock.unlock()
            c.resume()
        } else {
            fulfilled = true
            lock.unlock()
        }
    }

    func wait() async {
        await withCheckedContinuation { c in
            lock.lock()
            if fulfilled {
                fulfilled = false
                lock.unlock()
                c.resume()
            } else {
                continuation = c
                lock.unlock()
            }
        }
    }
}

// MARK: - Fixtures

private extension Ocp_Account_V1_TokenAccountInfo {
    static func usdcAtaInfo(quarks: UInt64) -> Ocp_Account_V1_TokenAccountInfo {
        let id = PublicKey.mock.solanaAccountID
        var proto = Ocp_Account_V1_TokenAccountInfo()
        proto.address = id
        proto.mint = id
        proto.owner = id
        proto.authority = id
        proto.balance = quarks
        proto.accountType = .associatedTokenAccount
        return proto
    }
}
