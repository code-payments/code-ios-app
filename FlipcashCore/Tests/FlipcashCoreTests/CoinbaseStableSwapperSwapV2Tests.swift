//
//  CoinbaseStableSwapperSwapV2Tests.swift
//  FlipcashCoreTests
//

import Foundation
import Testing
import OCPClientProtocol
@testable import FlipcashCore

/// Golden vector shared with Android and the server's `instructions_swap_v2_test.go`.
@Suite("CoinbaseStableSwapper SwapV2 instruction")
struct CoinbaseStableSwapperSwapV2Tests {

    private static func key(_ i: Int) -> PublicKey {
        var bytes = [UInt8](repeating: 0, count: 32)
        bytes[0] = UInt8(i + 1)
        return try! PublicKey(bytes)
    }

    private static let amountIn: UInt64 = 1_500_000
    private static let minAmountOut: UInt64 = 1_490_000

    private static var v2: Instruction {
        CoinbaseStableSwapperProgram.SwapV2(
            pool: key(0), inVault: key(1), outVault: key(2),
            inVaultTokenAccount: key(3), outVaultTokenAccount: key(4),
            userFromTokenAccount: key(5), toTokenAccount: key(6),
            feeRecipientTokenAccount: key(7), feeRecipient: key(8),
            fromMint: key(9), toMint: key(10), user: key(11),
            amountIn: amountIn, minAmountOut: minAmountOut
        ).instruction()
    }

    @Test("Data matches the golden vector exactly")
    func data_goldenVector() {
        let expected: [UInt8] = [
            43, 4, 237, 11, 26, 201, 30, 98,
            0x60, 0xe3, 0x16, 0, 0, 0, 0, 0,
            0x50, 0xbc, 0x16, 0, 0, 0, 0, 0,
        ]
        #expect(Array(Self.v2.data) == expected)
    }

    @Test("Accounts match the golden 15-account list, in order, with only the user signing")
    func accounts_golden() {
        let accounts = Self.v2.accounts
        #expect(accounts.map(\.publicKey) == (0...11).map(Self.key) + [
            TokenProgram.address, AssociatedTokenProgram.address, SystemProgram.address,
        ])
        #expect(accounts.map(\.isSigner) == (0..<15).map { $0 == 11 })
        #expect(accounts.map(\.isWritable) == (0..<15).map { [3, 4, 5, 6, 7, 11].contains($0) })
    }

    @Test("Targets the Coinbase Stable Swapper program")
    func program() {
        #expect(Self.v2.program == CoinbaseStableSwapperProgram.address)
    }

    @Test("Stateful stablecoin client parameters carry swapVersion 2")
    func statefulClientParameters_carryVersion() {
        let params = VerifiedSwapMetadata.ClientParameters(
            id: SwapId.generate(),
            fromMint: MintMetadata.usdf.address,
            toMint: MintMetadata.usdc.address,
            amount: TokenAmount(quarks: 1_000_000, mint: MintMetadata.usdf.address),
            fundingSource: .submitIntent(id: Self.key(0)),
            kind: .stablecoin(destinationOwner: Self.key(1))
        )
        #expect(params.stablecoinProto.swapVersion == 2)
    }

    @Test("Stateless stablecoin initiate parameters carry swapVersion 2")
    func statelessInitiate_carriesVersion() {
        let params = Ocp_Transaction_V1_StatelessSwapRequest.Initiate.CoinbaseStableSwapperClientParameters
            .coinbaseStableSwapper(
                fromMint: .usdc,
                toMint: .usdf,
                amount: TokenAmount(quarks: 1_000_000, mint: MintMetadata.usdc.address)
            )
        #expect(params.swapVersion == 2)
    }

    @Test("Stateless builder emits SwapV2 (15 accounts, v2 discriminator)")
    func statelessBuilder_emitsV2() {
        let serverParams = StatelessSwapServerParameters(
            payer: Self.key(20),
            blockhash: try! Hash([UInt8](repeating: 3, count: 32)),
            alts: [],
            computeUnitLimit: 0,
            computeUnitPrice: 0,
            memoValue: "",
            poolFeeRecipient: Self.key(21)
        )
        let ixs = SwapInstructionBuilder.buildStatelessSwapInstructions(
            serverParameters: serverParams,
            owner: Self.key(22),
            fromMint: .usdc,
            toMint: .usdf,
            amount: 1_000_000
        )
        let swap = ixs.last!
        #expect(swap.program == CoinbaseStableSwapperProgram.address)
        #expect(swap.accounts.count == 15)
        #expect(Array(swap.data.prefix(8)) == CoinbaseStableSwapperProgram.SwapV2.discriminator)
    }
}
