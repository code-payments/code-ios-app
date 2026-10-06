//
//  UsernameLookupRoutingTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

/// The username lookup opens the counterpart's profile until a DM with them
/// exists, and the DM after that.
@MainActor
@Suite("Username lookup routing")
struct UsernameLookupRoutingTests {

    // MARK: - Destination -

    @Test("Without a DM, the lookup lands on the profile, owned by the tips stack, keyed by the user")
    func destination_withoutDMIsTheProfile() {
        let userID = UUID()
        let destination = DMRoute.destination(for: userID, dmID: nil, origin: .usernameLookup)
        #expect(destination == .userProfile(userID, origin: .usernameLookup))
        #expect(destination.owningStack == .tips)
        #expect(destination.payload == userID.uuidString)
    }

    @Test("With a DM, the lookup lands on the chat")
    func destination_withDMIsTheChat() {
        let (me, them) = (UUID(), UUID())
        let dmID = ConversationID.tipDm(between: me, and: them)
        #expect(DMRoute.destination(for: them, dmID: dmID, origin: .usernameLookup) == .tipConversation(dmID))
    }

    // MARK: - Context -

    @Test("The chat id is the one the server derives for the pair")
    func context_derivesTheTipDmChatID() {
        // The screen derives it locally so the chat can be opened before it
        // exists; the first tip must land in that same chat.
        let (me, them) = (UUID(), UUID())
        #expect(ConversationID.tipDm(between: me, and: them) == .tipDm(between: them, and: me))
    }

    // MARK: - Back stack -

    @Test("The chat list is not a fixed number of screens below the lookup")
    func backStack_routeInHasNoFixedDepth() {
        // The lookup was pushed straight off the chat list until the New Chat
        // picker went in between (#790). A screen that assumed the depth it had
        // then is a screen that stops unwinding the moment the route changes.
        let router = AppRouter()
        router.activeTabStack = .tips

        router.push(.newChat)
        router.push(.usernameLookup)

        #expect(router[.tips].count == 2)
    }

    @Test(
        "Back from a profile or chat opened by handle lands on the chat list",
        arguments: [false, true]
    )
    func backStack_rewriteLeavesOnlyTheDestination(hasDM: Bool) {
        let router = AppRouter()
        router.activeTabStack = .tips
        router.push(.newChat)
        router.push(.usernameLookup)

        let them = UUID()
        let dmID = hasDM ? ConversationID.tipDm(between: UUID(), and: them) : nil
        let destination = DMRoute.destination(for: them, dmID: dmID, origin: .usernameLookup)
        let depthWithDestination = router[.tips].count + 1
        router.push(destination)
        #expect(router[.tips].count == depthWithDestination)

        // What the screen does once the push has started: neither the picker
        // nor the lookup is somewhere Back belongs, and the list is the root.
        router.setPath([destination], on: .tips)
        #expect(router[.tips].count == 1)
    }
}
