//
//  TransactionBuilderSwapErrorTests.swift
//  FlipcashCoreTests
//

import Foundation
import Testing
@testable import FlipcashCore

@Suite("TransactionBuilder.swap server-parameter validation")
struct TransactionBuilderSwapErrorTests {

    // MARK: - Fixtures

    private static func testKey(_ seed: Int) -> PublicKey {
        try! PublicKey([UInt8](repeating: UInt8(seed), count: 32))
    }

    private static let payer         = testKey(1)
    private static let nonce         = testKey(2)
    private static let blockhash     = try! Hash([UInt8](repeating: 3, count: 32))
    private static let authority     = testKey(4)
    private static let swapAuthority = testKey(5)

    private static let launchpadMint = MintMetadata(
        address: testKey(10),
        decimals: 10,
        name: "Test Token",
        symbol: "TEST",
        description: "",
        imageURL: nil,
        vmMetadata: VMMetadata(
            vm: testKey(11),
            authority: testKey(12),
            lockDurationInDays: 21
        ),
        launchpadMetadata: LaunchpadMetadata(
            currencyConfig: testKey(13),
            liquidityPool: testKey(14),
            seed: testKey(15),
            authority: testKey(12),
            mintVault: testKey(16),
            coreMintVault: testKey(17),
            coreMintFees: nil,
            supplyFromBonding: 50_000,
            sellFeeBps: 100
        )
    )

    private static let verifiedMetadata = VerifiedSwapMetadata(
        clientParameters: VerifiedSwapMetadata.ClientParameters(
            id: .generate(),
            fromMint: .usdf,
            toMint: testKey(10),
            amount: TokenAmount(quarks: 1_000_000, mint: .usdf),
            fundingSource: .submitIntent(id: testKey(18))
        ),
        serverParameters: VerifiedSwapMetadata.ServerParameters(
            nonce: nonce,
            blockhash: blockhash
        )
    )

    private static func makeStatefulParameters() -> SwapResponseServerParameters {
        SwapResponseServerParameters(
            kind: .stateful(.init(
                payer: payer,
                alts: [],
                computeUnitLimit: 200_000,
                computeUnitPrice: 1_000,
                memoValue: "test",
                memoryAccount: testKey(6),
                memoryIndex: 0
            ))
        )
    }

    private static func makeNewCurrencyParameters() -> SwapResponseServerParameters {
        SwapResponseServerParameters(
            kind: .newCurrency(.init(
                payer: payer,
                nonce: nonce,
                blockhash: blockhash,
                alts: [],
                computeUnitLimit: 200_000,
                computeUnitPrice: 1_000,
                memoValue: "test",
                authority: authority,
                name: "Test Token",
                symbol: "TEST",
                seed: testKey(15),
                sellFeeBps: 100,
                vmLockDurationInDays: 21,
                feeDestination: testKey(7)
            ))
        )
    }

    private static func makeStablecoinParameters() -> SwapResponseServerParameters {
        SwapResponseServerParameters(
            kind: .stablecoin(.init(
                payer: payer,
                nonce: nonce,
                blockhash: blockhash,
                alts: [],
                computeUnitLimit: 150_000,
                computeUnitPrice: 10_000,
                memoValue: "coinbase_stable_swapper_v0",
                feeDestination: testKey(7),
                poolFeeRecipient: testKey(8)
            ))
        )
    }

    private func buildSwap(
        responseParams: SwapResponseServerParameters,
        direction: SwapDirection
    ) throws -> SolanaTransaction {
        try TransactionBuilder.swap(
            responseParams: responseParams,
            metadata: Self.verifiedMetadata,
            authority: Self.authority,
            swapAuthority: Self.swapAuthority,
            direction: direction,
            amount: 1_000_000
        )
    }

    // MARK: - Tests

    @Test("New-currency parameters with a buy direction throw unsupportedServerParameters")
    func newCurrencyParameters_buyDirection_throwsUnsupported() {
        #expect(throws: SwapTransactionBuildError.unsupportedServerParameters) {
            try self.buildSwap(
                responseParams: Self.makeNewCurrencyParameters(),
                direction: .buy(mint: Self.launchpadMint)
            )
        }
    }

    @Test("Stablecoin parameters with a buy direction throw unsupportedServerParameters")
    func stablecoinParameters_buyDirection_throwsUnsupported() {
        #expect(throws: SwapTransactionBuildError.unsupportedServerParameters) {
            try self.buildSwap(
                responseParams: Self.makeStablecoinParameters(),
                direction: .buy(mint: Self.launchpadMint)
            )
        }
    }

    @Test("Stateful parameters with a withdraw direction throw unsupportedServerParameters")
    func statefulParameters_withdrawDirection_throwsUnsupported() {
        #expect(throws: SwapTransactionBuildError.unsupportedServerParameters) {
            try self.buildSwap(
                responseParams: Self.makeStatefulParameters(),
                direction: .withdraw(mint: .usdc)
            )
        }
    }

    @Test("Stateful parameters with a buy direction build a 9-instruction transaction")
    func statefulParameters_buyDirection_buildsTransaction() throws {
        let transaction = try buildSwap(
            responseParams: Self.makeStatefulParameters(),
            direction: .buy(mint: Self.launchpadMint)
        )

        #expect(transaction.message.instructions.count == 9)
    }

    @Test("Stateful parameters with a swap direction build a 12-instruction transaction")
    func statefulParameters_swapDirection_buildsTransaction() throws {
        let paymentMint = MintMetadata(
            address: Self.testKey(20),
            decimals: 10,
            name: "Pay Token",
            symbol: "PAY",
            description: "",
            imageURL: nil,
            vmMetadata: VMMetadata(
                vm: Self.testKey(21),
                authority: Self.testKey(22),
                lockDurationInDays: 21
            ),
            launchpadMetadata: LaunchpadMetadata(
                currencyConfig: Self.testKey(23),
                liquidityPool: Self.testKey(24),
                seed: Self.testKey(25),
                authority: Self.testKey(22),
                mintVault: Self.testKey(26),
                coreMintVault: Self.testKey(27),
                coreMintFees: nil,
                supplyFromBonding: 50_000,
                sellFeeBps: 100
            )
        )

        let transaction = try buildSwap(
            responseParams: Self.makeStatefulParameters(),
            direction: .swap(from: paymentMint, to: Self.launchpadMint)
        )

        #expect(transaction.message.instructions.count == 12)
    }

    @Test("New-currency parameters with a swap direction throw unsupportedServerParameters")
    func newCurrencyParameters_swapDirection_throwsUnsupported() {
        #expect(throws: SwapTransactionBuildError.unsupportedServerParameters) {
            try self.buildSwap(
                responseParams: Self.makeNewCurrencyParameters(),
                direction: .swap(from: Self.launchpadMint, to: Self.launchpadMint)
            )
        }
    }
}
