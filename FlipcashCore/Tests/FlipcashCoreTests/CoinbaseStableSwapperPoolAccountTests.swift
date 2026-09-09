import Foundation
import Testing
@testable import FlipcashCore

@Suite("CoinbaseStableSwapperProgram.PoolAccount")
struct CoinbaseStableSwapperPoolAccountTests {

    /// Minimum account length: 8 discriminator + 32 pause authority
    /// + 32 unpause authority + 32 treasury authority + 32 configure authority
    /// + 32 fee recipient.
    private static let minimumLength = 8 + 32 * 5

    /// First 315 bytes of mainnet pool CrDL9SoCyW1tBgn8k7rgGSpWhnszneWDbvKvqPAU4PL9
    /// after the 2026-09-08 MigrateAuthorities instruction. The live account is
    /// 2107 bytes with the remainder zeroed.
    private static let mainnetPoolPrefix =
        "QiYRQLxQRIEFHqE9vluQFKO1wbEwnd22aRe9qGrV03SIsz1AV7GqT/yEzcR/f+ALaKG4KMxbBfZ5dTNFPqxxZHMfbTqNfj6St0p+" +
        "+yObz2IILMcKsoko07O+oRSDek7YwzrH9TroL1+QbHdT/t9qpcq4Kyx8OPWZm79AIUM9UlN+X6ujF0hPgzT4z8SXtrVTfBhZj7Lz" +
        "SPTgCpHoi6cjfPqXvflOJvRBAgAAAN0H70q0C5DeChX575Umuo4KwnYx+lqZmPTGnq1wMK2QSoyv1lJlvQkMgeq0VkN3NML2MHaz" +
        "cTzSusODf5c6RhACAAAAxvp6877brTo9ZfNqq8l0MbG75MLS9uDkfKYCA0UvXWE908SAij1Ps5+uycukm1pjSlLt4RVI9SSqIPLN" +
        "Ru+AcQAAAAAAAAAAAAD/"

    private static func accountData(feeRecipient: [UInt8], trailing: Int = 0) -> Data {
        var data = Data(repeating: 0xAA, count: 8)          // discriminator
        data.append(Data(repeating: 0xBB, count: 32))       // pause authority
        data.append(Data(repeating: 0xCC, count: 32))       // unpause authority
        data.append(Data(repeating: 0xEE, count: 32))       // treasury authority
        data.append(Data(repeating: 0x11, count: 32))       // configure authority
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

    @Test("Parses the fee recipient from the migrated mainnet pool account")
    func initAccountData_mainnetPool_parsesFeeRecipient() throws {
        let prefix = try #require(Data(base64Encoded: Self.mainnetPoolPrefix))
        #expect(prefix.count == 315)
        var data = prefix
        data.append(Data(repeating: 0, count: 2107 - prefix.count))

        let account = try #require(CoinbaseStableSwapperProgram.PoolAccount(accountData: data))
        #expect(account.feeRecipient == (try PublicKey(base58: "4ZnFXk7KyB5khDqjWSHqHBQH1nQCnmvkr1pRFivWcP7e")))
    }

    @Test("Rejects account data shorter than the fee recipient bounds")
    func initAccountData_shortData_returnsNil() {
        let short = Data(repeating: 0xAA, count: Self.minimumLength - 1)
        #expect(CoinbaseStableSwapperProgram.PoolAccount(accountData: short) == nil)
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
