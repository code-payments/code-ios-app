//
//  DMRouteTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

/// A transaction's counterpart opens their profile until a DM with them exists, and the DM after that.
@MainActor
@Suite("DM route")
struct DMRouteTests {

    @Test("Without a DM, the route is the profile")
    func withoutDMIsTheProfile() {
        let userID = UUID()
        #expect(DMRoute.destination(for: userID, dmID: nil, origin: .transaction) == .userProfile(userID, origin: .transaction))
    }

    @Test("With a DM, the route is the chat")
    func withDMIsTheChat() {
        let (me, them) = (UUID(), UUID())
        let dmID = ConversationID.tipDm(between: me, and: them)
        #expect(DMRoute.destination(for: them, dmID: dmID, origin: .transaction) == .tipConversation(dmID))
    }
}
