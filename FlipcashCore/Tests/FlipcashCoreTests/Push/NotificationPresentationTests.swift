//
//  NotificationPresentationTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing
import FlipcashAPI
@testable import FlipcashCore

/// The foreground presentation decision. Mute is read off the push payload rather than local state,
/// so these drive it entirely from encoded payloads — the same bytes both the app and the
/// notification service extension see.
@Suite("Notification presentation")
struct NotificationPresentationTests {

    private static let chatIDBytes = Data((0..<32).map { UInt8($0) })
    private static var chatID: ConversationID { ConversationID(data: chatIDBytes) }

    private static func userInfo(muted: Bool, chatMetadata: Bool = true) throws -> [AnyHashable: Any] {
        let payload = Flipcash_Push_V1_Payload.with {
            $0.category = .chat
            $0.navigation = .with { $0.chatID = .with { $0.value = chatIDBytes } }
            if chatMetadata {
                $0.chatMetadata = .with { $0.muted = muted }
            }
        }
        return [NotificationPayload.userInfoKey: try payload.serializedData().base64EncodedString()]
    }

    @Test("A muted chat's push presents nothing")
    func mutedPresentsNothing() throws {
        let decision = NotificationPayload.presentationDecision(try Self.userInfo(muted: true)) { _ in false }

        #expect(decision == .suppressedMuted)
        #expect(decision.options.isEmpty)
    }

    @Test("An unmuted chat's push presents normally")
    func unmutedPresentsNormally() throws {
        let decision = NotificationPayload.presentationDecision(try Self.userInfo(muted: false)) { _ in false }

        #expect(decision == .present)
        #expect(decision.options == [.badge, .list, .sound, .banner])
    }

    @Test("A push for the chat already on screen presents nothing")
    func openConversationPresentsNothing() throws {
        let decision = NotificationPayload.presentationDecision(try Self.userInfo(muted: false)) {
            $0 == Self.chatID
        }

        #expect(decision == .suppressedOpenConversation)
        #expect(decision.options.isEmpty)
    }

    /// A server that predates the flag sends no chat metadata at all; that must read as unmuted
    /// rather than swallowing every notification.
    @Test("A push without chat metadata presents normally")
    func missingChatMetadataPresentsNormally() throws {
        let userInfo = try Self.userInfo(muted: false, chatMetadata: false)

        #expect(NotificationPayload.presentationDecision(userInfo) { _ in false } == .present)
    }

    @Test("A push carrying no payload at all presents normally")
    func noPayloadPresentsNormally() {
        #expect(NotificationPayload.presentationDecision([:]) { _ in false } == .present)
    }
}
