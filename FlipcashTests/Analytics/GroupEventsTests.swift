//
//  GroupEventsTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

/// What the group chat and mute events send, written as literals.
@MainActor
@Suite("Group chat and mute events", .serialized)
struct GroupEventsTests {

    init() {
        Analytics.tokenSymbolResolver = nil
    }

    private static let jeffy = "54ggcQ23uen5b9QXMAns99MQNTKn7iyzq4wvCW6e8r25"

    private static let jeffyGate = ConversationRules(listener: [
        .minimumBalance(MinimumBalanceRequirement(amount: .usd(10), mints: [.jeffy])),
    ])

    // MARK: - Group -

    @Test("Group: New Opened has no properties")
    func newOpened() throws {
        let sent = Analytics.recordingSends { Analytics.groupNewOpened() }
        try expectEvent(sent, "Group: New Opened", [:])
    }

    @Test("Group: Created carries the gate mint and picture on success")
    func createdSuccess() throws {
        let sent = Analytics.recordingSends {
            Analytics.groupCreated(error: nil, rules: Self.jeffyGate, hasPicture: true)
        }
        try expectEvent(sent, "Group: Created", [
            "State": .text("Success"),
            "Gate Mint": .text(Self.jeffy),
            "Has Picture": .flag(true),
        ])
    }

    @Test("A failed Group: Created carries the proto result name")
    func createdFailure() throws {
        let sent = Analytics.recordingSends {
            Analytics.groupCreated(error: ErrorStartChat.rulesNotSatisfied, rules: nil, hasPicture: false)
        }
        try expectEvent(sent, "Group: Created", [
            "State": .text("Failure"),
            "Error": .text("RulesNotSatisfied"),
            "Has Picture": .flag(false),
        ])
    }

    @Test("Group: Edited carries the field changed", arguments: [
        (GroupField.name, "Name"),
        (.picture, "Picture"),
    ])
    func edited(_ field: GroupField, _ expected: String) throws {
        let sent = Analytics.recordingSends { Analytics.groupEdited(field: field, error: ErrorEditChat.notFound) }
        try expectEvent(sent, "Group: Edited", [
            "Field": .text(expected),
            "State": .text("Failure"),
            "Error": .text("NotFound"),
        ])
    }

    @Test("Group: Invite Sheet Opened carries its source and member count", arguments: [
        (GroupInviteSheetSource.chat, "Chat"),
        (.profile, "Profile"),
    ])
    func inviteSheetOpened(_ source: GroupInviteSheetSource, _ expected: String) throws {
        let sent = Analytics.recordingSends { Analytics.groupInviteSheetOpened(source: source, memberCount: 1) }
        try expectEvent(sent, "Group: Invite Sheet Opened", [
            "Source": .text(expected),
            "Member Count": .number(1),
        ])
    }

    @Test("Group: Invite Shared carries its method", arguments: [
        (GroupInviteMethod.share, "Share"),
        (.theCopy, "Copy"),
    ])
    func inviteShared(_ method: GroupInviteMethod, _ expected: String) throws {
        let sent = Analytics.recordingSends { Analytics.groupInviteShared(method: method) }
        try expectEvent(sent, "Group: Invite Shared", ["Method": .text(expected)])
    }

    @Test("Group: Invite Followed carries its source", arguments: [
        (GroupInviteSource.link, "Link"),
        (.qr, "QR"),
        (.chatCard, "Chat Card"),
    ])
    func inviteFollowed(_ source: GroupInviteSource, _ expected: String) throws {
        let sent = Analytics.recordingSends { Analytics.groupInviteFollowed(source: source) }
        try expectEvent(sent, "Group: Invite Followed", ["Source": .text(expected)])
    }

    @Test("Group: Gate Shown carries access, gate mint and member count", arguments: [
        (GroupAccess.eligible, "Eligible"),
        (.blocked, "Blocked"),
    ])
    func gateShown(_ access: GroupAccess, _ expected: String) throws {
        let sent = Analytics.recordingSends {
            Analytics.groupGateShown(access: access, gateMint: .jeffy, memberCount: 12)
        }
        try expectEvent(sent, "Group: Gate Shown", [
            "Access": .text(expected),
            "Gate Mint": .text(Self.jeffy),
            "Member Count": .number(12),
        ])
    }

    @Test("Group: Gate Funding Tapped carries its method", arguments: [
        (GroupGateFunding.buyToken, "Buy Token"),
        (.addCash, "Add Cash"),
    ])
    func gateFundingTapped(_ method: GroupGateFunding, _ expected: String) throws {
        let sent = Analytics.recordingSends { Analytics.groupGateFundingTapped(method: method, gateMint: nil) }
        try expectEvent(sent, "Group: Gate Funding Tapped", ["Method": .text(expected)])
    }

    @Test("Group: Joined carries member count and gated")
    func joined() throws {
        let sent = Analytics.recordingSends {
            Analytics.groupJoined(error: ErrorJoinChat.rulesNotSatisfied, memberCount: 3, gated: true)
        }
        try expectEvent(sent, "Group: Joined", [
            "State": .text("Failure"),
            "Error": .text("RulesNotSatisfied"),
            "Member Count": .number(3),
            "Gated": .flag(true),
        ])
    }

    @Test("Group: Left carries member count")
    func left() throws {
        let sent = Analytics.recordingSends { Analytics.groupLeft(error: nil, memberCount: 5) }
        try expectEvent(sent, "Group: Left", [
            "State": .text("Success"),
            "Member Count": .number(5),
        ])
    }

    @Test("Group: Info Opened carries member count and membership")
    func infoOpened() throws {
        let sent = Analytics.recordingSends { Analytics.groupInfoOpened(memberCount: 7, isMember: false) }
        try expectEvent(sent, "Group: Info Opened", [
            "Member Count": .number(7),
            "Is Member": .flag(false),
        ])
    }

    // MARK: - Mute -

    @Test("Chat Muted carries its duration", arguments: [
        (MuteDuration.oneHour, "1 Hour"),
        (.eightHours, "8 Hours"),
        (.oneWeek, "1 Week"),
        (.always, "Always"),
    ])
    func muted(_ duration: MuteDuration, _ expected: String) throws {
        let sent = Analytics.recordingSends { Analytics.chatMuted(chatType: .group, duration: duration, error: nil) }
        try expectEvent(sent, "Chat Muted", [
            "Chat Type": .text("Group"),
            "Duration": .text(expected),
            "State": .text("Success"),
        ])
    }

    @Test("A failed Chat Unmuted carries the proto result name")
    func unmutedFailure() throws {
        let sent = Analytics.recordingSends { Analytics.chatUnmuted(chatType: .tipDm, error: ErrorUnmuteChat.denied) }
        try expectEvent(sent, "Chat Unmuted", [
            "Chat Type": .text("Tip"),
            "State": .text("Failure"),
            "Error": .text("Denied"),
        ])
    }

    // MARK: - Error and gate mint -

    @Test("A chat error reports its proto result name", arguments: [
        (ErrorStartChat.denied as Error, "Denied"),
        (ErrorStartChat.pictureBlobNotAccepted, "PictureBlobNotAccepted"),
        (ErrorStartChat.invalidRules, "InvalidRules"),
        (ErrorEditChat.pictureBlobNotAccepted, "PictureBlobNotAccepted"),
        (ErrorJoinChat.notFound, "NotFound"),
        (ErrorLeaveChat.denied, "Denied"),
        (ErrorMuteChat.notFound, "NotFound"),
    ])
    func chatResult(_ error: Error, _ expected: String) {
        #expect(Analytics.chatResult(error) == expected)
    }

    @Test("A failure the server didn't answer with a result reports Network", arguments: [
        ErrorJoinChat.transportFailure as Error,
        ErrorLeaveChat.cancelled,
        ErrorStartChat.rejected,
        ErrorEditChat.unknown,
        URLError(.notConnectedToInternet),
    ])
    func chatResultNetwork(_ error: Error) {
        #expect(Analytics.chatResult(error) == "Network")
    }

    @Test("The gate mint is the one mint the listener rule names")
    func gateMint() {
        let rules: ConversationRules? = Self.jeffyGate
        #expect(rules.gateMint == .jeffy)
    }

    @Test("An any-currency, staff-only or ungated group has no gate mint")
    func noGateMint() {
        let anyCurrency: ConversationRules? = ConversationRules(listener: [
            .minimumBalance(MinimumBalanceRequirement(amount: .usd(10))),
        ])
        let staff: ConversationRules? = ConversationRules(listener: [.staff])
        #expect(anyCurrency.gateMint == nil)
        #expect(staff.gateMint == nil)
        #expect((nil as ConversationRules?).gateMint == nil)
    }

    // MARK: - Helpers -

    /// A property value as Mixpanel receives it.
    enum Value {
        case text(String)
        case number(Double)
        case flag(Bool)
    }

    /// Checks the single event sent: its name, its exact key set, and every value.
    private func expectEvent(
        _ sent: [SentEvent],
        _ name: String,
        _ properties: [String: Value],
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let event = try sent.single
        #expect(event.name == name, sourceLocation: sourceLocation)
        #expect(event.properties.keys.sorted() == properties.keys.sorted(), sourceLocation: sourceLocation)
        for (key, value) in properties {
            switch value {
            case .text(let text):
                #expect(event.properties[key] as? String == text, "\(key)", sourceLocation: sourceLocation)
            case .number(let number):
                #expect(event.properties[key] as? Double == number, "\(key)", sourceLocation: sourceLocation)
            case .flag(let flag):
                #expect(event.properties[key] as? Bool == flag, "\(key)", sourceLocation: sourceLocation)
            }
        }
    }
}

// Kotlin/Native enum entries are immutable singletons, so they are safe to pass as test arguments.
extension GroupField: @retroactive @unchecked Sendable {}
extension GroupInviteSheetSource: @retroactive @unchecked Sendable {}
extension GroupInviteMethod: @retroactive @unchecked Sendable {}
extension GroupInviteSource: @retroactive @unchecked Sendable {}
extension GroupAccess: @retroactive @unchecked Sendable {}
extension GroupGateFunding: @retroactive @unchecked Sendable {}
extension MuteDuration: @retroactive @unchecked Sendable {}
