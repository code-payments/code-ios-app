import Foundation
import Testing
@testable import FlipcashCore

@Suite("CoinbaseStableSwapperProgram.PoolAccount")
struct CoinbaseStableSwapperPoolAccountTests {

    /// `sha256("account:LiquidityPool")[0..8]` — the real Anchor discriminator for this account.
    private static let discriminator: [UInt8] = [66, 38, 17, 64, 188, 80, 68, 129]

    /// Minimum account length: 8 discriminator + 32 operations authority + 32 pause authority
    /// + 32 unnamed pubkey + 32 unnamed pubkey + 32 fee recipient.
    private static let minimumLength = 8 + 32 + 32 + 32 + 32 + 32

    /// Base64 of the first 168 bytes (discriminator through `fee_recipient`) of the real
    /// pool account `CrDL9SoCyW1tBgn8k7rgGSpWhnszneWDbvKvqPAU4PL9`, captured from mainnet.
    private static let realCapturedAccountDataBase64 = """
    QiYRQLxQRIEFHqE9vluQFKO1wbEwnd22aRe9qGrV03SIsz1AV7GqT/yEzcR/f+ALaKG4KMxbBfZ5dTNFPqxxZHMfbTqNfj6St0p++yObz2IILMcKsoko07O+oRSDek7YwzrH9TroL1+QbHdT/t9qpcq4Kyx8OPWZm79AIUM9UlN+X6ujF0hPgzT4z8SXtrVTfBhZj7LzSPTgCpHoi6cjfPqXvflOJvRB
    """

    private static func accountData(
        feeRecipient: [UInt8],
        discriminator: [UInt8] = Self.discriminator,
        trailing: Int = 0
    ) -> Data {
        var data = Data(discriminator)
        data.append(Data(repeating: 0xBB, count: 32))       // operations_authority
        data.append(Data(repeating: 0xCC, count: 32))       // pause_authority
        data.append(Data(repeating: 0xEE, count: 32))       // unnamed pubkey (offset 72)
        data.append(Data(repeating: 0xFA, count: 32))       // unnamed pubkey (offset 104)
        data.append(Data(feeRecipient))
        data.append(Data(repeating: 0xDD, count: trailing))
        return data
    }

    @Test(
        "Parses the fee recipient at offset 136, with or without trailing fields",
        arguments: [0, 128]
    )
    func initAccountData_validLayout_parsesFeeRecipient(trailing: Int) throws {
        let feeRecipientBytes = [UInt8](repeating: 7, count: 32)
        let account = try #require(
            CoinbaseStableSwapperProgram.PoolAccount(
                accountData: Self.accountData(feeRecipient: feeRecipientBytes, trailing: trailing)
            )
        )
        #expect(account.feeRecipient == (try PublicKey(feeRecipientBytes)))
    }

    @Test("Decodes the real pool account and recovers the correct fee recipient")
    func initAccountData_realCapturedAccount_parsesFeeRecipient() throws {
        let data = try #require(Data(base64Encoded: Self.realCapturedAccountDataBase64))
        let account = try #require(CoinbaseStableSwapperProgram.PoolAccount(accountData: data))
        #expect(account.feeRecipient == (try PublicKey(base58: "4ZnFXk7KyB5khDqjWSHqHBQH1nQCnmvkr1pRFivWcP7e")))
    }

    @Test("Rejects account data shorter than the fee recipient bounds")
    func initAccountData_shortData_returnsNil() {
        let short = Self.accountData(feeRecipient: [UInt8](repeating: 7, count: 32))
            .prefix(Self.minimumLength - 1)
        #expect(CoinbaseStableSwapperProgram.PoolAccount(accountData: Data(short)) == nil)
    }

    @Test("Rejects a discriminator that doesn't match LiquidityPool")
    func initAccountData_mismatchedDiscriminator_returnsNil() {
        let wrongDiscriminator = [UInt8](repeating: 0, count: 8)
        let data = Self.accountData(
            feeRecipient: [UInt8](repeating: 7, count: 32),
            discriminator: wrongDiscriminator
        )
        #expect(CoinbaseStableSwapperProgram.PoolAccount(accountData: data) == nil)
    }

    @Test("Ignores slice offsets — parses relative to the data's start")
    func initAccountData_dataSlice_parsesRelativeToStart() throws {
        let feeRecipientBytes = [UInt8](repeating: 5, count: 32)
        var padded = Data(repeating: 0xFF, count: 16)
        padded.append(Self.accountData(feeRecipient: feeRecipientBytes))
        let slice = padded[16...]

        let account = try #require(CoinbaseStableSwapperProgram.PoolAccount(accountData: slice))
        #expect(account.feeRecipient == (try PublicKey(feeRecipientBytes)))
    }
}
