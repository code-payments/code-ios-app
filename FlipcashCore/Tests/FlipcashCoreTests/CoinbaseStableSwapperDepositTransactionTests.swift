//
//  CoinbaseStableSwapperDepositTransactionTests.swift
//  FlipcashCoreTests
//

import Foundation
import Testing
@testable import FlipcashCore

/// Pins the bytes an external-wallet USDC deposit puts on the wire, starting from the real
/// pool account rather than a hand-written fee recipient.
///
/// The chain under test is the one the deep-link deposit runs: parse the pool account, take
/// `fee_recipient` out of it, build the USDC→USDF swap against the VM deposit, encode. A wrong
/// offset in `PoolAccount` yields a valid-looking `PublicKey` and a transaction that encodes
/// fine, so only the end-to-end bytes catch it.
///
/// The deposit swap is `swap_v2` (15 accounts, no whitelist). The expected bytes are
/// builder-derived: there is no on-chain `swap_v2` capture for this transaction yet. The
/// previous `swap` (v1) version of these bytes was accepted by `simulateTransaction` on mainnet
/// (no error, 68922 compute units, `Swapped 5000000 tokens`), and reading `fee_recipient` at the
/// offset the published IDL implies instead failed that simulation with `ConstraintAddress`
/// (2012). Re-simulate the v2 bytes before relying on them as a mainnet-accepted vector.
@Suite("CoinbaseStableSwapper deposit transaction bytes")
struct CoinbaseStableSwapperDepositTransactionTests {

    // MARK: - Fixtures

    /// Base64 of the first 168 bytes (discriminator through `fee_recipient`) of the real pool
    /// account `CrDL9SoCyW1tBgn8k7rgGSpWhnszneWDbvKvqPAU4PL9`, captured from mainnet.
    private static let poolAccountBase64 = """
    QiYRQLxQRIEFHqE9vluQFKO1wbEwnd22aRe9qGrV03SIsz1AV7GqT/yEzcR/f+ALaKG4KMxbBfZ5dTNFPqxxZHMfbTqNfj6St0p++yObz2IILMcKsoko07O+oRSDek7YwzrH9TroL1+QbHdT/t9qpcq4Kyx8OPWZm79AIUM9UlN+X6ujF0hPgzT4z8SXtrVTfBhZj7LzSPTgCpHoi6cjfPqXvflOJvRB
    """

    /// A mainnet wallet with a USDC balance, so these bytes can be replayed through
    /// `simulateTransaction` unchanged when the pool or the program moves.
    private static let sender = try! PublicKey(base58: "13V7ou4zHHwDVaAGWxqHSwU2sVzRR4m62XWqCFxhA5fD")
    private static let owner = try! PublicKey([UInt8](repeating: 7, count: 32))
    private static let swapId = try! PublicKey([UInt8](repeating: 9, count: 32))
    private static let blockhash = try! Hash([UInt8](repeating: 99, count: 32))
    private static let amount: UInt64 = 5_000_000

    /// Any change here is a wire-format change on the deposit path. Re-simulate before updating.
    /// Builder-derived `swap_v2` bytes; see the suite comment.
    private static let expectedBase64 = """
    AQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABAA4VAKL0PLpNizvAoz6QRhxwuE+0xI1gTXBS8xC2iFAT9YAIIEbBeYxANDSqQKEPw/bim+87xyfndOcR1Z8MXipwRQhN3zo5EjvB3buXfyApNPeiOya5xLRmU4amnmybe8G0ZvC2QXkvoK+rzDvts+c808FFOCj9M+Gw1VaTwlFFQuCIGuzkYUNbUsQHluSoCkWyRnCKUYxj6p9wIBIqXQISoIsQLEV0nZ6/A9+EnNdx0SgwdXMN9srCBKAsQrgkmUgy/UHEeoQ9iL75ZI2OJCdbgb8cuXN12zjqg9u576KCFfMAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAMGRm/lIRcy/+ytunLDm+e8jOW7xfcSayxDmzpAAAAABUpTUPhdyILWFKVWcniKKW3fHqur0KYGeIhJMvTu9qAGp9UXGSxcUSGMyUw9SvF/WNruCJuh/UTj29mKAAAAAAbd9uHXZaGT2cvhRs7reawctIXtX1s3kTqM9YV+/wCpDEFZLOrgP4XlL2Cp/OoiptfGnqhwN8d2wUpZw0Pc/EQXrHn35X2ZhEB0QDeeHO4EVQ94zdMsrvVy1q+XDO+XnCuKEXJELwMYhHcwB4CqMwj+zD6MwkrlErJ/0Le6FUYqNPjPxJe2tVN8GFmPsvNI9OAKkeiLpyN8+pe9+U4m9EE908SAij1Ps5+uycukm1pjSlLt4RVI9SSqIPLNRu+AcYyXJY9OJInxuz0QKRSODYMLWhOZ2v8QhASOe9jb6fhZsAv1H/nJezKQ1MsvZdgtk2ADZkchGXY0muvR9OrxRba9RisE/6dQ2FdZLElujNnDg858Wn5R9em05xQ2Tb0ZL8b6evO+2606PWXzaqvJdDGxu+TC0vbg5HymAgNFL11hY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2MICAAFAkANAwAIAAkD6AMAAAAAAAARBwAEABAHCwoBAREHAAUTEAcLCgEBEQcAAwAUBwsKAQEJACtjR2ZIaUM2S2dnM0ZwRlp2Z3dHY3N3c0NSdHA0YUJQMmZ6dVhSUVBpenVODA8SDQ4BAgMEBg8UEAALEQcYKwTtCxrJHmJAS0wAAAAAAEBLTAAAAAAACwMEBQAJA0BLTAAAAAAA
    """

    // MARK: - Tests

    @Test("The real pool account yields the fee recipient the program enforces")
    func poolAccount_parsesDeployedFeeRecipient() throws {
        let data = try #require(Data(base64Encoded: Self.poolAccountBase64))
        let pool = try #require(CoinbaseStableSwapperProgram.PoolAccount(accountData: data))
        #expect(pool.feeRecipient == (try PublicKey(base58: "4ZnFXk7KyB5khDqjWSHqHBQH1nQCnmvkr1pRFivWcP7e")))
    }

    @Test("Pool bytes through to encoded transaction produce the simulated byte sequence")
    func depositTransaction_encodesToFixture() throws {
        let data = try #require(Data(base64Encoded: Self.poolAccountBase64))
        let pool = try #require(CoinbaseStableSwapperProgram.PoolAccount(accountData: data))

        let instructions = SwapInstructionBuilder.buildUsdcToUsdfSwapInstructions(
            sender: Self.sender,
            owner: Self.owner,
            amount: Self.amount,
            pool: .coinbaseStableSwapper(feeRecipient: pool.feeRecipient),
            swapId: Self.swapId,
            destination: .vmDeposit
        )

        let transaction = SolanaTransaction(
            payer: Self.sender,
            recentBlockhash: Self.blockhash,
            instructions: instructions
        )

        #expect(instructions.count == 8)
        #expect(instructions[6].data.prefix(8).elementsEqual(CoinbaseStableSwapperProgram.SwapV2.discriminator))
        #expect(instructions[6].accounts.count == 15)
        #expect(transaction.encode() == (try #require(Data(base64Encoded: Self.expectedBase64))))
    }

    @Test("The encoded transaction fits in a single packet")
    func depositTransaction_fitsPacketLimit() throws {
        let data = try #require(Data(base64Encoded: Self.expectedBase64))
        #expect(data.count <= 1232)
    }
}
