//
//  SwapInstructionBuilderUsdfToUsdcTests.swift
//  FlipcashCoreTests
//

import Foundation
import Testing
@testable import FlipcashCore

@Suite("SwapInstructionBuilder.buildUsdfToUsdcSwapInstructions")
struct SwapInstructionBuilderUsdfToUsdcTests {

    // MARK: - Fixtures

    /// 32-byte pubkey filled entirely with the seed byte. Mirrors Android's
    /// `testKey(seed: Int) = PublicKey(ByteArray(32) { seed.toByte() })`.
    private static func testKey(_ seed: Int) -> PublicKey {
        try! PublicKey([UInt8](repeating: UInt8(seed), count: 32))
    }

    private static let payer            = testKey(1)
    private static let nonce            = testKey(2)
    private static let blockhash        = testKey(3)
    private static let authority        = testKey(4)
    private static let swapAuthority    = testKey(5)
    private static let destinationOwner = testKey(6)
    private static let feeDestination   = testKey(7)
    private static let poolFeeRecipient = testKey(8)

    private static let fromMintAddress  = testKey(10)
    private static let fromVmAuthority  = testKey(11)
    private static let fromVm           = testKey(12)
    private static let toMintAddress    = testKey(20)
    private static let toVmAuthority    = testKey(21)
    private static let toVm             = testKey(22)

    /// Mirrors Android's `mintMetadata(address, vmAuthority, vm)` with decimals=6
    /// and lockDurationInDays=21.
    private static func makeMintMetadata(
        address: PublicKey,
        vmAuthority: PublicKey,
        vm: PublicKey
    ) -> MintMetadata {
        MintMetadata(
            address: address,
            decimals: 6,
            name: "Test",
            symbol: "TST",
            description: "",
            imageURL: nil,
            vmMetadata: VMMetadata(
                vm: vm,
                authority: vmAuthority,
                lockDurationInDays: 21
            ),
            launchpadMetadata: nil
        )
    }

    private static let fromMintMetadata = makeMintMetadata(
        address: fromMintAddress,
        vmAuthority: fromVmAuthority,
        vm: fromVm
    )
    private static let toMintMetadata = makeMintMetadata(
        address: toMintAddress,
        vmAuthority: toVmAuthority,
        vm: toVm
    )

    private static let serverParameters = SwapResponseServerParameters.CoinbaseStableSwapServerParameters(
        payer: payer,
        nonce: nonce,
        blockhash: try! Hash([UInt8](repeating: 3, count: 32)),
        alts: [],
        computeUnitLimit: 150_000,
        computeUnitPrice: 10_000,
        memoValue: "coinbase_stable_swapper_v0",
        feeDestination: feeDestination,
        poolFeeRecipient: poolFeeRecipient
    )

    private static func makeInstructions(
        amount: UInt64 = 1_000_000,
        feeAmount: UInt64 = 50_000,
        minOutput: UInt64 = 990_000
    ) -> [Instruction] {
        SwapInstructionBuilder.buildUsdfToUsdcSwapInstructions(
            serverParameters: serverParameters,
            authority: authority,
            swapAuthority: swapAuthority,
            destinationOwner: destinationOwner,
            fromMintMetadata: fromMintMetadata,
            toMintMetadata: toMintMetadata,
            amount: amount,
            feeAmount: feeAmount,
            minOutput: minOutput
        )
    }

    // MARK: - Instruction count

    @Test("Produces exactly 9 instructions")
    func produces9Instructions() {
        #expect(Self.makeInstructions().count == 9)
    }

    // MARK: - Instruction order and programs

    @Test("Instruction 0 is SystemProgram AdvanceNonce")
    func instruction0_isAdvanceNonce() {
        #expect(Self.makeInstructions()[0].program == SystemProgram.address)
    }

    @Test("Instruction 1 is ComputeBudget SetComputeUnitLimit")
    func instruction1_isComputeUnitLimit() {
        let ix = Self.makeInstructions()[1]
        #expect(ix.program == ComputeBudgetProgram.address)
        #expect(ix.data.first == ComputeBudgetProgram.Command.setComputeUnitLimit.rawValue)
    }

    @Test("Instruction 2 is ComputeBudget SetComputeUnitPrice")
    func instruction2_isComputeUnitPrice() {
        let ix = Self.makeInstructions()[2]
        #expect(ix.program == ComputeBudgetProgram.address)
        #expect(ix.data.first == ComputeBudgetProgram.Command.setComputeUnitPrice.rawValue)
    }

    @Test("Instruction 3 is Memo")
    func instruction3_isMemo() {
        #expect(Self.makeInstructions()[3].program == MemoProgram.address)
    }

    @Test("Instruction 4 is AssociatedTokenProgram CreateIdempotent for swap authority from_mint ATA")
    func instruction4_isCreateSwapAuthorityFromMintATA() {
        let ix = Self.makeInstructions()[4]
        #expect(ix.program == AssociatedTokenProgram.address)
        // account layout: [payer (w,s), ata (w), owner, mint, system, token, rent]
        #expect(ix.accounts[2].publicKey == Self.swapAuthority)
        #expect(ix.accounts[3].publicKey == Self.fromMintAddress)
    }

    @Test("Instruction 5 is AssociatedTokenProgram CreateIdempotent for destination owner to_mint ATA")
    func instruction5_isCreateDestinationOwnerToMintATA() {
        let ix = Self.makeInstructions()[5]
        #expect(ix.program == AssociatedTokenProgram.address)
        #expect(ix.accounts[2].publicKey == Self.destinationOwner)
        #expect(ix.accounts[3].publicKey == Self.toMintAddress)
    }

    @Test("Instruction 6 is VMProgram TransferForSwapWithFee")
    func instruction6_isVMTransferForSwapWithFee() {
        let ix = Self.makeInstructions()[6]
        #expect(ix.program == VMProgram.address)
        // account layout: [vmAuthority(w,s), vm(w), swapper(w,s), swapPda, swapAta(w), swapDest(w), feeDest(w), tokenProgram]
        #expect(ix.accounts[0].publicKey == Self.fromVmAuthority)
        #expect(ix.accounts[1].publicKey == Self.fromVm)
        #expect(ix.accounts[2].publicKey == Self.authority)
        #expect(ix.accounts[6].publicKey == Self.feeDestination)
    }

    @Test("Instruction 7 is CoinbaseStableSwapper Swap")
    func instruction7_isCoinbaseSwap() {
        let ix = Self.makeInstructions()[7]
        #expect(ix.program == CoinbaseStableSwapperProgram.address)
    }

    @Test("Instruction 8 is TokenProgram CloseAccount")
    func instruction8_isCloseAccount() {
        let ix = Self.makeInstructions()[8]
        #expect(ix.program == TokenProgram.address)
        // account layout: [account(w), destination(w), owner]
        let expectedAta = PublicKey.deriveAssociatedAccount(from: Self.swapAuthority, mint: Self.fromMintAddress)!.publicKey
        #expect(ix.accounts[0].publicKey == expectedAta)
        #expect(ix.accounts[1].publicKey == Self.payer)
        #expect(ix.accounts[2].publicKey == Self.swapAuthority)
    }

    // MARK: - CoinbaseStableSwapper::Swap account verification

    @Test("Swap instruction has correct pool PDA at account 0")
    func swap_pool() {
        let ix = Self.makeInstructions()[7]
        let expected = CoinbaseStableSwapperProgram.derivePoolAddress()!.publicKey
        #expect(ix.accounts[0].publicKey == expected)
    }

    @Test("Swap instruction has correct in and out vaults at accounts 1 and 2")
    func swap_vaults() {
        let ix = Self.makeInstructions()[7]
        let pool = CoinbaseStableSwapperProgram.derivePoolAddress()!.publicKey
        let expectedInVault  = CoinbaseStableSwapperProgram.deriveTokenVaultAddress(pool: pool, mint: Self.fromMintAddress)!.publicKey
        let expectedOutVault = CoinbaseStableSwapperProgram.deriveTokenVaultAddress(pool: pool, mint: Self.toMintAddress)!.publicKey
        #expect(ix.accounts[1].publicKey == expectedInVault)
        #expect(ix.accounts[2].publicKey == expectedOutVault)
    }

    @Test("Swap instruction has correct vault token accounts at accounts 3 and 4")
    func swap_vaultTokenAccounts() {
        let ix = Self.makeInstructions()[7]
        let pool = CoinbaseStableSwapperProgram.derivePoolAddress()!.publicKey
        let inVault  = CoinbaseStableSwapperProgram.deriveTokenVaultAddress(pool: pool, mint: Self.fromMintAddress)!.publicKey
        let outVault = CoinbaseStableSwapperProgram.deriveTokenVaultAddress(pool: pool, mint: Self.toMintAddress)!.publicKey
        let expectedInVaultTA  = CoinbaseStableSwapperProgram.deriveVaultTokenAccountAddress(vault: inVault)!.publicKey
        let expectedOutVaultTA = CoinbaseStableSwapperProgram.deriveVaultTokenAccountAddress(vault: outVault)!.publicKey
        #expect(ix.accounts[3].publicKey == expectedInVaultTA)
        #expect(ix.accounts[4].publicKey == expectedOutVaultTA)
    }

    @Test("Swap userFromTokenAccount (account 5) is swap authority's from_mint ATA")
    func swap_userFromTokenAccount() {
        let ix = Self.makeInstructions()[7]
        let expected = PublicKey.deriveAssociatedAccount(from: Self.swapAuthority, mint: Self.fromMintAddress)!.publicKey
        #expect(ix.accounts[5].publicKey == expected)
    }

    @Test("Swap toTokenAccount (account 6) is destination owner's to_mint ATA")
    func swap_toTokenAccount() {
        let ix = Self.makeInstructions()[7]
        let expected = PublicKey.deriveAssociatedAccount(from: Self.destinationOwner, mint: Self.toMintAddress)!.publicKey
        #expect(ix.accounts[6].publicKey == expected)
    }

    @Test("Swap feeRecipientTokenAccount (account 7) is poolFeeRecipient's from_mint ATA")
    func swap_feeRecipientTokenAccount() {
        let ix = Self.makeInstructions()[7]
        let expected = PublicKey.deriveAssociatedAccount(from: Self.poolFeeRecipient, mint: Self.fromMintAddress)!.publicKey
        #expect(ix.accounts[7].publicKey == expected)
    }

    @Test("Swap feeRecipient (account 8) matches server parameter")
    func swap_feeRecipient() {
        let ix = Self.makeInstructions()[7]
        #expect(ix.accounts[8].publicKey == Self.poolFeeRecipient)
    }

    @Test("Swap fromMint (account 9) and toMint (account 10) match mint addresses")
    func swap_mints() {
        let ix = Self.makeInstructions()[7]
        #expect(ix.accounts[9].publicKey  == Self.fromMintAddress)
        #expect(ix.accounts[10].publicKey == Self.toMintAddress)
    }

    @Test("Swap user (account 11) is swapAuthority and isSigner")
    func swap_user() {
        let ix = Self.makeInstructions()[7]
        #expect(ix.accounts[11].publicKey == Self.swapAuthority)
        #expect(ix.accounts[11].isSigner  == true)
    }

    @Test("Swap whitelist (account 12) is the Coinbase whitelist PDA")
    func swap_whitelist() {
        let ix = Self.makeInstructions()[7]
        let expected = CoinbaseStableSwapperProgram.deriveWhitelistAddress()!.publicKey
        #expect(ix.accounts[12].publicKey == expected)
    }

    // MARK: - Discriminator + data layout (24 bytes)

    @Test("Swap instruction data starts with the Anchor discriminator")
    func swap_discriminator() {
        let ix = Self.makeInstructions()[7]
        let expected: [UInt8] = [248, 198, 158, 145, 225, 117, 135, 200]
        #expect(Array(ix.data.prefix(8)) == expected)
    }

    @Test("Swap data is 24 bytes: discriminator(8) + amountIn(8 LE) + minAmountOut(8 LE)")
    func swap_dataLayout() {
        let ix = Self.makeInstructions(amount: 1_000_000, minOutput: 990_000)[7]
        #expect(ix.data.count == 24)

        let amountIn = ix.data[8..<16].withUnsafeBytes { $0.load(as: UInt64.self).littleEndian }
        #expect(amountIn == 1_000_000)

        let minAmountOut = ix.data[16..<24].withUnsafeBytes { $0.load(as: UInt64.self).littleEndian }
        #expect(minAmountOut == 990_000)
    }

    // MARK: - Cross-instruction linkage

    @Test("VM TransferForSwapWithFee destination (account 5) matches Swap userFromTokenAccount (account 5)")
    func transferDestination_matchesSwapUserFrom() {
        let instructions = Self.makeInstructions()
        let transferIx = instructions[6]
        let swapIx     = instructions[7]
        #expect(transferIx.accounts[5].publicKey == swapIx.accounts[5].publicKey)
    }

    @Test("CloseAccount account (account 0) matches Swap userFromTokenAccount (account 5)")
    func closeAccount_matchesSwapUserFrom() {
        let instructions = Self.makeInstructions()
        let swapIx  = instructions[7]
        let closeIx = instructions[8]
        #expect(closeIx.accounts[0].publicKey == swapIx.accounts[5].publicKey)
    }
}
