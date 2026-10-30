//
//  ProfileEventsTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashAPI
import FlipcashCore
@testable import Flipcash

/// What the Profile events send, written as literals.
@MainActor
@Suite("Profile events", .serialized)
struct ProfileEventsTests {

    init() {
        Analytics.tokenSymbolResolver = nil
    }

    private struct Boom: Error {}

    // MARK: - Wrappers -

    @Test("Profile: Settings Viewed has no properties")
    func settingsViewed() throws {
        let sent = Analytics.recordingSends { Analytics.profileSettingsViewed() }
        try expectEvent(sent, "Profile: Settings Viewed", [:])
    }

    @Test("Profile: Edit Profile Viewed has no properties")
    func editProfileViewed() throws {
        let sent = Analytics.recordingSends { Analytics.profileEditProfileViewed() }
        try expectEvent(sent, "Profile: Edit Profile Viewed", [:])
    }

    @Test("Profile: Card Shown has no properties")
    func cardShown() throws {
        let sent = Analytics.recordingSends { Analytics.profileCardShown() }
        try expectEvent(sent, "Profile: Card Shown", [:])
    }

    @Test("Profile: Bio Moderation Failed has no properties")
    func bioModerationFailed() throws {
        let sent = Analytics.recordingSends { Analytics.profileBioModerationFailed() }
        try expectEvent(sent, "Profile: Bio Moderation Failed", [:])
    }

    @Test("Profile: Field Saved carries the field")
    func fieldSaved() throws {
        let cases: [(SharedCoreKit.ProfileField, String)] = [
            (.name, "Name"), (.username, "Username"), (.photo, "Photo"),
            (.cover, "Cover"), (.bio, "Bio"), (.minimum, "Minimum"),
        ]
        for (field, value) in cases {
            let sent = Analytics.recordingSends { Analytics.profileFieldSaved(field) }
            try expectEvent(sent, "Profile: Field Saved", ["Field": value])
        }
    }

    @Test("Profile: Menu Action carries the action", arguments: [
        (ProfileMenuItem.mute, "Mute"),
        (.report, "Report"),
        (.block, "Block"),
        (.unblock, "Unblock"),
    ])
    func menuAction(item: ProfileMenuItem, value: String) throws {
        let sent = Analytics.recordingSends { Analytics.profileMenuAction(for: item) }
        try expectEvent(sent, "Profile: Menu Action", ["Action": value])
    }

    @Test("Group moderation entries send no Menu Action", arguments: [ProfileMenuItem.silence, .removeFromGroup])
    func moderationEntriesSendNothing(item: ProfileMenuItem) {
        #expect(item.analyticsAction == nil)
        let sent = Analytics.recordingSends { Analytics.profileMenuAction(for: item) }
        #expect(sent.isEmpty)
    }

    @Test("Profile: Pinned Button Tapped carries the action")
    func pinnedButtonTapped() throws {
        let fee = try #require(FiatAmount.usd(1))
        let dmID = ConversationID(data: Data(repeating: 1, count: 32))
        let cases: [(Flipcash.ProfilePinnedAction, String)] = [
            (.startChatting(fee), "Start Chatting"),
            (.startChattingUnpriced, "Start Chatting"),
            (.openChat(dmID), "Open Chat"),
            (.unblock, "Unblock"),
        ]
        for (action, value) in cases {
            let sent = Analytics.recordingSends { Analytics.profilePinnedButtonTapped(for: action) }
            try expectEvent(sent, "Profile: Pinned Button Tapped", ["Action": value])
        }
    }

    @Test("An empty pin sends no Pinned Button Tapped")
    func emptyPinSendsNothing() {
        #expect(Flipcash.ProfilePinnedAction.none.analyticsAction == nil)
        let sent = Analytics.recordingSends { Analytics.profilePinnedButtonTapped(for: .none) }
        #expect(sent.isEmpty)
    }

    // MARK: - EditBioModel -

    private func makeBioModel(saving: @escaping (String) async throws -> Void) -> EditBioModel {
        let model = EditBioModel(bio: "Hello", saving: saving, refresh: {})
        model.text = "Hello there"
        return model
    }

    @Test("A saved bio sends Field Saved for the bio")
    func bioSaved() async throws {
        let model = makeBioModel { _ in }
        let sent = await Analytics.recordingSendsAsync { await model.save() }
        try expectEvent(sent, "Profile: Field Saved", ["Field": "Bio"])
    }

    @Test("A moderated bio sends Bio Moderation Failed and no Field Saved")
    func bioModerated() async throws {
        let model = makeBioModel { _ in throw ErrorProfile.moderated(.init()) }
        let sent = await Analytics.recordingSendsAsync { await model.save() }
        try expectEvent(sent, "Profile: Bio Moderation Failed", [:])
    }

    @Test("An invalid or failed bio sends nothing", arguments: [true, false])
    func bioOtherFailures(invalid: Bool) async {
        let model = makeBioModel { _ in throw invalid ? ErrorProfile.invalidBio : Boom() }
        let sent = await Analytics.recordingSendsAsync { await model.save() }
        #expect(sent.isEmpty)
    }

    // MARK: - Helpers -

    private func expectEvent(
        _ sent: [SentEvent],
        _ name: String,
        _ properties: [String: String],
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let event = try sent.single
        #expect(event.name == name, sourceLocation: sourceLocation)
        #expect(event.properties.keys.sorted() == properties.keys.sorted(), sourceLocation: sourceLocation)
        for (key, value) in properties {
            #expect(event.properties[key] as? String == value, "\(key)", sourceLocation: sourceLocation)
        }
    }
}
