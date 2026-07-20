//
//  SwapInstructionBuilderNewCurrencyTreasuryTests.swift
//  FlipcashCoreTests
//

import Foundation
import Testing
import FlipcashAPI
@testable import FlipcashCore

@Suite("SwapInstructionBuilder treasury-funded new-currency launch")
struct SwapInstructionBuilderNewCurrencyTreasuryTests {

    private static func key(_ seed: UInt8) -> PublicKey {
        try! PublicKey([UInt8](repeating: seed, count: 32))
    }

    private static let payer     = key(1)
    private static let nonce     = key(2)
    private static let authority = key(4)
    private static let treasury  = key(7)
    private static let feeDestination = key(8)

    private static let paymentMint = MintMetadata(
        address: key(10),
        decimals: 10,
        name: "PAY",
        symbol: "PAY",
        description: "",
        imageURL: nil,
        vmMetadata: VMMetadata(
            vm: key(11),
            authority: key(12),
            lockDurationInDays: 21
        ),
        launchpadMetadata: LaunchpadMetadata(
            currencyConfig: key(13),
            liquidityPool: key(14),
            seed: key(15),
            authority: key(12),
            mintVault: key(16),
            coreMintVault: key(17),
            coreMintFees: nil,
            supplyFromBonding: 50_000,
            sellFeeBps: 100
        )
    )

    private static func makeServerParams() -> SwapResponseServerParameters.ReserveNewCurrency {
        SwapResponseServerParameters.ReserveNewCurrency(
            payer: payer,
            nonce: nonce,
            blockhash: try! Hash([UInt8](repeating: 99, count: 32)),
            alts: [],
            computeUnitLimit: 250_000,
            computeUnitPrice: 10_000,
            memoValue: "",
            authority: authority,
            name: "Test Coin",
            symbol: "VALUE",
            seed: key(20),
            sellFeeBps: 100,
            vmLockDurationInDays: 21,
            feeDestination: feeDestination,
            treasury: treasury,
            treasuryPurchaseAmount: 10_000_000
        )
    }

    private func build(swapAmount: UInt64 = 900, feeAmount: UInt64 = 100) throws -> [Instruction] {
        try SwapInstructionBuilder.newCurrencyLaunchTreasuryFunded(
            serverParams: Self.makeServerParams(),
            treasury: Self.treasury,
            treasuryPurchaseAmount: 10_000_000,
            authority: Self.authority,
            paymentToken: Self.paymentMint,
            swapAmount: swapAmount,
            feeAmount: feeAmount
        )
    }

    @Test("Builds the 7-instruction treasury format in server order — no Initialize, Memo, or Close")
    func instructionOrder() throws {
        let instructions = try build()

        #expect(instructions.count == 7)
        #expect(instructions[0].program == SystemProgram.address)
        #expect(instructions[1].program == ComputeBudgetProgram.address)
        #expect(instructions[2].program == ComputeBudgetProgram.address)
        #expect(instructions[3].program == AssociatedTokenProgram.address)
        #expect(instructions[4].program == VMProgram.address)
        #expect(instructions[5].program == CurrencyCreatorProgram.address)
        #expect(instructions[6].program == CurrencyCreatorProgram.address)
    }

    @Test("The treasury's payment-mint ATA collects both the swap and the fee")
    func transferLeg() throws {
        let instructions = try build(swapAmount: 900, feeAmount: 100)

        let treasuryAta = try AssociatedTokenProgram.CreateIdempotent(instruction: instructions[3])
        #expect(treasuryAta.owner == Self.treasury)
        #expect(treasuryAta.mint == Self.paymentMint.address)
        #expect(treasuryAta.subsidizer == Self.payer)

        let transfer = try VMProgram.TransferForSwapWithFee(instruction: instructions[4])
        #expect(transfer.swapAmount == 900)
        #expect(transfer.feeAmount == 100)
        #expect(transfer.vmAuthority == Self.paymentMint.vmMetadata?.authority)
        #expect(transfer.vm == Self.paymentMint.vmMetadata?.vm)
        #expect(transfer.swapper == Self.authority)
        #expect(transfer.swapDestination == treasuryAta.address)
        #expect(transfer.feeDestination == treasuryAta.address)
    }

    @Test("SellTokens sells the full swap+fee from the treasury, proceeds to the fee destination")
    func sellLeg() throws {
        let instructions = try build(swapAmount: 900, feeAmount: 100)

        let treasuryAta = try AssociatedTokenProgram.CreateIdempotent(instruction: instructions[3])
        let sell = try CurrencyCreatorProgram.SellTokens(instruction: instructions[5])

        #expect(sell.inAmount == 1_000)
        #expect(sell.minAmountOut == 0)
        #expect(sell.seller == Self.treasury)
        #expect(sell.pool == Self.paymentMint.launchpadMetadata?.liquidityPool)
        #expect(sell.targetMint == Self.paymentMint.address)
        #expect(sell.baseMint == MintMetadata.usdf.address)
        #expect(sell.vaultTarget == Self.paymentMint.launchpadMetadata?.mintVault)
        #expect(sell.vaultBase == Self.paymentMint.launchpadMetadata?.coreMintVault)
        #expect(sell.sellerTarget == treasuryAta.address)
        #expect(sell.sellerBase == Self.feeDestination)
    }

    @Test("BuyTokens is treasury-funded with exactly the pre-coordinated core quarks")
    func buyLeg() throws {
        let instructions = try build()

        let buy = try CurrencyCreatorProgram.BuyTokens(instruction: instructions[6])

        #expect(buy.amount == 10_000_000)
        #expect(buy.minOutAmount == 0)
        #expect(buy.buyer == Self.treasury)
        #expect(buy.baseMint == MintMetadata.usdf.address)

        let treasuryCoreAta = try #require(PublicKey.deriveAssociatedAccount(
            from: Self.treasury,
            mint: MintMetadata.usdf.address
        ))
        #expect(buy.buyerBase == treasuryCoreAta.publicKey)
    }

    @Test("Server params parse the treasury fields when present, nil treasury when absent")
    func paramsParseTreasury() throws {
        var proto = Ocp_Transaction_V1_StatefulSwapResponse.ServerParameters.ReserveNewCurrencyServerParameter()
        proto.payer = Self.payer.solanaAccountID
        proto.nonce = Self.nonce.solanaAccountID
        proto.blockhash = .with { $0.value = Data(repeating: 99, count: 32) }
        proto.authority = Self.authority.solanaAccountID
        proto.seed = Self.key(20).solanaAccountID
        proto.feeDestination = Self.feeDestination.solanaAccountID
        proto.treasury = Self.treasury.solanaAccountID
        proto.treasuryPurchaseAmount = 10_000_000

        let parsed = try #require(SwapResponseServerParameters.ReserveNewCurrency(proto))
        #expect(parsed.treasury == Self.treasury)
        #expect(parsed.treasuryPurchaseAmount == 10_000_000)

        proto.clearTreasury()
        let withoutTreasury = try #require(SwapResponseServerParameters.ReserveNewCurrency(proto))
        #expect(withoutTreasury.treasury == nil)
    }

    @Test("Missing payment-mint metadata throws missingMintMetadata")
    func missingMetadata_throws() {
        let bare = MintMetadata(
            address: Self.paymentMint.address,
            decimals: 10,
            name: "PAY",
            symbol: "PAY",
            description: "",
            imageURL: nil,
            vmMetadata: Self.paymentMint.vmMetadata,
            launchpadMetadata: nil
        )

        #expect(throws: SwapTransactionBuildError.missingMintMetadata(symbol: "PAY")) {
            try SwapInstructionBuilder.newCurrencyLaunchTreasuryFunded(
                serverParams: Self.makeServerParams(),
                treasury: Self.treasury,
                treasuryPurchaseAmount: 10_000_000,
                authority: Self.authority,
                paymentToken: bare,
                swapAmount: 900,
                feeAmount: 100
            )
        }
    }
}
