//
//  UsernameLookupRoutingTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

/// The username lookup always opens the counterpart's profile, whether or not a DM exists.
@MainActor
@Suite("Username lookup routing")
struct UsernameLookupRoutingTests {

    // MARK: - Destination -

    @Test("The lookup lands on the profile, owned by the tips stack, keyed by the user")
    func destination_isTheProfile() {
        let userID = UUID()
        let destination = UsernameLookupScreen.destination(for: userID)
        #expect(destination == .userProfile(userID, origin: .usernameLookup))
        #expect(destination.owningStack == .tips)
        #expect(destination.payload == userID.uuidString)
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

    @Test("Back from a profile opened by handle lands on the chat list")
    func backStack_rewriteLeavesOnlyTheDestination() {
        let router = AppRouter()
        router.activeTabStack = .tips
        router.push(.newChat)
        router.push(.usernameLookup)

        let destination = UsernameLookupScreen.destination(for: UUID())
        let depthWithDestination = router[.tips].count + 1
        router.push(destination)
        #expect(router[.tips].count == depthWithDestination)

        // What the screen does once the push has started: neither the picker
        // nor the lookup is somewhere Back belongs, and the list is the root.
        router.setPath([destination], on: .tips)
        #expect(router[.tips].count == 1)
    }
}
