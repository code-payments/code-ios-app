//
//  ProfilePinnedActionTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("ProfilePinnedAction")
struct ProfilePinnedActionTests {

    private let fee = FiatAmount(value: Decimal(string: "0.50")!, currency: .usd)
    private let dmID = ConversationID(data: Data(repeating: 7, count: 32))

    @Test("The viewer's own profile pins nothing")
    func isSelf_none() {
        #expect(ProfilePinnedAction.resolve(isSelf: true, isBlocked: false, dmID: dmID, fee: fee) == .none)
    }

    @Test("A blocked profile pins Unblock whether or not a DM exists", arguments: [true, false])
    func blocked_unblock(hasDM: Bool) {
        let action = ProfilePinnedAction.resolve(isSelf: false, isBlocked: true, dmID: hasDM ? dmID : nil, fee: fee)
        #expect(action == .unblock)
    }

    @Test("An existing DM pins Open Chat")
    func dm_openChat() {
        let action = ProfilePinnedAction.resolve(isSelf: false, isBlocked: false, dmID: dmID, fee: fee)
        #expect(action == .openChat(dmID))
    }

    @Test("No DM and a fee pins the priced start")
    func noDM_fee_startChatting() {
        let action = ProfilePinnedAction.resolve(isSelf: false, isBlocked: false, dmID: nil, fee: fee)
        #expect(action == .startChatting(fee))
    }

    @Test("No DM and no fee pins the unpriced start")
    func noDM_noFee_unpriced() {
        let action = ProfilePinnedAction.resolve(isSelf: false, isBlocked: false, dmID: nil, fee: nil)
        #expect(action == .startChattingUnpriced)
    }

    @Test("Labels")
    func labels() {
        #expect(ProfilePinnedAction.startChatting(fee).title == "Send \(fee.formatted()) to Start Chatting")
        #expect(ProfilePinnedAction.startChattingUnpriced.title == "Start Chatting")
        #expect(ProfilePinnedAction.openChat(dmID).title == "Open Chat")
        #expect(ProfilePinnedAction.unblock.title == "Unblock")
        #expect(ProfilePinnedAction.none.title == nil)
    }
}
