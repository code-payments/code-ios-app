import Testing
import Foundation
@testable import FlipcashCore

@Suite("BlockedUserProfile")
struct BlockedUserProfileTests {

    @Test("Holds identity, block time, and minimal display fields")
    func fields() {
        let id = UUID()
        let at = Date(timeIntervalSince1970: 1_700_000_000)
        let p = BlockedUserProfile(userID: id, blockedAt: at, displayName: "Fred Wilson", avatarBlurhash: "L6")
        #expect(p.userID == id)
        #expect(p.blockedAt == at)
        #expect(p.displayName == "Fred Wilson")
        #expect(p.avatarBlurhash == "L6")
    }
}
