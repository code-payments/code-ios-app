//
//  TransferForSwapWithFeeTests.swift
//  Flipcash
//

import Foundation
import Testing
@testable import FlipcashCore

@Suite("VMProgram.TransferForSwapWithFee")
struct TransferForSwapWithFeeTests {

    private static func key(_ base58: String) -> PublicKey { try! PublicKey(base58: base58) }

    private static let vmAuthority     = key("cash11ndAmdKFEnG2wrQQ5Zqvr1kN9htxxLyoPLYFUV")
    private static let vm              = key("JACkaKsm2Rd6TNJwH4UB7G6tHrWUATJPTgNNnRVsg4ip")
    private static let swapper         = key("admJSWL9vzQfoFm9HoLsgTHCK5G1SKzdsMJCdAtKXnN")
    private static let swapPda         = key("FGH6ZKtsd7kLE6ToxEyjBgVrQQefKF7XKLxNAoU56X2q")
    private static let swapAta         = key("6QffJbV83ZpSRGvmvba9agN8xfZ9PatHoYcBUXRnmoDr")
    private static let swapDestination = key("FNdBL7w2pRxBoz349ygKdWfGvrzPN6Wjcqu9mmVXjmcx")
    private static let feeDestination  = key("HkL1my3dtsn6FVbcv7rHA4htg6zdVyn4fna3e941WomZ")

    private func makeInstruction(swapAmount: UInt64, feeAmount: UInt64, bump: Byte) -> VMProgram.TransferForSwapWithFee {
        .init(
            vmAuthority: Self.vmAuthority,
            vm: Self.vm,
            swapper: Self.swapper,
            swapPda: Self.swapPda,
            swapAta: Self.swapAta,
            swapDestination: Self.swapDestination,
            feeDestination: Self.feeDestination,
            swapAmount: swapAmount,
            feeAmount: feeAmount,
            bump: bump
        )
    }

    @Test("Opcode is 20 and data layout is opcode + swap + fee + bump")
    func encoding_dataLayout() {
        let ix = makeInstruction(swapAmount: 5_000_000, feeAmount: 15_000_000, bump: 254)
        let data = ix.encode()

        #expect(data.count == 1 + 8 + 8 + 1)
        #expect(data[0] == VMProgram.Command.transferForSwapWithFee.rawValue)
        #expect(data[0] == 20)

        let swapBytes = Array(data[1..<9])
        #expect(UInt64(bytes: swapBytes) == 5_000_000)

        let feeBytes = Array(data[9..<17])
        #expect(UInt64(bytes: feeBytes) == 15_000_000)

        #expect(data[17] == 254)
    }

    @Test("Account order matches OCP TransferForSwapWithFeeInstructionAccounts")
    func accountOrder() {
        let ix = makeInstruction(swapAmount: 1, feeAmount: 2, bump: 0)
        let accounts = ix.instruction().accounts

        #expect(accounts.count == 8)

        #expect(accounts[0].publicKey == Self.vmAuthority)
        #expect(accounts[0].isSigner == true)
        #expect(accounts[0].isWritable == true)

        #expect(accounts[1].publicKey == Self.vm)
        #expect(accounts[1].isWritable == true)
        #expect(accounts[1].isSigner == false)

        #expect(accounts[2].publicKey == Self.swapper)
        #expect(accounts[2].isSigner == true)
        #expect(accounts[2].isWritable == true)

        #expect(accounts[3].publicKey == Self.swapPda)
        #expect(accounts[3].isWritable == false)

        #expect(accounts[4].publicKey == Self.swapAta)
        #expect(accounts[4].isWritable == true)

        #expect(accounts[5].publicKey == Self.swapDestination)
        #expect(accounts[5].isWritable == true)

        #expect(accounts[6].publicKey == Self.feeDestination)
        #expect(accounts[6].isWritable == true)

        #expect(accounts[7].publicKey == TokenProgram.address)
        #expect(accounts[7].isWritable == false)
    }

    @Test("Round-trip encode/decode preserves every field")
    func roundTrip() throws {
        let original = makeInstruction(swapAmount: 5_000_000, feeAmount: 15_000_000, bump: 253)
        let parsed = try VMProgram.TransferForSwapWithFee(instruction: original.instruction())
        #expect(parsed == original)
    }

    @Test("Zero-fee launch still encodes TransferForSwapWithFee with fee_amount = 0")
    func zeroFeeRoundTrip() throws {
        let original = makeInstruction(swapAmount: 5_000_000, feeAmount: 0, bump: 1)
        let parsed = try VMProgram.TransferForSwapWithFee(instruction: original.instruction())
        #expect(parsed == original)
        #expect(original.encode()[0] == VMProgram.Command.transferForSwapWithFee.rawValue)
    }
}
