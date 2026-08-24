import Testing
@testable import FlipcashCore
import FlipcashAPI

@Suite("UserFlags.usernameMinBalance")
struct UserFlagsUsernameMinBalanceTests {

    @Test("Populates from proto in USDF quarks")
    func usernameMinBalance_populatesFromProto() {
        let proto = Flipcash_Account_V1_UserFlags.with {
            $0.usernameMinBalance = 5_000_000   // 5 USDF in quarks (6 decimals)
        }

        let flags = UserFlags(proto)

        #expect(flags.usernameMinBalance.quarks == 5_000_000)
        #expect(flags.usernameMinBalance.mint == .usdf)
    }

    @Test("Zero value is preserved verbatim")
    func usernameMinBalance_zeroPreserved() {
        let proto = Flipcash_Account_V1_UserFlags()

        let flags = UserFlags(proto)

        #expect(flags.usernameMinBalance.quarks == 0)
        #expect(flags.usernameMinBalance.mint == .usdf)
    }
}
