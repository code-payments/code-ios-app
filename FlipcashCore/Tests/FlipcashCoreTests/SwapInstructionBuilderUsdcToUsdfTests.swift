//
//  SwapInstructionBuilderUsdcToUsdfTests.swift
//  FlipcashCoreTests
//

import Foundation
import Testing
@testable import FlipcashCore

@Suite("SwapInstructionBuilder.buildUsdcToUsdfSwapInstructions")
struct SwapInstructionBuilderUsdcToUsdfTests {

    // MARK: - Fixtures

    /// 32-byte pubkey filled entirely with the seed byte. Mirrors the existing
    /// UsdfToUsdc test suite.
    private static func testKey(_ seed: Int) -> PublicKey {
        try! PublicKey([UInt8](repeating: UInt8(seed), count: 32))
    }

    private static let sender  = testKey(1)
    private static let owner   = testKey(2)
    private static let swapId  = testKey(3)
    private static let amount: UInt64 = 20_000_000

    private static func makeInstructions(
        amount: UInt64 = SwapInstructionBuilderUsdcToUsdfTests.amount
    ) -> [Instruction] {
        SwapInstructionBuilder.buildUsdcToUsdfSwapInstructions(
            sender: sender,
            owner: owner,
            amount: amount,
            pool: .usdf,
            swapId: swapId
        )
    }

    // MARK: - Instruction count

    @Test("Produces exactly 8 instructions")
    func produces8Instructions() {
        #expect(Self.makeInstructions().count == 8)
    }

    // MARK: - Instruction order and programs

    @Test("Instruction 0 is ComputeBudget SetComputeUnitLimit")
    func instruction0_isComputeUnitLimit() {
        let ix = Self.makeInstructions()[0]
        #expect(ix.program == ComputeBudgetProgram.address)
        #expect(ix.data.first == ComputeBudgetProgram.Command.setComputeUnitLimit.rawValue)
    }

    @Test("Instruction 1 is ComputeBudget SetComputeUnitPrice")
    func instruction1_isComputeUnitPrice() {
        let ix = Self.makeInstructions()[1]
        #expect(ix.program == ComputeBudgetProgram.address)
        #expect(ix.data.first == ComputeBudgetProgram.Command.setComputeUnitPrice.rawValue)
    }

    @Test("Instruction 2 is AssociatedTokenProgram CreateIdempotent for sender's USDF ATA")
    func instruction2_createsSenderUsdfATA() {
        let ix = Self.makeInstructions()[2]
        // account layout: [payer (w,s), ata (w), owner, mint, system, token, rent]
        #expect(ix.program == AssociatedTokenProgram.address)
        #expect(ix.accounts[0].publicKey == Self.sender)
        #expect(ix.accounts[0].isSigner == true)
        #expect(ix.accounts[2].publicKey == Self.sender)
        #expect(ix.accounts[3].publicKey == .usdf)
    }

    @Test("Instruction 3 is AssociatedTokenProgram CreateIdempotent for swap PDA's USDF ATA")
    func instruction3_createsSwapPdaUsdfATA() {
        let ix = Self.makeInstructions()[3]
        let pdaPublicKey = MintMetadata.usdf.timelockSwapAccounts(owner: Self.owner)!.pda.publicKey
        #expect(ix.program == AssociatedTokenProgram.address)
        #expect(ix.accounts[0].publicKey == Self.sender)
        #expect(ix.accounts[2].publicKey == pdaPublicKey)
        #expect(ix.accounts[3].publicKey == .usdf)
    }

    @Test("Instruction 4 is AssociatedTokenProgram CreateIdempotent for sender's USDC ATA")
    func instruction4_createsSenderUsdcATA() {
        let ix = Self.makeInstructions()[4]
        #expect(ix.program == AssociatedTokenProgram.address)
        #expect(ix.accounts[0].publicKey == Self.sender)
        #expect(ix.accounts[0].isSigner == true)
        #expect(ix.accounts[2].publicKey == Self.sender)
        #expect(ix.accounts[3].publicKey == .usdc)
    }

    @Test("Instruction 5 is Memo carrying the swap id")
    func instruction5_isMemoWithSwapId() {
        let ix = Self.makeInstructions()[5]
        #expect(ix.program == MemoProgram.address)
        #expect(ix.data == Data(Self.swapId.base58.utf8))
    }

    @Test("Instruction 6 is UsdfProgram Swap")
    func instruction6_isUsdfSwap() {
        #expect(Self.makeInstructions()[6].program == UsdfProgram.address)
    }

    @Test("Instruction 7 is TokenProgram Transfer to swap PDA's USDF ATA")
    func instruction7_isTransferToSwapPdaAta() {
        let ix = Self.makeInstructions()[7]
        let pdaAta = MintMetadata.usdf.timelockSwapAccounts(owner: Self.owner)!.ata.publicKey
        let senderUsdfAta = PublicKey.deriveAssociatedAccount(from: Self.sender, mint: .usdf)!.publicKey
        #expect(ix.program == TokenProgram.address)
        // account layout: [source (w), destination (w), owner (s)]
        #expect(ix.accounts[0].publicKey == senderUsdfAta)
        #expect(ix.accounts[1].publicKey == pdaAta)
        #expect(ix.accounts[2].publicKey == Self.sender)
        #expect(ix.accounts[2].isSigner == true)
    }

    // MARK: - Usdf::Swap account verification

    @Test("Swap user (account 0) is sender and isSigner")
    func swap_userIsSender() {
        let ix = Self.makeInstructions()[6]
        #expect(ix.accounts[0].publicKey == Self.sender)
        #expect(ix.accounts[0].isSigner == true)
    }

    @Test("Swap pool, vaults match LiquidityPool.usdf")
    func swap_poolAccounts() {
        let ix = Self.makeInstructions()[6]
        #expect(ix.accounts[1].publicKey == LiquidityPool.usdf.address)
        #expect(ix.accounts[2].publicKey == LiquidityPool.usdf.usdfVault)
        #expect(ix.accounts[3].publicKey == LiquidityPool.usdf.otherVault)
    }

    @Test("Swap userUsdfToken (account 4) is sender's USDF ATA")
    func swap_userUsdfToken() {
        let ix = Self.makeInstructions()[6]
        let expected = PublicKey.deriveAssociatedAccount(from: Self.sender, mint: .usdf)!.publicKey
        #expect(ix.accounts[4].publicKey == expected)
    }

    @Test("Swap userOtherToken (account 5) is the same USDC ATA address that instruction 4 creates")
    func swap_userOtherToken() {
        let instructions = Self.makeInstructions()
        let createUsdcAta = instructions[4].accounts[1].publicKey
        #expect(instructions[6].accounts[5].publicKey == createUsdcAta)
    }

    // MARK: - Discriminator + data layout

    @Test("Swap data: command byte + amount(8 LE) + usdfToOther(1 byte = 0)")
    func swap_dataLayout() {
        let ix = Self.makeInstructions(amount: 20_000_000)[6]
        #expect(ix.data.count == 1 + 8 + 1)
        #expect(ix.data.first == UsdfProgram.Command.swap.rawValue)
        #expect(UInt64(bytes: Array(ix.data[1..<9])) == 20_000_000)
        #expect(ix.data.last == 0) // usdfToOther = false (USDC → USDF direction)
    }
}
