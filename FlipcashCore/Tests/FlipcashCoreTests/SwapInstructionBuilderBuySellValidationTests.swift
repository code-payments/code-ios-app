//
//  SwapInstructionBuilderBuySellValidationTests.swift
//  FlipcashCoreTests
//

import Foundation
import Testing
@testable import FlipcashCore

@Suite("SwapInstructionBuilder buy/sell server-data validation")
struct SwapInstructionBuilderBuySellValidationTests {

    // MARK: - Fixtures

    private static func testKey(_ seed: Int) -> PublicKey {
        try! PublicKey([UInt8](repeating: UInt8(seed), count: 32))
    }

    private static let nonce         = testKey(2)
    private static let authority     = testKey(4)
    private static let swapAuthority = testKey(5)

    private static let validLaunchpadMetadata = LaunchpadMetadata(
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

    private static func makeMint(
        address: PublicKey,
        symbol: String,
        vmMetadata: VMMetadata?,
        launchpadMetadata: LaunchpadMetadata?
    ) -> MintMetadata {
        MintMetadata(
            address: address,
            decimals: 10,
            name: "Test Token",
            symbol: symbol,
            description: "",
            imageURL: nil,
            vmMetadata: vmMetadata,
            launchpadMetadata: launchpadMetadata
        )
    }

    private static let validTargetMint = makeMint(
        address: testKey(10),
        symbol: "TEST",
        vmMetadata: VMMetadata(vm: testKey(11), authority: testKey(12), lockDurationInDays: 21),
        launchpadMetadata: validLaunchpadMetadata
    )

    private static func makeCoreMint(lockDurationInDays: Int = 21) -> MintMetadata {
        makeMint(
            address: testKey(20),
            symbol: "CORE",
            vmMetadata: VMMetadata(vm: testKey(21), authority: testKey(22), lockDurationInDays: lockDurationInDays),
            launchpadMetadata: nil
        )
    }

    private static func makeServerParameters(memoryIndex: UInt32 = 0) -> SwapResponseServerParameters {
        SwapResponseServerParameters(
            kind: .stateful(.init(
                payer: testKey(1),
                alts: [],
                computeUnitLimit: 200_000,
                computeUnitPrice: 1_000,
                memoValue: "test",
                memoryAccount: testKey(6),
                memoryIndex: memoryIndex
            ))
        )
    }

    private static func makeNewCurrencyParams(
        vmLockDurationInDays: UInt32,
        sellFeeBps: UInt32
    ) -> SwapResponseServerParameters.ReserveNewCurrency {
        SwapResponseServerParameters.ReserveNewCurrency(
            payer: testKey(1),
            nonce: testKey(2),
            blockhash: try! Hash([UInt8](repeating: 3, count: 32)),
            alts: [],
            computeUnitLimit: 200_000,
            computeUnitPrice: 1_000,
            memoValue: "test",
            authority: authority,
            name: "Test Token",
            symbol: "TEST",
            seed: testKey(15),
            sellFeeBps: sellFeeBps,
            vmLockDurationInDays: vmLockDurationInDays,
            feeDestination: testKey(7)
        )
    }

    private func buildBuy(
        serverParameters: SwapResponseServerParameters,
        coreMint: MintMetadata,
        targetMint: MintMetadata
    ) throws -> [Instruction] {
        try SwapInstructionBuilder.buildBuyInstructions(
            serverParameters: serverParameters,
            nonce: Self.nonce,
            authority: Self.authority,
            swapAuthority: Self.swapAuthority,
            coreMintMetadata: coreMint,
            targetMintMetadata: targetMint,
            amount: 1_000_000,
            minOutput: 0,
            maxSlippage: 0
        )
    }

    private func buildSell(
        serverParameters: SwapResponseServerParameters,
        sourceMint: MintMetadata,
        coreMint: MintMetadata
    ) throws -> [Instruction] {
        try SwapInstructionBuilder.buildSellInstructions(
            serverParameters: serverParameters,
            nonce: Self.nonce,
            authority: Self.authority,
            swapAuthority: Self.swapAuthority,
            sourceMintMetadata: sourceMint,
            coreMintMetadata: coreMint,
            amount: 1_000_000,
            minOutput: 0,
            maxSlippage: 0
        )
    }

    // MARK: - Missing metadata

    @Test("Buy throws missingMintMetadata when the target mint has no VM metadata")
    func buy_targetMissingVMMetadata_throws() {
        let target = Self.makeMint(
            address: Self.testKey(10),
            symbol: "TEST",
            vmMetadata: nil,
            launchpadMetadata: Self.validLaunchpadMetadata
        )

        #expect(throws: SwapTransactionBuildError.missingMintMetadata(symbol: "TEST")) {
            try self.buildBuy(
                serverParameters: Self.makeServerParameters(),
                coreMint: Self.makeCoreMint(),
                targetMint: target
            )
        }
    }

    @Test("Buy throws missingMintMetadata when the target mint has no launchpad metadata")
    func buy_targetMissingLaunchpadMetadata_throws() {
        let target = Self.makeMint(
            address: Self.testKey(10),
            symbol: "TEST",
            vmMetadata: VMMetadata(vm: Self.testKey(11), authority: Self.testKey(12), lockDurationInDays: 21),
            launchpadMetadata: nil
        )

        #expect(throws: SwapTransactionBuildError.missingMintMetadata(symbol: "TEST")) {
            try self.buildBuy(
                serverParameters: Self.makeServerParameters(),
                coreMint: Self.makeCoreMint(),
                targetMint: target
            )
        }
    }

    @Test("Sell throws missingMintMetadata when the source mint has no VM metadata")
    func sell_sourceMissingVMMetadata_throws() {
        let source = Self.makeMint(
            address: Self.testKey(10),
            symbol: "TEST",
            vmMetadata: nil,
            launchpadMetadata: Self.validLaunchpadMetadata
        )

        #expect(throws: SwapTransactionBuildError.missingMintMetadata(symbol: "TEST")) {
            try self.buildSell(
                serverParameters: Self.makeServerParameters(),
                sourceMint: source,
                coreMint: Self.makeCoreMint()
            )
        }
    }

    @Test("Sell throws missingMintMetadata when the source mint has no launchpad metadata")
    func sell_sourceMissingLaunchpadMetadata_throws() {
        let source = Self.makeMint(
            address: Self.testKey(10),
            symbol: "TEST",
            vmMetadata: VMMetadata(vm: Self.testKey(11), authority: Self.testKey(12), lockDurationInDays: 21),
            launchpadMetadata: nil
        )

        #expect(throws: SwapTransactionBuildError.missingMintMetadata(symbol: "TEST")) {
            try self.buildSell(
                serverParameters: Self.makeServerParameters(),
                sourceMint: source,
                coreMint: Self.makeCoreMint()
            )
        }
    }

    // MARK: - Server-parameter range validation

    @Test("Buy throws invalidServerParameter when memoryIndex exceeds UInt16.max")
    func buy_memoryIndexOverflow_throws() {
        #expect(throws: SwapTransactionBuildError.invalidServerParameter("memoryIndex")) {
            try self.buildBuy(
                serverParameters: Self.makeServerParameters(memoryIndex: UInt32(UInt16.max) + 1),
                coreMint: Self.makeCoreMint(),
                targetMint: Self.validTargetMint
            )
        }
    }

    @Test("Sell throws invalidServerParameter when memoryIndex exceeds UInt16.max")
    func sell_memoryIndexOverflow_throws() {
        #expect(throws: SwapTransactionBuildError.invalidServerParameter("memoryIndex")) {
            try self.buildSell(
                serverParameters: Self.makeServerParameters(memoryIndex: UInt32(UInt16.max) + 1),
                sourceMint: Self.validTargetMint,
                coreMint: Self.makeCoreMint()
            )
        }
    }

    @Test("Buy throws when the core mint lock duration cannot derive swap accounts")
    func buy_coreMint300DayLockDuration_throws() {
        #expect(throws: SwapTransactionBuildError.missingMintMetadata(symbol: "CORE")) {
            try self.buildBuy(
                serverParameters: Self.makeServerParameters(),
                coreMint: Self.makeCoreMint(lockDurationInDays: 300),
                targetMint: Self.validTargetMint
            )
        }
    }

    // MARK: - New-currency launch validation

    @Test("New-currency launch throws invalidServerParameter for a 300-day VM lock duration")
    func newCurrency_vmLockDurationOverflow_throws() {
        #expect(throws: SwapTransactionBuildError.invalidServerParameter("vmLockDurationInDays")) {
            try SwapInstructionBuilder.newCurrencyLaunch(
                serverParams: Self.makeNewCurrencyParams(vmLockDurationInDays: 300, sellFeeBps: 100),
                authority: Self.authority,
                swapAmount: 1_000_000,
                feeAmount: 50_000
            )
        }
    }

    @Test("New-currency launch throws invalidServerParameter when sellFeeBps exceeds UInt16.max")
    func newCurrency_sellFeeBpsOverflow_throws() {
        #expect(throws: SwapTransactionBuildError.invalidServerParameter("sellFeeBps")) {
            try SwapInstructionBuilder.newCurrencyLaunch(
                serverParams: Self.makeNewCurrencyParams(vmLockDurationInDays: 21, sellFeeBps: 70_000),
                authority: Self.authority,
                swapAmount: 1_000_000,
                feeAmount: 50_000
            )
        }
    }

    // MARK: - Happy paths

    @Test("Buy with valid metadata and parameters produces 9 instructions")
    func buy_happyPath_produces9Instructions() throws {
        let instructions = try buildBuy(
            serverParameters: Self.makeServerParameters(),
            coreMint: Self.makeCoreMint(),
            targetMint: Self.validTargetMint
        )

        #expect(instructions.count == 9)
    }

    @Test("Sell with valid metadata and parameters produces 9 instructions")
    func sell_happyPath_produces9Instructions() throws {
        let instructions = try buildSell(
            serverParameters: Self.makeServerParameters(),
            sourceMint: Self.validTargetMint,
            coreMint: Self.makeCoreMint()
        )

        #expect(instructions.count == 9)
    }
}
