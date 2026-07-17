//
//  CurrencyCreatorProgramSellTokensTests.swift
//  FlipcashCoreTests
//

import Foundation
import Testing
@testable import FlipcashCore

@Suite("CurrencyCreatorProgram.SellTokens")
struct CurrencyCreatorProgramSellTokensTests {

    private static func key(_ seed: UInt8) -> PublicKey {
        try! PublicKey([UInt8](repeating: seed, count: 32))
    }

    private static let seller       = key(1)
    private static let pool         = key(2)
    private static let targetMint   = key(3)
    private static let baseMint     = key(4)
    private static let vaultTarget  = key(5)
    private static let vaultBase    = key(6)
    private static let sellerTarget = key(7)
    private static let sellerBase   = key(8)

    private func makeInstance(inAmount: UInt64, minAmountOut: UInt64) -> CurrencyCreatorProgram.SellTokens {
        CurrencyCreatorProgram.SellTokens(
            seller: Self.seller,
            pool: Self.pool,
            targetMint: Self.targetMint,
            baseMint: Self.baseMint,
            vaultTarget: Self.vaultTarget,
            vaultBase: Self.vaultBase,
            sellerTarget: Self.sellerTarget,
            sellerBase: Self.sellerBase,
            inAmount: inAmount,
            minAmountOut: minAmountOut
        )
    }

    @Test("Opcode is 5 and data layout is opcode + inAmount + minAmountOut")
    func encoding_dataLayout() {
        let data = makeInstance(inAmount: 1_000_000, minAmountOut: 0).encode()

        #expect(data.count == 17)
        #expect(data[0] == CurrencyCreatorProgram.Command.sellTokens.rawValue)
        #expect(UInt64(bytes: Array(data[1..<9])) == 1_000_000)
        #expect(UInt64(bytes: Array(data[9..<17])) == 0)
    }

    @Test("Round-trip encode/decode preserves every field")
    func roundTrip() throws {
        let original = makeInstance(inAmount: 42, minAmountOut: 7)
        let parsed = try CurrencyCreatorProgram.SellTokens(instruction: original.instruction())
        #expect(parsed == original)
    }

    @Test("Account order matches OCP SellTokensInstructionAccounts")
    func accountOrder() {
        let accounts = makeInstance(inAmount: 1, minAmountOut: 0).instruction().accounts

        #expect(accounts.count == 9)

        #expect(accounts[0].publicKey == Self.seller)
        #expect(accounts[0].isSigner == true)
        #expect(accounts[0].isWritable == true)

        #expect(accounts[1].publicKey == Self.pool)
        #expect(accounts[1].isWritable == true)
        #expect(accounts[1].isSigner == false)

        #expect(accounts[2].publicKey == Self.targetMint)
        #expect(accounts[2].isWritable == false)

        #expect(accounts[3].publicKey == Self.baseMint)
        #expect(accounts[3].isWritable == false)

        #expect(accounts[4].publicKey == Self.vaultTarget)
        #expect(accounts[4].isWritable == true)

        #expect(accounts[5].publicKey == Self.vaultBase)
        #expect(accounts[5].isWritable == true)

        #expect(accounts[6].publicKey == Self.sellerTarget)
        #expect(accounts[6].isWritable == true)

        #expect(accounts[7].publicKey == Self.sellerBase)
        #expect(accounts[7].isWritable == true)

        #expect(accounts[8].publicKey == TokenProgram.address)
        #expect(accounts[8].isWritable == false)
        #expect(accounts[8].isSigner == false)
    }

    @Test("Program address is the CurrencyCreator program")
    func programAddress() {
        #expect(makeInstance(inAmount: 1, minAmountOut: 0).instruction().program == CurrencyCreatorProgram.address)
    }

    @Test("Decoding rejects a truncated payload")
    func decode_truncatedPayload_throws() {
        var instruction = makeInstance(inAmount: 1, minAmountOut: 0).instruction()
        instruction.data = instruction.data.prefix(9) // opcode + half of inAmount

        #expect(throws: (any Error).self) {
            try CurrencyCreatorProgram.SellTokens(instruction: instruction)
        }
    }

    @Test("Decoding rejects a wrong account count")
    func decode_wrongAccountCount_throws() {
        var instruction = makeInstance(inAmount: 1, minAmountOut: 0).instruction()
        instruction.accounts = Array(instruction.accounts.dropLast())

        #expect(throws: (any Error).self) {
            try CurrencyCreatorProgram.SellTokens(instruction: instruction)
        }
    }
}
