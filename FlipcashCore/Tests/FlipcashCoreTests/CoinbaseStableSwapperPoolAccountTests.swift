import Foundation
import Testing
@testable import FlipcashCore

@Suite("CoinbaseStableSwapperProgram.PoolAccount")
struct CoinbaseStableSwapperPoolAccountTests {

    /// Minimum account length: 8 discriminator + 32 ops authority
    /// + 32 pause authority + 32 fee recipient.
    private static let minimumLength = 8 + 32 + 32 + 32

    private static func accountData(feeRecipient: [UInt8], trailing: Int = 0) -> Data {
        var data = Data(repeating: 0xAA, count: 8)          // discriminator
        data.append(Data(repeating: 0xBB, count: 32))       // operations authority
        data.append(Data(repeating: 0xCC, count: 32))       // pause authority
        data.append(Data(feeRecipient))
        data.append(Data(repeating: 0xDD, count: trailing))
        return data
    }

    @Test("Parses the fee recipient at offset 72")
    func initAccountData_validLayout_parsesFeeRecipient() throws {
        let feeRecipientBytes = [UInt8](repeating: 7, count: 32)
        let account = try #require(
            CoinbaseStableSwapperProgram.PoolAccount(accountData: Self.accountData(feeRecipient: feeRecipientBytes))
        )
        #expect(account.feeRecipient == (try PublicKey(feeRecipientBytes)))
    }

    @Test("Tolerates trailing fields beyond the fee recipient")
    func initAccountData_trailingFields_parsesFeeRecipient() throws {
        let feeRecipientBytes = [UInt8](repeating: 9, count: 32)
        let account = try #require(
            CoinbaseStableSwapperProgram.PoolAccount(
                accountData: Self.accountData(feeRecipient: feeRecipientBytes, trailing: 128)
            )
        )
        #expect(account.feeRecipient == (try PublicKey(feeRecipientBytes)))
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
