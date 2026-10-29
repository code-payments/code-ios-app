import Foundation
import Testing
@testable import FlipcashCore

@Suite("IntentLogID")
struct IntentLogIDTests {

    private let id = PublicKey.generate()!

    @Test("A sensitive intent ID logs only its last six characters until it succeeds")
    func sensitiveMasksUntilSettled() {
        let logID = IntentLogID(id: id, isSensitive: true)

        #expect(logID.pending == "…" + String(id.base58.suffix(6)))
        #expect(!logID.pending.contains(id.base58))
        #expect(logID.settled == id.base58)
    }

    @Test("A normal intent ID logs in full before and after it settles")
    func normalLogsInFull() {
        let logID = IntentLogID(id: id, isSensitive: false)

        #expect(logID.pending == id.base58)
        #expect(logID.settled == id.base58)
    }
}
