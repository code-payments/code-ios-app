//
//  ActivityRowReturnTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@Suite("Activity row for a sent-back payment")
struct ActivityRowReturnTests {

    private let dm = ConversationID.test(3)

    private func activity(_ kind: Activity.Kind, returned: Bool) -> Activity {
        Activity(
            id: .jeffy,
            state: .completed,
            kind: kind,
            title: "Sent $5",
            exchangedFiat: .mockOne,
            date: .now,
            metadata: nil,
            returnedPayment: returned ? .init(conversationID: dm, messageID: MessageID(value: 1)) : nil
        )
    }

    private func title(_ kind: Activity.Kind, name: String?) -> String? {
        ActivityRow.title(kind: kind, boostedReaction: nil, name: name, chatName: nil, serverTitle: "Sent $5", isReturn: true)
    }

    @Test("16: the side that sent it back reads 'Sent back to <Name>' and opens the DM")
    func sentSide() {
        #expect(title(.gave, name: "Alex Morgan") == "Sent back to Alex Morgan")
        #expect(ActivityRow.destination(for: activity(.gave, returned: true), dmExists: true) == .tipConversation(dm))
    }

    @Test("17: the side it was returned to reads '<Name> sent back' and opens the DM")
    func receivedSide() {
        #expect(title(.received, name: "Alex Morgan") == "Alex Morgan sent back")
        #expect(ActivityRow.destination(for: activity(.received, returned: true), dmExists: true) == .tipConversation(dm))
    }

    @Test("An unresolved name falls back to the server's title")
    func unknownName() {
        #expect(title(.gave, name: nil) == nil)
        #expect(title(.received, name: "") == nil)
    }

    @Test("A return whose DM is gone, and any other row, opens the details screen")
    func detailsFallback() {
        let gone = activity(.gave, returned: true)
        #expect(ActivityRow.destination(for: gone, dmExists: false) == .transactionDetails(gone))
        let plain = activity(.gave, returned: false)
        #expect(ActivityRow.destination(for: plain, dmExists: true) == .transactionDetails(plain))
    }
}
