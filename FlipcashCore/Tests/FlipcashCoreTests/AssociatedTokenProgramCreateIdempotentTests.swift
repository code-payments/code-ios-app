//
//  AssociatedTokenProgramCreateIdempotentTests.swift
//  FlipcashCore
//

import Foundation
import Testing
@testable import FlipcashCore

@Suite("AssociatedTokenProgram.CreateIdempotent")
struct AssociatedTokenProgramCreateIdempotentTests {

    private static let subsidizer = try! PublicKey(base58: "cash11ndAmdKFEnG2wrQQ5Zqvr1kN9htxxLyoPLYFUV")
    private static let owner      = try! PublicKey(base58: "JACkaKsm2Rd6TNJwH4UB7G6tHrWUATJPTgNNnRVsg4ip")
    private static let address    = try! PublicKey(base58: "FNdBL7w2pRxBoz349ygKdWfGvrzPN6Wjcqu9mmVXjmcx")
    private static let mint       = try! PublicKey(base58: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v")  // USDC

    private func makeInstance() -> AssociatedTokenProgram.CreateIdempotent {
        .init(
            subsidizer: Self.subsidizer,
            address: Self.address,
            owner: Self.owner,
            mint: Self.mint,
        )
    }

    @Test("encode() emits a 1-byte command discriminator with value 0x01")
    func encodingDataLayout() {
        let encoded = makeInstance().encode()
        #expect(Array(encoded) == [0x01])
    }

    @Test("instruction() lays out the 7 accounts: subsidizer (write+signer), ATA (write), owner, mint, system, token, rent")
    func instructionAccountLayout() {
        let ix = makeInstance().instruction()
        #expect(ix.accounts.count == 7)

        #expect(ix.accounts[0].publicKey == Self.subsidizer)
        #expect(ix.accounts[0].isSigner == true)
        #expect(ix.accounts[0].isWritable == true)

        #expect(ix.accounts[1].publicKey == Self.address)
        #expect(ix.accounts[1].isWritable == true)
        #expect(ix.accounts[1].isSigner == false)

        #expect(ix.accounts[2].publicKey == Self.owner)
        #expect(ix.accounts[2].isWritable == false)

        #expect(ix.accounts[3].publicKey == Self.mint)
        #expect(ix.accounts[3].isWritable == false)

        #expect(ix.accounts[4].publicKey == SystemProgram.address)
        #expect(ix.accounts[5].publicKey == TokenProgram.address)
        #expect(ix.accounts[6].publicKey == SysVar.rent.address)
    }

    @Test("instruction() targets the associated token program")
    func instructionTargetsAtaProgram() {
        let ix = makeInstance().instruction()
        #expect(ix.program == AssociatedTokenProgram.address)
    }

    @Test("init(instruction:) round-trips all four key fields from a built instruction")
    func decodeRoundTrip() throws {
        let original = makeInstance()
        let decoded = try AssociatedTokenProgram.CreateIdempotent(instruction: original.instruction())

        #expect(decoded.subsidizer == Self.subsidizer)
        #expect(decoded.address == Self.address)
        #expect(decoded.owner == Self.owner)
        #expect(decoded.mint == Self.mint)
    }

    @Test("Convenience init derives the ATA address from owner + mint")
    func conveniencInitDerivesAddress() {
        let derived = AssociatedTokenProgram.CreateIdempotent(
            subsidizer: Self.subsidizer,
            owner: Self.owner,
            mint: Self.mint,
        )
        let expected = PublicKey.deriveAssociatedAccount(from: Self.owner, mint: Self.mint)!.publicKey
        #expect(derived.address == expected)
    }
}
