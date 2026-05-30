import Testing
@testable import FlipcashCore
import FlipcashAPI

@Suite("UserFlags.enablePhoneNumberSend")
struct UserFlagsEnablePhoneNumberSendTests {

    @Test("Maps enablePhoneNumberSend from the proto")
    func enablePhoneNumberSend_mapsFromProto() {
        let enabled = UserFlags(Flipcash_Account_V1_UserFlags.with { $0.enablePhoneNumberSend = true })
        #expect(enabled.enablePhoneNumberSend)

        let unset = UserFlags(Flipcash_Account_V1_UserFlags())
        #expect(unset.enablePhoneNumberSend == false)
    }
}
