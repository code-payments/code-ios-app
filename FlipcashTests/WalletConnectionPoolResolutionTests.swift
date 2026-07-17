//
//  WalletConnectionPoolResolutionTests.swift
//  FlipcashTests
//

import Foundation
import Testing
@testable import Flipcash
import FlipcashCore

@MainActor
@Suite("WalletConnection.resolveFundSwapPool")
struct WalletConnectionPoolResolutionTests {

    private nonisolated static func poolAccountData(feeRecipient: [UInt8]) -> Data {
        var data = Data(repeating: 0, count: 8 + 32 + 32)
        data.append(Data(feeRecipient))
        return data
    }

    @Test(
        "Legacy flag values resolve to the legacy pool without touching the network",
        arguments: [UserFlags.UsdcLiquidityPool.unknown, .flipcash]
    )
    func resolveFundSwapPool_legacyFlag_returnsLegacyPoolWithoutFetching(
        flag: UserFlags.UsdcLiquidityPool
    ) async throws {
        let rpc = MockSolanaRPC()
        let fetchCount = CallCounter()
        rpc.accountDataHandler = { _ in
            fetchCount.increment()
            return nil
        }

        let connection = WalletConnection(owner: .mock, rpc: rpc)
        let pool = try await connection.resolveFundSwapPool(flag)

        #expect(pool == .usdf(.usdf))
        #expect(fetchCount.value == 0)
    }

    @Test("Coinbase flag fetches the pool account and parses its fee recipient")
    func resolveFundSwapPool_coinbaseFlag_parsesFeeRecipientFromPoolAccount() async throws {
        let feeRecipientBytes = [UInt8](repeating: 7, count: 32)
        let requestedAccount = RequestedAccountBox()
        let rpc = MockSolanaRPC()
        rpc.accountDataHandler = { account in
            requestedAccount.store(account)
            return Self.poolAccountData(feeRecipient: feeRecipientBytes)
        }

        let connection = WalletConnection(owner: .mock, rpc: rpc)
        let pool = try await connection.resolveFundSwapPool(.coinbaseStableSwapper)

        let expectedPoolAddress = try #require(CoinbaseStableSwapperProgram.derivePoolAddress()).publicKey
        #expect(requestedAccount.value == expectedPoolAddress)
        #expect(pool == .coinbaseStableSwapper(feeRecipient: try PublicKey(feeRecipientBytes)))
    }

    @Test("Missing pool account fails the resolution instead of falling back")
    func resolveFundSwapPool_missingPoolAccount_throwsPoolAccountUnavailable() async throws {
        let rpc = MockSolanaRPC()
        rpc.accountDataHandler = { _ in nil }

        let connection = WalletConnection(owner: .mock, rpc: rpc)
        await #expect(throws: WalletConnection.Error.poolAccountUnavailable) {
            _ = try await connection.resolveFundSwapPool(.coinbaseStableSwapper)
        }
    }

    @Test("Malformed pool account data fails the resolution instead of falling back")
    func resolveFundSwapPool_malformedPoolAccount_throwsPoolAccountUnavailable() async throws {
        let rpc = MockSolanaRPC()
        rpc.accountDataHandler = { _ in Data(repeating: 0, count: 10) }

        let connection = WalletConnection(owner: .mock, rpc: rpc)
        await #expect(throws: WalletConnection.Error.poolAccountUnavailable) {
            _ = try await connection.resolveFundSwapPool(.coinbaseStableSwapper)
        }
    }

    @Test("An RPC failure propagates instead of being swallowed")
    func resolveFundSwapPool_rpcFailure_rethrows() async throws {
        let rpc = MockSolanaRPC()
        rpc.accountDataHandler = { _ in throw URLError(.notConnectedToInternet) }

        let connection = WalletConnection(owner: .mock, rpc: rpc)
        await #expect(throws: URLError.self) {
            _ = try await connection.resolveFundSwapPool(.coinbaseStableSwapper)
        }
    }
}

/// Minimal thread-safe capture boxes for values observed inside `@Sendable`
/// mock handlers.
private final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}

private final class RequestedAccountBox: @unchecked Sendable {
    private let lock = NSLock()
    private var account: PublicKey?

    var value: PublicKey? {
        lock.lock()
        defer { lock.unlock() }
        return account
    }

    func store(_ value: PublicKey) {
        lock.lock()
        account = value
        lock.unlock()
    }
}
