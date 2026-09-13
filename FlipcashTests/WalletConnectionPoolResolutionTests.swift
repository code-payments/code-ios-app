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

    /// `sha256("account:LiquidityPool")[0..8]` — the real Anchor discriminator for this
    /// account. `PoolAccount` rejects data that doesn't start with these bytes.
    private nonisolated static let poolAccountDiscriminator: [UInt8] = [66, 38, 17, 64, 188, 80, 68, 129]

    /// Fee recipient sits at offset 136: discriminator (8) + operations_authority (32)
    /// + pause_authority (32) + two unnamed pubkeys (32 each) that the published IDL
    /// does not describe.
    private nonisolated static func poolAccountData(feeRecipient: [UInt8]) -> Data {
        var data = Data(Self.poolAccountDiscriminator)
        data.append(Data(repeating: 0, count: 32 + 32 + 32 + 32))
        data.append(Data(feeRecipient))
        return data
    }

    private static func makeConnection(rpc: MockSolanaRPC) -> WalletConnection {
        WalletConnection(owner: .mock, rpc: rpc, preferredLiquidityPool: { .unknown })
    }

    @Test(
        "Legacy flag values resolve to the legacy pool without touching the network",
        arguments: [UserFlags.UsdcLiquidityPool.unknown, .flipcash]
    )
    func resolveFundSwapPool_legacyFlag_returnsLegacyPoolWithoutFetching(
        flag: UserFlags.UsdcLiquidityPool
    ) async throws {
        let rpc = MockSolanaRPC()

        let pool = try await Self.makeConnection(rpc: rpc).resolveFundSwapPool(flag)

        #expect(pool == .usdf)
        #expect(rpc.accountDataRequests.isEmpty)
    }

    @Test("Coinbase flag fetches the pool account and parses its fee recipient")
    func resolveFundSwapPool_coinbaseFlag_parsesFeeRecipientFromPoolAccount() async throws {
        let feeRecipientBytes = [UInt8](repeating: 7, count: 32)
        let rpc = MockSolanaRPC()
        rpc.accountDataHandler = { _ in Self.poolAccountData(feeRecipient: feeRecipientBytes) }

        let pool = try await Self.makeConnection(rpc: rpc).resolveFundSwapPool(.coinbaseStableSwapper)

        let expectedPoolAddress = try #require(CoinbaseStableSwapperProgram.derivePoolAddress()).publicKey
        #expect(rpc.accountDataRequests == [expectedPoolAddress])
        #expect(pool == .coinbaseStableSwapper(feeRecipient: try PublicKey(feeRecipientBytes)))
    }

    @Test("Missing pool account fails the resolution instead of falling back")
    func resolveFundSwapPool_missingPoolAccount_throwsPoolAccountUnavailable() async throws {
        let rpc = MockSolanaRPC()
        rpc.accountDataHandler = { _ in nil }

        await #expect(throws: WalletConnection.Error.poolAccountUnavailable) {
            _ = try await Self.makeConnection(rpc: rpc).resolveFundSwapPool(.coinbaseStableSwapper)
        }
    }

    @Test("An RPC failure propagates instead of being swallowed")
    func resolveFundSwapPool_rpcFailure_rethrows() async throws {
        let rpc = MockSolanaRPC()
        rpc.accountDataHandler = { _ in throw URLError(.notConnectedToInternet) }

        await #expect(throws: URLError.self) {
            _ = try await Self.makeConnection(rpc: rpc).resolveFundSwapPool(.coinbaseStableSwapper)
        }
    }
}
