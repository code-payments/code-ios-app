//
//  SystemProgramAdvanceNonceTests.swift
//  FlipcashCore
//

import Foundation
import Testing
@testable import FlipcashCore

@Suite("SystemProgram.AdvanceNonce")
struct SystemProgramAdvanceNonceTests {

    private static let nonce     = try! PublicKey(base58: "JACkaKsm2Rd6TNJwH4UB7G6tHrWUATJPTgNNnRVsg4ip")
    private static let authority = try! PublicKey(base58: "cash11ndAmdKFEnG2wrQQ5Zqvr1kN9htxxLyoPLYFUV")

    private func makeInstance() -> SystemProgram.AdvanceNonce {
        .init(nonce: Self.nonce, authority: Self.authority)
    }

    @Test("encode() emits the 4-byte advanceNonceAccount command")
    func encodingDataLayout() {
        let encoded = makeInstance().encode()
        let expectedBytes = SystemProgram.Command.advanceNonceAccount.rawValue.bytes
        #expect(encoded.count == expectedBytes.count)
        #expect(Array(encoded) == expectedBytes)
    }

    @Test("instruction() targets the system program with 3 accounts: nonce, recentBlockhashes sysvar, authority signer")
    func instructionAccountLayout() {
        let ix = makeInstance().instruction()
        #expect(ix.program == SystemProgram.address)
        #expect(ix.accounts.count == 3)

        #expect(ix.accounts[0].publicKey == Self.nonce)
        #expect(ix.accounts[0].isWritable == true)

        #expect(ix.accounts[1].publicKey == SysVar.recentBlockhashes.address)
        #expect(ix.accounts[1].isWritable == false)

        #expect(ix.accounts[2].publicKey == Self.authority)
        #expect(ix.accounts[2].isSigner == true)
    }

    @Test("init(instruction:) round-trips nonce and authority (sysvar at index 1 is intentionally skipped)")
    func decodeRoundTrip() throws {
        let original = makeInstance()
        let decoded = try SystemProgram.AdvanceNonce(instruction: original.instruction())
        #expect(decoded == original)
    }
}
