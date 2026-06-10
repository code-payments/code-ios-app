//
//  VMProgramTransferForSwapTests.swift
//  FlipcashCore
//

import Foundation
import Testing
@testable import FlipcashCore

@Suite("VMProgram.TransferForSwap")
struct VMProgramTransferForSwapTests {

    private static func key(_ base58: String) -> PublicKey { try! PublicKey(base58: base58) }

    private static let vmAuthority = key("cash11ndAmdKFEnG2wrQQ5Zqvr1kN9htxxLyoPLYFUV")
    private static let vm          = key("JACkaKsm2Rd6TNJwH4UB7G6tHrWUATJPTgNNnRVsg4ip")
    private static let swapper     = key("admJSWL9vzQfoFm9HoLsgTHCK5G1SKzdsMJCdAtKXnN")
    private static let swapPda     = key("FGH6ZKtsd7kLE6ToxEyjBgVrQQefKF7XKLxNAoU56X2q")
    private static let swapAta     = key("6QffJbV83ZpSRGvmvba9agN8xfZ9PatHoYcBUXRnmoDr")
    private static let destination = key("FNdBL7w2pRxBoz349ygKdWfGvrzPN6Wjcqu9mmVXjmcx")

    private func makeInstance(amount: UInt64, bump: Byte) -> VMProgram.TransferForSwap {
        .init(
            vmAuthority: Self.vmAuthority,
            vm: Self.vm,
            swapper: Self.swapper,
            swapPda: Self.swapPda,
            swapAta: Self.swapAta,
            destination: Self.destination,
            amount: amount,
            bump: bump
        )
    }

    @Test("Opcode is 17 and data layout is opcode + amount + bump")
    func encoding_dataLayout() {
        let data = makeInstance(amount: 1_000_000, bump: 254).encode()

        #expect(data.count == 10)
        #expect(data[0] == VMProgram.Command.transferForSwap.rawValue)

        let amountBytes = Array(data[1..<9])
        #expect(UInt64(bytes: amountBytes) == 1_000_000)

        #expect(data[9] == 254)
    }

    @Test("Round-trip encode/decode preserves every field")
    func roundTrip() throws {
        let original = makeInstance(amount: 1_000_000, bump: 254)
        let parsed = try VMProgram.TransferForSwap(instruction: original.instruction())
        #expect(parsed == original)
    }

    @Test("Account order matches OCP TransferForSwapInstructionAccounts")
    func accountOrder() {
        let accounts = makeInstance(amount: 1, bump: 0).instruction().accounts

        #expect(accounts.count == 7)

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

        #expect(accounts[5].publicKey == Self.destination)
        #expect(accounts[5].isWritable == true)

        #expect(accounts[6].publicKey == TokenProgram.address)
        #expect(accounts[6].isWritable == false)
    }
}
