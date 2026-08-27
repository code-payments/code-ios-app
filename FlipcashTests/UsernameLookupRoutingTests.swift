//
//  UsernameLookupRoutingTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

/// The username lookup opens the counterpart's chat (node 9443:8928), which
/// does not exist server-side until the first tip. These cover what the screen
/// has to resolve from the fetched profile alone in the meantime.
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

    @Test("The chat destination belongs to the tips stack")
    func destination_ownedByTipsStack() {
        #expect(AppRouter.Destination.tipConversationForUser(UUID()).owningStack == .tips)
    }

    @Test("The chat destination logs the counterpart as its payload")
    func destination_payloadIsCounterpart() {
        let userID = UUID()
        let destination = AppRouter.Destination.tipConversationForUser(userID)
        #expect(destination.description == "tipConversationForUser")
        #expect(destination.payload == userID.uuidString)
    }

    @Test("Two lookups of the same person are the same destination")
    func destination_isStablePerCounterpart() {
        let userID = UUID()
        #expect(
            AppRouter.Destination.tipConversationForUser(userID)
                == AppRouter.Destination.tipConversationForUser(userID)
        )
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

    @Test("A name-less account still titles the chat")
    func counterpart_fallsBackForANamelessAccount() {
        // Claiming a handle doesn't require a display name, so this is a real
        // account, not a malformed response — the chat needs a title regardless.
        let member = ConversationScreen.counterpart(
            userID: UUID(),
            profile: Self.profile(displayName: nil, username: "fred_wilson")
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
