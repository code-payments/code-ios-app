//
//  ChatAttributionNameTests.swift
//  FlipcashTests
//

import Testing
import FlipcashCore
@testable import Flipcash

/// What a group row calls its sender when the sender has no display name.
@Suite("Chat attribution name")
struct ChatAttributionNameTests {

    @Test("A display name is used as is")
    func attributionName_displayName_usesIt() {
        let member = ConversationMember(userID: UserID(), displayName: "Grace", username: Username("grace"))
        #expect(ConversationLoadCoordinator.attributionName(for: member) == "Grace")
    }

    @Test("A nameless sender with a handle is called by the handle")
    func attributionName_namelessWithHandle_usesHandle() throws {
        let username = try #require(Username("grace"))
        let member = ConversationMember(userID: UserID(), displayName: "", username: username)
        #expect(ConversationLoadCoordinator.attributionName(for: member) == username.handle)
    }

    @Test("A sender with neither is called Flipcash User")
    func attributionName_namelessWithoutHandle_usesFallback() {
        let member = ConversationMember(userID: UserID(), displayName: "")
        #expect(ConversationLoadCoordinator.attributionName(for: member) == ConversationController.fallbackCounterpartName)
    }

    @Test("A tip DM with no chat yet titles a nameless profile by its handle, not a blank")
    @MainActor func dmCounterpart_emptyName_usesHandle() throws {
        let username = try #require(Username("grace"))
        let profile = Profile(displayName: "", phone: Phone?.none, email: nil, username: username)
        #expect(ConversationScreen.counterpart(userID: UserID(), profile: profile).displayName == username.handle)
    }

    @Test("A tip DM with no chat yet titles a nameless profile without a handle as Flipcash User")
    @MainActor func dmCounterpart_emptyNameNoHandle_usesFallback() {
        let profile = Profile(displayName: "", phone: Phone?.none, email: nil)
        #expect(ConversationScreen.counterpart(userID: UserID(), profile: profile).displayName == ConversationController.fallbackCounterpartName)
    }
}
