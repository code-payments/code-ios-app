//
//  LegacyMessageDecodingTests.swift
//  FlipcashCoreTests
//

import Foundation
import Testing
@testable import FlipcashCore

@Suite("LegacyMessage decoding")
struct LegacyMessageDecodingTests {

    // MARK: - Fixtures

    private static func testKey(_ seed: Int) -> PublicKey {
        try! PublicKey([UInt8](repeating: UInt8(seed), count: 32))
    }

    // MARK: - Tests

    @Test("Encode then decode round-trips header, accounts, and blockhash")
    func encodeDecode_roundTrips() throws {
        let payer = Self.testKey(1)
        let other = Self.testKey(2)
        let program = Self.testKey(9)
        let blockhash = try Hash([UInt8](repeating: 3, count: 32))

        let instruction = Instruction(
            program: program,
            accounts: [
                .writable(publicKey: payer, signer: true),
                .writable(publicKey: other),
            ],
            data: Data([1, 2, 3])
        )

        let message = LegacyMessage(
            accounts: [
                .payer(publicKey: payer),
                .program(publicKey: program),
                .writable(publicKey: payer, signer: true),
                .writable(publicKey: other),
            ],
            recentBlockhash: blockhash,
            instructions: [instruction]
        )

        let decoded = try #require(LegacyMessage(data: message.encode()))

        #expect(decoded.header == message.header)
        #expect(decoded.accounts.map(\.publicKey) == message.accounts.map(\.publicKey))
        #expect(decoded.recentBlockhash == message.recentBlockhash)
    }

    @Test("Account count exceeding remaining data returns nil")
    func truncatedAccounts_returnsNil() {
        var data = Data([1, 0, 1])
        data.append(ShortVec.encodeLength(10))
        data.append(Data(repeating: 7, count: PublicKey.length))

        #expect(LegacyMessage(data: data) == nil)
    }
}
