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
    /// for the deterministic USDC→USDF instruction set built below. Validated
    /// once against `SolanaSwift.Transaction.from(data:)` — those bytes
    /// round-trip through a known-correct legacy-message parser. Any change
    /// to this fixture means the encoder, the swap-instruction builder, or
    /// the legacy-message account ordering has changed; either is a wire-
    /// format regression that needs a deliberate review before this test is
    /// updated.
    private static let expectedBase64 = """
    AQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABAAsRAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQElKxrRNEbgnBPXjYIsz3543heVtrJ7qk60jnephMSLXSW1LhyrXvKR7ZrvLr3rsmS685lKl6lNUZldbIba6SQjOC53YOoR483gdl52u6nQIKu152HOENS474Mm9i7wRMHbfvI99eRIyyGS4m59c0LgJqE25ZYjms8D0axmFwMenOu0bQ63u+SVHuTupt0Tn5WfJP4aEUXaLXwGsE7QyU5nAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAADBkZv5SEXMv/srbpyw5vnvIzlu8X3EmssQ5s6QAAAAAVKU1D4XciC1hSlVnJ4iilt3x6rq9CmBniISTL07vagBqfVFxksXFEhjMlMPUrxf1ja7gibof1E49vZigAAAAAG3fbh12Whk9nL4UbO63msHLSF7V9bN5E6jPWFfv8AqQ2Lc7lEmSRk6i4IIysJGyanmbJ2Rxm4nOQ5fjYnlgt+PdPEgIo9T7OfrsnLpJtaY0pS7eEVSPUkqiDyzUbvgHF0Ty/Q1vVSYoO+s41dtnestYvXn68FewAAXoq4K9PCnIyXJY9OJInxuz0QKRSODYMLWhOZ2v8QhASOe9jb6fhZxvp6877brTo9ZfNqq8l0MbG75MLS9uDkfKYCA0UvXWHlmFP/nGQNRpk/zuVafE1Fcp/63ahMHcMVM7+lfr3orWNjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjCAcABQJADQMABwAJA+gDAAAAAAAADgcAAwAMBgoJAQEOBwACEAwGCgkBAQ4HAAUADwYKCQEBCAArQ2t0UnVRMm10dGdSR2tYSnR5a3NkS0hqVWRjMkM0VGdEenlCOThvRXp5OAsHAA0EAQMFCgoCAC0xAQAAAAAACgMDAgAJAwAtMQEAAAAA
    """

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

        let encoded = transaction.encode()
        let expected = try #require(Data(base64Encoded: Self.expectedBase64))
        #expect(encoded == expected)
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
