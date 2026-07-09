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

    @Test(
        "Re-entrant start() calls don't double-fire — the second is skipped while the first is still awaiting the fetch",
        .tags(.concurrency)
    )
    func start_whileInFlight_skipsSecondCall() async throws {
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
    func start_whenAtaEmpty_skipsSwap(quarks: UInt64?) async throws {
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

    // MARK: - Happy path

    @Test("Positive USDC balance runs the swap and fires onSweepCompleted")
    func start_withPositiveBalance_invokesSwapAndCompletion() async throws {
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
            try AccountInfo(.usdcAtaInfo(quarks: 10_000))
        }
        await op.start().value

        #expect(await fetcher.callCount == 1)
        #expect(await swapper.callCount == 1)
        #expect(await completion.value == 1)
    }

    // MARK: - Re-entry after completion

    @Test(
        "Second start() after a successful sweep runs another sweep",
        .tags(.concurrency)
    )
    func start_afterPreviousCompletion_allowsSecondSweep() async throws {
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
            try AccountInfo(.usdcAtaInfo(quarks: 10_000))
        }

        await op.start().value
        #expect(await fetcher.callCount == 1)
        #expect(await swapper.callCount == 1)
        #expect(await completion.value == 1)

        // A second start() after the first completes must run another sweep.
        // Load-bearing: scenePhase → active fires repeatedly, and a fresh USDC
        // deposit between two activations must be picked up by the next sweep.
        await op.start().value
        #expect(await fetcher.callCount == 2)
        #expect(await swapper.callCount == 2)
        #expect(await completion.value == 2)
    }

    // MARK: - Error path

    @Test(
        "Swap failure skips the completion callback and releases the in-flight guard",
        .tags(.concurrency)
    )
    func start_whenSwapThrows_skipsCompletionAndReleasesGuard() async throws {
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
            try AccountInfo(.usdcAtaInfo(quarks: 10_000))
        }
        await swapper.setNextResult(.failure(ErrorStatelessSwap.unknown))
        await op.start().value

        #expect(await swapper.callCount == 1)
        #expect(await completion.value == 0)

        // A second start() must proceed — proves the catch path released isRunning.
        await op.start().value
        #expect(await fetcher.callCount == 2)
        #expect(await swapper.callCount == 2)
    }

    // MARK: - Retrying sweep (Add Money deposit flow)

    @Test("sweepUntilConverted converts on the first attempt when USDC is already present")
    func sweepUntilConverted_whenPresent_convertsImmediately() async throws {
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
            try AccountInfo(.usdcAtaInfo(quarks: 10_000))
        }

        let converted = await op.sweepUntilConverted(maxAttempts: 3, backoff: .zero)

        #expect(converted)
        #expect(await fetcher.callCount == 1)
        #expect(await swapper.callCount == 1)
        // The retrying sweep leaves the post-transaction refresh to the caller.
        #expect(await completion.value == 0)
    }

    @Test("sweepUntilConverted retries then gives up when USDC never lands")
    func sweepUntilConverted_whenNeverPresent_exhaustsAndReturnsFalse() async throws {
        let fetcher = MockAccountFetcher()
        let swapper = MockSwapper()

        let op = UsdcSweepOperation(
            accountFetcher: fetcher,
            swapper: swapper,
            ownerKeyPair: .mock,
            onSweepCompleted: {}
        )

        await fetcher.setImmediateHandler { nil }

        let converted = await op.sweepUntilConverted(maxAttempts: 4, backoff: .zero)

        #expect(!converted)
        #expect(await fetcher.callCount == 4)
        #expect(await swapper.callCount == 0)
    }

    @Test("sweepUntilConverted stops after the first successful swap")
    func sweepUntilConverted_stopsAfterFirstSwap() async throws {
        let fetcher = MockAccountFetcher()
        let swapper = MockSwapper()

        let op = UsdcSweepOperation(
            accountFetcher: fetcher,
            swapper: swapper,
            ownerKeyPair: .mock,
            onSweepCompleted: {}
        )

        // Empty on the first poll, funded on the second — the sweep must fire
        // exactly once and not poll again after converting.
        await fetcher.setSequence([
            .success(try AccountInfo(.usdcAtaInfo(quarks: 0))),
            .success(try AccountInfo(.usdcAtaInfo(quarks: 10_000))),
            .success(try AccountInfo(.usdcAtaInfo(quarks: 10_000))),
        ])

        let converted = await op.sweepUntilConverted(maxAttempts: 5, backoff: .zero)

        #expect(converted)
        #expect(await fetcher.callCount == 2)
        #expect(await swapper.callCount == 1)
    }

    @Test("sweepUntilConverted waits until the balance meets expectedAtLeast")
    func sweepUntilConverted_respectsExpectedAtLeast() async throws {
        let fetcher = MockAccountFetcher()
        let swapper = MockSwapper()

        let op = UsdcSweepOperation(
            accountFetcher: fetcher,
            swapper: swapper,
            ownerKeyPair: .mock,
            onSweepCompleted: {}
        )

        // 3_000 quarks present but the caller requires at least 5_000 — the first
        // poll is below threshold, the second meets it.
        await fetcher.setSequence([
            .success(try AccountInfo(.usdcAtaInfo(quarks: 3_000))),
            .success(try AccountInfo(.usdcAtaInfo(quarks: 5_000))),
        ])

        let converted = await op.sweepUntilConverted(
            expectedAtLeast: TokenAmount(quarks: 5_000, mint: .usdc),
            maxAttempts: 5,
            backoff: .zero
        )

        #expect(converted)
        #expect(await fetcher.callCount == 2)
        #expect(await swapper.callCount == 1)
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

    /// Per-call results for the retrying sweep tests: each `fetch` pops the next
    /// element; once exhausted it returns `.success(nil)`. Takes precedence over
    /// `mode` when set, so existing single-mode tests are unaffected.
    private var sequence: [Result<AccountInfo?, Error>]?
    private var sequenceIndex = 0

    func setSequence(_ results: [Result<AccountInfo?, Error>]) {
        sequence = results
        sequenceIndex = 0
    }

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
        if let sequence {
            let result = sequenceIndex < sequence.count ? sequence[sequenceIndex] : .success(nil)
            sequenceIndex += 1
            return try result.get()
        }
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
    private var nextResult: Result<StatelessSwapResult, Error> = .success(
        .finalized(signature: try! Signature(Data(repeating: 0, count: 64)))
    )

    func setNextResult(_ result: Result<StatelessSwapResult, Error>) {
        nextResult = result
    }

    func statelessSwap(
        fromMint: MintMetadata,
        toMint: MintMetadata,
        amount: TokenAmount,
        owner: KeyPair
    ) async throws -> StatelessSwapResult {
        callCount += 1
        return try nextResult.get()
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
