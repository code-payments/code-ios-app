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

    private static func testKey(_ seed: Int) -> PublicKey {
        try! PublicKey([UInt8](repeating: UInt8(seed), count: 32))
    }

    private static let sender  = testKey(1)
    private static let owner   = testKey(2)
    private static let swapId  = testKey(3)
    private static let amount: UInt64 = 20_000_000

    private static func makeInstructions(
        amount: UInt64 = SwapInstructionBuilderUsdcToUsdfTests.amount,
        pool: FundSwapPool = .usdf,
        destination: UsdfSwapDestination = .swapPda
    ) -> [Instruction] {
        SwapInstructionBuilder.buildUsdcToUsdfSwapInstructions(
            sender: sender,
            owner: owner,
            amount: amount,
            pool: pool,
            swapId: swapId,
            destination: destination
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

    @Test(
        "CreateIdempotent at instruction targets the expected payer/owner/mint",
        arguments: [
            (
                index: 2,
                ataOwner: SwapInstructionBuilderUsdcToUsdfTests.sender,
                mint: PublicKey.usdf
            ),
            (
                index: 3,
                ataOwner: MintMetadata.usdf.timelockSwapAccounts(
                    owner: SwapInstructionBuilderUsdcToUsdfTests.owner
                )!.pda.publicKey,
                mint: PublicKey.usdf
            ),
            (
                index: 4,
                ataOwner: SwapInstructionBuilderUsdcToUsdfTests.sender,
                mint: PublicKey.usdc
            ),
        ]
    )
    func createIdempotent_payerOwnerMint(
        index: Int,
        ataOwner: PublicKey,
        mint: PublicKey
    ) {
        let ix = Self.makeInstructions()[index]
        // account layout: [payer (w,s), ata (w), owner, mint, system, token, rent]
        #expect(ix.program == AssociatedTokenProgram.address)
        #expect(ix.accounts[0].publicKey == Self.sender)
        #expect(ix.accounts[0].isSigner)
        #expect(ix.accounts[2].publicKey == ataOwner)
        #expect(ix.accounts[3].publicKey == mint)
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
    func instruction7_isTransferToSwapPdaAta() throws {
        let ix = Self.makeInstructions()[7]
        let pdaAta = try #require(MintMetadata.usdf.timelockSwapAccounts(owner: Self.owner)).ata.publicKey
        let senderUsdfAta = try #require(PublicKey.deriveAssociatedAccount(from: Self.sender, mint: .usdf)).publicKey
        #expect(ix.program == TokenProgram.address)
        // account layout: [source (w), destination (w), owner (s)]
        #expect(ix.accounts[0].publicKey == senderUsdfAta)
        #expect(ix.accounts[1].publicKey == pdaAta)
        #expect(ix.accounts[2].publicKey == Self.sender)
        #expect(ix.accounts[2].isSigner)
    }

    // MARK: - Usdf::Swap account verification

    @Test("Swap user (account 0) is sender and isSigner")
    func swap_userIsSender() {
        let ix = Self.makeInstructions()[6]
        #expect(ix.accounts[0].publicKey == Self.sender)
        #expect(ix.accounts[0].isSigner)
    }

    @Test("Swap pool, vaults match LiquidityPool.usdf")
    func swap_poolAccounts() {
        let ix = Self.makeInstructions()[6]
        #expect(ix.accounts[1].publicKey == LiquidityPool.usdf.address)
        #expect(ix.accounts[2].publicKey == LiquidityPool.usdf.usdfVault)
        #expect(ix.accounts[3].publicKey == LiquidityPool.usdf.otherVault)
    }

    @Test("Swap userUsdfToken (account 4) is sender's USDF ATA")
    func swap_userUsdfToken() throws {
        let ix = Self.makeInstructions()[6]
        let expected = try #require(PublicKey.deriveAssociatedAccount(from: Self.sender, mint: .usdf)).publicKey
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

    // MARK: - VM Deposit destination (Add Money via Phantom)

    private static func makeDepositInstructions(
        amount: UInt64 = SwapInstructionBuilderUsdcToUsdfTests.amount
    ) -> [Instruction] {
        makeInstructions(amount: amount, destination: .vmDeposit)
    }

    /// The owner's USDF VM Deposit ATA — derived exactly as the builder does:
    /// deposit PDA (`deriveDepositAccount`) then that PDA's canonical USDF ATA.
    private static func usdfDepositAta() -> PublicKey {
        let vm = MintMetadata.usdf.vmMetadata!
        let depositPda = PublicKey.deriveDepositAccount(
            owner: owner,
            mint: .usdf,
            timeAuthority: vm.authority,
            lockout: Byte(vm.lockDurationInDays)
        )!
        return PublicKey.deriveAssociatedAccount(from: depositPda.publicKey, mint: .usdf)!.publicKey
    }

    @Test("VM-deposit variant still produces exactly 8 instructions")
    func deposit_produces8Instructions() {
        #expect(Self.makeDepositInstructions().count == 8)
    }

    @Test("VM-deposit CreateIdempotent (instruction 3) opens the USDF VM Deposit ATA")
    func deposit_createIdempotentTargetsDepositAta() {
        let ix = Self.makeDepositInstructions()[3]
        let vm = MintMetadata.usdf.vmMetadata!
        let depositPda = PublicKey.deriveDepositAccount(
            owner: Self.owner,
            mint: .usdf,
            timeAuthority: vm.authority,
            lockout: Byte(vm.lockDurationInDays)
        )!
        // account layout: [payer (w,s), ata (w), owner, mint, system, token, rent]
        #expect(ix.program == AssociatedTokenProgram.address)
        #expect(ix.accounts[1].publicKey == Self.usdfDepositAta())
        #expect(ix.accounts[2].publicKey == depositPda.publicKey)
        #expect(ix.accounts[3].publicKey == PublicKey.usdf)
    }

    @Test("VM-deposit Transfer (instruction 7) sends USDF to the VM Deposit ATA, not the swap PDA")
    func deposit_transferTargetsDepositAta() throws {
        let ix = Self.makeDepositInstructions()[7]
        let depositAta = Self.usdfDepositAta()
        let swapPdaAta = try #require(MintMetadata.usdf.timelockSwapAccounts(owner: Self.owner)).ata.publicKey
        let senderUsdfAta = try #require(PublicKey.deriveAssociatedAccount(from: Self.sender, mint: .usdf)).publicKey
        #expect(ix.program == TokenProgram.address)
        // account layout: [source (w), destination (w), owner (s)]
        #expect(ix.accounts[0].publicKey == senderUsdfAta)
        #expect(ix.accounts[1].publicKey == depositAta)
        #expect(ix.accounts[1].publicKey != swapPdaAta)
        #expect(ix.accounts[2].publicKey == Self.sender)
        #expect(ix.accounts[2].isSigner)
    }

    @Test("The USDF VM Deposit ATA differs from the swap PDA ATA")
    func deposit_addressDiffersFromSwapPda() throws {
        let swapPdaAta = try #require(MintMetadata.usdf.timelockSwapAccounts(owner: Self.owner)).ata.publicKey
        #expect(Self.usdfDepositAta() != swapPdaAta)
    }

    // MARK: - Coinbase Stable Swapper pool

    private static let feeRecipient = testKey(4)

    private static func makeCoinbaseInstructions(
        amount: UInt64 = SwapInstructionBuilderUsdcToUsdfTests.amount
    ) -> [Instruction] {
        makeInstructions(
            amount: amount,
            pool: .coinbaseStableSwapper(feeRecipient: feeRecipient),
            destination: .vmDeposit
        )
    }

    @Test("Coinbase variant still produces exactly 8 instructions")
    func coinbase_produces8Instructions() {
        #expect(Self.makeCoinbaseInstructions().count == 8)
    }

    @Test("Coinbase variant replaces instruction 6 with the CoinbaseStableSwapper swap")
    func coinbase_swapInstructionProgram() {
        #expect(Self.makeCoinbaseInstructions()[6].program == CoinbaseStableSwapperProgram.address)
    }

    @Test(
        "Coinbase variant matches the legacy layout at every non-swap instruction",
        arguments: [0, 1, 2, 3, 4, 5, 7]
    )
    func coinbase_nonSwapInstruction_matchesLegacy(index: Int) {
        let coinbase = Self.makeCoinbaseInstructions()[index]
        let legacy = Self.makeDepositInstructions()[index]
        #expect(coinbase.program == legacy.program)
        #expect(coinbase.accounts.map(\.publicKey) == legacy.accounts.map(\.publicKey))
        #expect(coinbase.data == legacy.data)
    }

    @Test("Coinbase swap accounts: pool PDAs, sender ATAs, fee recipient, whitelist")
    func coinbase_swapAccounts() throws {
        let instructions = Self.makeCoinbaseInstructions()
        let ix = instructions[6]

        let pool = try #require(CoinbaseStableSwapperProgram.derivePoolAddress()).publicKey
        let inVault = try #require(CoinbaseStableSwapperProgram.deriveTokenVaultAddress(pool: pool, mint: .usdc)).publicKey
        let outVault = try #require(CoinbaseStableSwapperProgram.deriveTokenVaultAddress(pool: pool, mint: .usdf)).publicKey
        let inVaultTokenAccount = try #require(CoinbaseStableSwapperProgram.deriveVaultTokenAccountAddress(vault: inVault)).publicKey
        let outVaultTokenAccount = try #require(CoinbaseStableSwapperProgram.deriveVaultTokenAccountAddress(vault: outVault)).publicKey
        let whitelist = try #require(CoinbaseStableSwapperProgram.deriveWhitelistAddress()).publicKey
        let senderUsdcAta = instructions[4].accounts[1].publicKey
        let senderUsdfAta = instructions[2].accounts[1].publicKey
        let feeRecipientUsdcAta = try #require(
            PublicKey.deriveAssociatedAccount(from: Self.feeRecipient, mint: .usdc)
        ).publicKey

        // Account list order documented on CoinbaseStableSwapperProgram.Swap.
        #expect(ix.accounts[0].publicKey == pool)
        #expect(ix.accounts[1].publicKey == inVault)
        #expect(ix.accounts[2].publicKey == outVault)
        #expect(ix.accounts[3].publicKey == inVaultTokenAccount)
        #expect(ix.accounts[4].publicKey == outVaultTokenAccount)
        #expect(ix.accounts[5].publicKey == senderUsdcAta)
        #expect(ix.accounts[6].publicKey == senderUsdfAta)
        #expect(ix.accounts[7].publicKey == feeRecipientUsdcAta)
        #expect(ix.accounts[8].publicKey == Self.feeRecipient)
        #expect(ix.accounts[9].publicKey == PublicKey.usdc)
        #expect(ix.accounts[10].publicKey == PublicKey.usdf)
        #expect(ix.accounts[11].publicKey == Self.sender)
        #expect(ix.accounts[11].isSigner)
        #expect(ix.accounts[12].publicKey == whitelist)
    }

    @Test("Coinbase swap data: discriminator + amountIn(8 LE) + minAmountOut(8 LE), both equal to amount")
    func coinbase_dataLayout() {
        let ix = Self.makeCoinbaseInstructions(amount: 20_000_000)[6]
        #expect(ix.data.count == 8 + 8 + 8)
        #expect(Array(ix.data.prefix(8)) == CoinbaseStableSwapperProgram.Swap.discriminator)
        #expect(UInt64(bytes: Array(ix.data[8..<16])) == 20_000_000)
        #expect(UInt64(bytes: Array(ix.data[16..<24])) == 20_000_000)
    }
}
