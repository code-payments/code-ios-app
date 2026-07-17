//
//  SwapInstructionBuilderSwapTests.swift
//  FlipcashCoreTests
//

import Foundation
import Testing
@testable import FlipcashCore

@Suite("SwapInstructionBuilder launchpad→launchpad swap")
struct SwapInstructionBuilderSwapTests {

    private static func key(_ seed: UInt8) -> PublicKey {
        try! PublicKey([UInt8](repeating: seed, count: 32))
    }

    private static let payer         = key(1)
    private static let nonce         = key(2)
    private static let authority     = key(4)
    private static let swapAuthority = key(5)
    private static let memoryAccount = key(6)

    private static func makeLaunchpadMint(base: UInt8, symbol: String) -> MintMetadata {
        MintMetadata(
            address: key(base),
            decimals: 10,
            name: symbol,
            symbol: symbol,
            description: "",
            imageURL: nil,
            vmMetadata: VMMetadata(
                vm: key(base + 1),
                authority: key(base + 2),
                lockDurationInDays: 21
            ),
            launchpadMetadata: LaunchpadMetadata(
                currencyConfig: key(base + 3),
                liquidityPool: key(base + 4),
                seed: key(base + 5),
                authority: key(base + 2),
                mintVault: key(base + 6),
                coreMintVault: key(base + 7),
                coreMintFees: nil,
                supplyFromBonding: 50_000,
                sellFeeBps: 100
            )
        )
    }

    private static let sourceMint = makeLaunchpadMint(base: 10, symbol: "PAY")
    private static let targetMint = makeLaunchpadMint(base: 30, symbol: "BUY")

    private static func makeServerParameters(memoryIndex: UInt32 = 3) -> SwapResponseServerParameters {
        SwapResponseServerParameters(
            kind: .stateful(.init(
                payer: payer,
                alts: [],
                computeUnitLimit: 250_000,
                computeUnitPrice: 10_000,
                memoValue: "buy_sell_v0",
                memoryAccount: memoryAccount,
                memoryIndex: memoryIndex
            ))
        )
    }

    private func build(amount: UInt64 = 1_000_000) throws -> [Instruction] {
        try SwapInstructionBuilder.buildSwapInstructions(
            serverParameters: Self.makeServerParameters(),
            nonce: Self.nonce,
            authority: Self.authority,
            swapAuthority: Self.swapAuthority,
            sourceMintMetadata: Self.sourceMint,
            targetMintMetadata: Self.targetMint,
            coreMintMetadata: .usdf,
            amount: amount
        )
    }

    @Test("Builds the 12-instruction launchpad→launchpad format in server order")
    func instructionOrder() throws {
        let instructions = try build()

        #expect(instructions.count == 12)
        #expect(instructions[0].program == SystemProgram.address)
        #expect(instructions[1].program == ComputeBudgetProgram.address)
        #expect(instructions[2].program == ComputeBudgetProgram.address)
        #expect(instructions[3].program == MemoProgram.address)
        #expect(instructions[4].program == AssociatedTokenProgram.address)
        #expect(instructions[5].program == AssociatedTokenProgram.address)
        #expect(instructions[6].program == VMProgram.address)
        #expect(instructions[7].program == CurrencyCreatorProgram.address)
        #expect(instructions[8].program == CurrencyCreatorProgram.address)
        #expect(instructions[9].program == TokenProgram.address)
        #expect(instructions[10].program == TokenProgram.address)
        #expect(instructions[11].program == VMProgram.address)
    }

    @Test("Temp ATA creations are core mint first, then source mint")
    func tempAtaOrder() throws {
        let instructions = try build()

        let coreAta = try AssociatedTokenProgram.CreateIdempotent(instruction: instructions[4])
        #expect(coreAta.mint == MintMetadata.usdf.address)
        #expect(coreAta.owner == Self.swapAuthority)
        #expect(coreAta.subsidizer == Self.payer)

        let sourceAta = try AssociatedTokenProgram.CreateIdempotent(instruction: instructions[5])
        #expect(sourceAta.mint == Self.sourceMint.address)
        #expect(sourceAta.owner == Self.swapAuthority)
    }

    @Test("TransferForSwap moves the swap amount into the temp source ATA")
    func transferLeg() throws {
        let instructions = try build(amount: 777)

        let sourceAta = try AssociatedTokenProgram.CreateIdempotent(instruction: instructions[5])
        let transfer = try VMProgram.TransferForSwap(instruction: instructions[6])

        #expect(transfer.amount == 777)
        #expect(transfer.vm == Self.sourceMint.vmMetadata?.vm)
        #expect(transfer.swapper == Self.authority)
        #expect(transfer.destination == sourceAta.address)
    }

    @Test("SellTokens sells the full amount with minAmountOut 0 into the temp core ATA")
    func sellLeg() throws {
        let instructions = try build(amount: 777)

        let coreAta = try AssociatedTokenProgram.CreateIdempotent(instruction: instructions[4])
        let sourceAta = try AssociatedTokenProgram.CreateIdempotent(instruction: instructions[5])
        let sell = try CurrencyCreatorProgram.SellTokens(instruction: instructions[7])

        #expect(sell.inAmount == 777)
        #expect(sell.minAmountOut == 0)
        #expect(sell.seller == Self.swapAuthority)
        #expect(sell.pool == Self.sourceMint.launchpadMetadata?.liquidityPool)
        #expect(sell.targetMint == Self.sourceMint.address)
        #expect(sell.baseMint == MintMetadata.usdf.address)
        #expect(sell.vaultTarget == Self.sourceMint.launchpadMetadata?.mintVault)
        #expect(sell.vaultBase == Self.sourceMint.launchpadMetadata?.coreMintVault)
        #expect(sell.sellerTarget == sourceAta.address)
        #expect(sell.sellerBase == coreAta.address)
    }

    @Test("BuyAndDepositIntoVm is the unlimited-buy form funded by the temp core ATA")
    func buyLeg() throws {
        let instructions = try build()

        let coreAta = try AssociatedTokenProgram.CreateIdempotent(instruction: instructions[4])
        let buy = try CurrencyCreatorProgram.BuyAndDepositIntoVm(instruction: instructions[8])

        #expect(buy.amount == 0)
        #expect(buy.minOutAmount == 0)
        #expect(buy.vmMemoryIndex == 3)
        #expect(buy.buyer == Self.swapAuthority)
        #expect(buy.pool == Self.targetMint.launchpadMetadata?.liquidityPool)
        #expect(buy.targetMint == Self.targetMint.address)
        #expect(buy.baseMint == MintMetadata.usdf.address)
        #expect(buy.buyerBase == coreAta.address)
        #expect(buy.vmAuthority == Self.targetMint.vmMetadata?.authority)
        #expect(buy.vm == Self.targetMint.vmMetadata?.vm)
        #expect(buy.vmMemory == Self.memoryAccount)
        #expect(buy.vtaOwner == Self.authority)
    }

    @Test("Close order is temp core ATA, temp source ATA, then source swap account")
    func closeOrder() throws {
        let instructions = try build()

        let coreAta = try AssociatedTokenProgram.CreateIdempotent(instruction: instructions[4])
        let sourceAta = try AssociatedTokenProgram.CreateIdempotent(instruction: instructions[5])

        let closeCore = try TokenProgram.CloseAccount(instruction: instructions[9])
        #expect(closeCore.account == coreAta.address)
        #expect(closeCore.destination == Self.payer)
        #expect(closeCore.owner == Self.swapAuthority)

        let closeSource = try TokenProgram.CloseAccount(instruction: instructions[10])
        #expect(closeSource.account == sourceAta.address)

        let closeSwap = try VMProgram.CloseSwapAccountIfEmpty(instruction: instructions[11])
        #expect(closeSwap.vm == Self.sourceMint.vmMetadata?.vm)
        #expect(closeSwap.swapper == Self.authority)
    }

    @Test("Missing launchpad metadata on either mint throws missingMintMetadata")
    func missingMetadata_throws() {
        let bareTarget = MintMetadata(
            address: Self.targetMint.address,
            decimals: 10,
            name: "BUY",
            symbol: "BUY",
            description: "",
            imageURL: nil,
            vmMetadata: Self.targetMint.vmMetadata,
            launchpadMetadata: nil
        )

        #expect(throws: SwapTransactionBuildError.missingMintMetadata(symbol: "BUY")) {
            try SwapInstructionBuilder.buildSwapInstructions(
                serverParameters: Self.makeServerParameters(),
                nonce: Self.nonce,
                authority: Self.authority,
                swapAuthority: Self.swapAuthority,
                sourceMintMetadata: Self.sourceMint,
                targetMintMetadata: bareTarget,
                coreMintMetadata: .usdf,
                amount: 1
            )
        }
    }
}
