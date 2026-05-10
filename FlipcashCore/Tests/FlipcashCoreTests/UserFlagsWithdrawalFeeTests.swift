import Testing
@testable import FlipcashCore
import FlipcashAPI

@Suite("UserFlags.withdrawalFeeAmount")
struct UserFlagsWithdrawalFeeTests {

    @Test("Populates from proto in USDF quarks")
    func withdrawalFeeAmount_populatesFromProto() {
        let proto = Flipcash_Account_V1_UserFlags.with {
            $0.withdrawalFeeAmount = 50_000   // 0.05 USDF in quarks (6 decimals)
        }

        let flags = UserFlags(proto)

        #expect(flags.withdrawalFeeAmount.quarks == 50_000)
        #expect(flags.withdrawalFeeAmount.mint == .usdf)
    }

    @Test("Zero value is preserved verbatim")
    func withdrawalFeeAmount_zeroPreserved() {
        let proto = Flipcash_Account_V1_UserFlags()

        let flags = UserFlags(proto)

        #expect(flags.withdrawalFeeAmount.quarks == 0)
        #expect(flags.withdrawalFeeAmount.mint == .usdf)
    }
}
