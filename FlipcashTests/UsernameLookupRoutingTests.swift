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

    private static func profile(displayName: String?, username: String? = nil) -> Profile {
        Profile(
            displayName: displayName,
            phone: Optional<Phone>.none,
            email: nil,
            username: username.flatMap { Username($0) }
        )
    }

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

    @Test("A tip DM counterpart is never matched to an address-book contact")
    func context_neverResolvesAContact() {
        // Tip DMs identify people by profile. A directory entry that happens to
        // carry the derived chat id must not retitle the screen or redirect the
        // send to a phone number.
        let (me, them) = (UUID(), UUID())
        let chatID = ConversationID.tipDm(between: me, and: them)
        let contact = ResolvedContact(
            contactId: "abc",
            displayName: "Fred From My Phone",
            phoneE164: "+15551234567",
            nationalPhone: "(555) 123-4567",
            imageData: nil,
            dmChatID: chatID.data
        )
        let context = ConversationContext.tipDM(counterpart: them)
        #expect(context.resolvedContact(in: [contact]) == nil)
        // The same directory does resolve for a chat reached by its id.
        #expect(ConversationContext.existing(chatID).resolvedContact(in: [contact]) != nil)
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

    // MARK: - Counterpart -

    @Test("The fetched profile supplies the name and handle the chat shows")
    func counterpart_carriesNameAndHandle() {
        let userID = UUID()
        let member = ConversationScreen.counterpart(
            userID: userID,
            profile: Self.profile(displayName: "Fred Wilson", username: "fred_wilson")
        )
        #expect(member.userID == userID)
        #expect(member.displayName == "Fred Wilson")
        #expect(member.username == Username("fred_wilson"))
    }

    @Test("A name-less account is titled by its handle")
    func counterpart_fallsBackToTheHandleForANamelessAccount() {
        // Claiming a handle doesn't require a display name, so this is a real
        // account, not a malformed response — the chat needs a title regardless.
        let member = ConversationScreen.counterpart(
            userID: UUID(),
            profile: Self.profile(displayName: nil, username: "fred_wilson")
        )
        #expect(member.displayName == "@fred_wilson")
    }

    @Test("An account with neither a name nor a handle gets the fallback title")
    func counterpart_fallsBackForAnAccountWithNoNameOrHandle() {
        let member = ConversationScreen.counterpart(
            userID: UUID(),
            profile: Self.profile(displayName: nil)
        )
        #expect(member.displayName == ConversationController.fallbackCounterpartName)
    }

    @Test("A counterpart with no handle renders the name-only card")
    func counterpart_withoutAHandleShowsNoHandleLine() {
        let member = ConversationScreen.counterpart(
            userID: UUID(),
            profile: Self.profile(displayName: "Fred Wilson")
        )
        #expect(ConversationScreen.tipDMCounterpart(member) == ChatProfileCard.Counterpart.none)
    }
}
