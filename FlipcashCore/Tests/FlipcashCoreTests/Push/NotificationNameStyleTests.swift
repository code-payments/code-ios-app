import Testing
import FlipcashAPI
@testable import FlipcashCore

@Suite("NotificationNameStyle")
struct NotificationNameStyleTests {

    @Test("CONTACT_JOIN uses the full name")
    func contactJoinIsFull() {
        #expect(Flipcash_Push_V1_Payload.Category.contactJoin.nameStyle == .full)
    }

    @Test("CHAT (sent you cash) uses the first name only")
    func chatIsFirstOnly() {
        #expect(Flipcash_Push_V1_Payload.Category.chat.nameStyle == .firstOnly)
    }

    @Test("Non-contact categories default to the full name")
    func othersDefaultToFull() {
        #expect(Flipcash_Push_V1_Payload.Category.default.nameStyle == .full)
        #expect(Flipcash_Push_V1_Payload.Category.depositWithdrawal.nameStyle == .full)
        #expect(Flipcash_Push_V1_Payload.Category.buySell.nameStyle == .full)
        #expect(Flipcash_Push_V1_Payload.Category.gain.nameStyle == .full)
    }
}
