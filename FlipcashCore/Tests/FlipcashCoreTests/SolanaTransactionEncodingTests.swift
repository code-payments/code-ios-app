//
//  SolanaTransactionEncodingTests.swift
//  FlipcashCoreTests
//

import Foundation
import Testing
@testable import FlipcashCore

@Suite("SolanaTransaction.encode wire-format pin")
struct SolanaTransactionEncodingTests {

    // MARK: - Fixtures

    private static let sender = try! PublicKey([UInt8](repeating: 1, count: 32))
    private static let owner = try! PublicKey([UInt8](repeating: 2, count: 32))
    private static let swapId = try! PublicKey([UInt8](repeating: 3, count: 32))
    private static let blockhashBytes = [UInt8](repeating: 99, count: 32)
    private static let blockhash = try! Hash(blockhashBytes)
    private static let amount: UInt64 = 20_000_000

    /// Base64 of `SolanaTransaction(payer:recentBlockhash:instructions:).encode()`
    /// for the USDC→USDF instruction set built below. Validated once against
    /// `SolanaSwift.Transaction.from(data:)`. Any change to this fixture is a
    /// wire-format regression — review before updating.
    private static let expectedBase64 = """
    AQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABAAsRAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQElKxrRNEbgnBPXjYIsz3543heVtrJ7qk60jnephMSLXSW1LhyrXvKR7ZrvLr3rsmS685lKl6lNUZldbIba6SQjOC53YOoR483gdl52u6nQIKu152HOENS474Mm9i7wRMHbfvI99eRIyyGS4m59c0LgJqE25ZYjms8D0axmFwMenOu0bQ63u+SVHuTupt0Tn5WfJP4aEUXaLXwGsE7QyU5nAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAADBkZv5SEXMv/srbpyw5vnvIzlu8X3EmssQ5s6QAAAAAVKU1D4XciC1hSlVnJ4iilt3x6rq9CmBniISTL07vagBqfVFxksXFEhjMlMPUrxf1ja7gibof1E49vZigAAAAAG3fbh12Whk9nL4UbO63msHLSF7V9bN5E6jPWFfv8AqQ2Lc7lEmSRk6i4IIysJGyanmbJ2Rxm4nOQ5fjYnlgt+PdPEgIo9T7OfrsnLpJtaY0pS7eEVSPUkqiDyzUbvgHF0Ty/Q1vVSYoO+s41dtnestYvXn68FewAAXoq4K9PCnIyXJY9OJInxuz0QKRSODYMLWhOZ2v8QhASOe9jb6fhZxvp6877brTo9ZfNqq8l0MbG75MLS9uDkfKYCA0UvXWHlmFP/nGQNRpk/zuVafE1Fcp/63ahMHcMVM7+lfr3orWNjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjCAcABQJADQMABwAJA+gDAAAAAAAADgcAAwAMBgoJAQEOBwACEAwGCgkBAQ4HAAUADwYKCQEBCAArQ2t0UnVRMm10dGdSR2tYSnR5a3NkS0hqVWRjMkM0VGdEenlCOThvRXp5OAsHAA0EAQMFCgoCAC0xAQAAAAAACgMDAgAJAwAtMQEAAAAA
    """

    private static let expectedBytes: Data = Data(base64Encoded: expectedBase64)!

    // MARK: - Test

    @Test("USDC→USDF instructions encode to a stable, wire-valid byte sequence")
    func usdcToUsdf_encodesToFixture() throws {
        let instructions = SwapInstructionBuilder.buildUsdcToUsdfSwapInstructions(
            sender: Self.sender,
            owner: Self.owner,
            amount: Self.amount,
            pool: .usdf,
            swapId: Self.swapId
        )

        let transaction = SolanaTransaction(
            payer: Self.sender,
            recentBlockhash: Self.blockhash,
            instructions: instructions
        )

        #expect(transaction.encode() == Self.expectedBytes)
    }

    @Test("Multi-table lookups compile instruction indexes in table-grouped order")
    func multiTableLookups_compileInTableGroupedOrder() throws {
        // Loaded accounts resolve on-chain grouped BY TABLE (every table's
        // writables, then every table's readonlys) — not in global sort
        // order. Arrange keys so the two orderings differ: the second table's
        // accounts sort lexicographically BEFORE the first table's.
        func key(_ seed: UInt8) -> PublicKey { try! PublicKey([UInt8](repeating: seed, count: 32)) }

        let payer = key(1)
        let program = key(2)
        let writableA = key(40) // in table A (sorts after writableB)
        let writableB = key(30) // in table B
        let readonlyA = key(41) // in table A (sorts after readonlyB)
        let readonlyB = key(31) // in table B

        let tableA = AddressLookupTable(publicKey: key(10), addresses: [writableA, readonlyA])
        let tableB = AddressLookupTable(publicKey: key(11), addresses: [writableB, readonlyB])

        let instruction = Instruction(
            program: program,
            accounts: [
                .writable(publicKey: writableA),
                .writable(publicKey: writableB),
                .readonly(publicKey: readonlyA),
                .readonly(publicKey: readonlyB),
            ],
            data: Data([7])
        )

        let transaction = SolanaTransaction(
            payer: payer,
            recentBlockhash: Self.blockhash,
            addressLookupTables: [tableA, tableB],
            instructions: [instruction]
        )

        guard case .versionedV0(let message) = transaction.message else {
            Issue.record("Expected a v0 message when lookup tables are provided")
            return
        }

        // Static: payer(0), program(1). Loaded: tableA.writable(2),
        // tableB.writable(3), tableA.readonly(4), tableB.readonly(5).
        #expect(message.staticAccountKeys == [payer, program])
        #expect(message.instructions[0].accountIndexes == [2, 3, 4, 5])

        #expect(message.addressTableLookups.count == 2)
        #expect(message.addressTableLookups[0].publicKey == tableA.publicKey)
        #expect(message.addressTableLookups[0].writableIndexes == [0])
        #expect(message.addressTableLookups[0].readonlyIndexes == [1])
        #expect(message.addressTableLookups[1].publicKey == tableB.publicKey)
        #expect(message.addressTableLookups[1].writableIndexes == [0])
        #expect(message.addressTableLookups[1].readonlyIndexes == [1])
    }

    @Test("Round-trip: encoded bytes decode back into an equivalent transaction")
    func encodeDecode_roundTrips() throws {
        let instructions = SwapInstructionBuilder.buildUsdcToUsdfSwapInstructions(
            sender: Self.sender,
            owner: Self.owner,
            amount: Self.amount,
            pool: .usdf,
            swapId: Self.swapId
        )

        let original = SolanaTransaction(
            payer: Self.sender,
            recentBlockhash: Self.blockhash,
            instructions: instructions
        )

        let encoded = original.encode()
        let decoded = try #require(SolanaTransaction(data: encoded))

        #expect(decoded.encode() == encoded)
        #expect(decoded.recentBlockhash == Self.blockhash)
        #expect(decoded.message.accountKeys.count == original.message.accountKeys.count)
        #expect(decoded.message.accountKeys.first == Self.sender)
        #expect(decoded.message.instructions.count == instructions.count)
    }
}
