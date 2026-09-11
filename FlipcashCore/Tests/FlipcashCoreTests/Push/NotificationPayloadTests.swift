import Foundation
import Testing
import FlipcashAPI
@testable import FlipcashCore

@Suite("NotificationPayload")
struct NotificationPayloadTests {

    /// Base64 of a `Flipcash_Push_V1_Payload` carrying a single CONTACT_JOIN
    /// title substitution for phone `+15551234567`. Hand-encoded and verified
    /// against `flipcash2-server/push/pushes.go:SendContactJoinedFlipcashPush`.
    private static let knownPayloadBase64 =
        "Eh4KDCsxNTU1MTIzNDU2NxIOCgwrMTU1NTEyMzQ1NjcgBSoMQ09OVEFDVF9KT0lO"

    @Test("Decodes a known CONTACT_JOIN payload")
    func decodesKnownPayload() throws {
        let payload = try #require(
            NotificationPayload.decode([NotificationPayload.userInfoKey: Self.knownPayloadBase64])
        )

        #expect(payload.category == .contactJoin)
        #expect(payload.groupKey == "CONTACT_JOIN")
        #expect(payload.bodySubstitutions.isEmpty)

        let substitution = try #require(payload.titleSubstitutions.first)
        #expect(payload.titleSubstitutions.count == 1)
        #expect(substitution.fallback == "+15551234567")
        #expect(substitution.phoneNumberToContactName.value == "+15551234567")
    }

    @Test("Decodes a payload nested under the aps dictionary")
    func decodesPayloadNestedUnderAps() throws {
        let payload = try #require(
            NotificationPayload.decode(["aps": [NotificationPayload.userInfoKey: Self.knownPayloadBase64]])
        )

        #expect(payload.category == .contactJoin)
    }

    @Test("isContactJoin is true for a CONTACT_JOIN payload nested under aps")
    func isContactJoinNestedUnderAps() {
        #expect(NotificationPayload.isContactJoin(["aps": [NotificationPayload.userInfoKey: Self.knownPayloadBase64]]))
    }

    @Test("isContactJoin is false when no payload is present")
    func isContactJoinFalseWhenAbsent() {
        #expect(NotificationPayload.isContactJoin([:]) == false)
    }

    @Test("Returns nil when the userInfo dictionary is missing the key")
    func returnsNilWhenKeyMissing() {
        #expect(NotificationPayload.decode([:]) == nil)
        #expect(NotificationPayload.decode(["other_key": "value"]) == nil)
    }

    @Test("Returns nil when the value is not a string")
    func returnsNilWhenValueNotString() {
        #expect(NotificationPayload.decode([NotificationPayload.userInfoKey: 42]) == nil)
        #expect(NotificationPayload.decode([NotificationPayload.userInfoKey: Data([0x01])]) == nil)
        #expect(NotificationPayload.decode([NotificationPayload.userInfoKey: true]) == nil)
        #expect(NotificationPayload.decode([NotificationPayload.userInfoKey: [String]()]) == nil)
    }

    @Test("Returns nil for malformed base64")
    func returnsNilForMalformedBase64() {
        #expect(NotificationPayload.decode([NotificationPayload.userInfoKey: "not base64!@#$"]) == nil)
    }

    @Test("Returns nil for valid base64 that isn't a Payload")
    func returnsNilForGarbageBytes() {
        // Random bytes that won't parse as Flipcash_Push_V1_Payload.
        let garbage = Data([0xff, 0xff, 0xff, 0xff, 0xff]).base64EncodedString()
        #expect(NotificationPayload.decode([NotificationPayload.userInfoKey: garbage]) == nil)
    }

    // MARK: - chatID

    /// The 32-byte ChatId used across the chat-targeting tests.
    private static let chatIDBytes = Data((0..<32).map { UInt8($0) })

    private static func base64(for payload: Flipcash_Push_V1_Payload) throws -> String {
        try payload.serializedData().base64EncodedString()
    }

    @Test("chatID returns the target conversation for a CHAT push")
    func chatIDForChatPush() throws {
        let payload = Flipcash_Push_V1_Payload.with {
            $0.category = .chat
            $0.navigation = .with { $0.chatID = .with { $0.value = Self.chatIDBytes } }
        }
        let userInfo = [NotificationPayload.userInfoKey: try Self.base64(for: payload)]
        #expect(NotificationPayload.chatID(userInfo) == ConversationID(data: Self.chatIDBytes))
    }

    @Test("chatID resolves a CHAT push nested under aps")
    func chatIDNestedUnderAps() throws {
        let payload = Flipcash_Push_V1_Payload.with {
            $0.category = .chat
            $0.navigation = .with { $0.chatID = .with { $0.value = Self.chatIDBytes } }
        }
        let userInfo = ["aps": [NotificationPayload.userInfoKey: try Self.base64(for: payload)]]
        #expect(NotificationPayload.chatID(userInfo) == ConversationID(data: Self.chatIDBytes))
    }

    @Test("chatID is nil for a non-chat payload")
    func chatIDNilForNonChat() {
        #expect(NotificationPayload.chatID([NotificationPayload.userInfoKey: Self.knownPayloadBase64]) == nil)
    }

    @Test("chatID is nil for a CHAT push without chat navigation")
    func chatIDNilWhenNavigationMissing() throws {
        let payload = Flipcash_Push_V1_Payload.with { $0.category = .chat }
        let userInfo = [NotificationPayload.userInfoKey: try Self.base64(for: payload)]
        #expect(NotificationPayload.chatID(userInfo) == nil)
    }

    @Test("chatID is nil for a non-chat category even when chat navigation is present")
    func chatIDNilForNonChatCategoryWithChatNavigation() throws {
        let payload = Flipcash_Push_V1_Payload.with {
            $0.category = .default
            $0.navigation = .with { $0.chatID = .with { $0.value = Self.chatIDBytes } }
        }
        let userInfo = [NotificationPayload.userInfoKey: try Self.base64(for: payload)]
        #expect(NotificationPayload.chatID(userInfo) == nil)
    }

    @Test("chatID is nil for a CHAT push whose navigation targets currency info")
    func chatIDNilForCurrencyInfoNavigation() throws {
        let payload = Flipcash_Push_V1_Payload.with {
            $0.category = .chat
            $0.navigation = .with { $0.currencyInfo = .with { $0.value = Self.chatIDBytes } }
        }
        let userInfo = [NotificationPayload.userInfoKey: try Self.base64(for: payload)]
        #expect(NotificationPayload.chatID(userInfo) == nil)
    }

    @Test("chatID is nil when no payload is present")
    func chatIDNilWhenAbsent() {
        #expect(NotificationPayload.chatID([:]) == nil)
    }

    @Test("chatType returns the DM kind from chat metadata")
    func chatTypeFromMetadata() throws {
        let payload = Flipcash_Push_V1_Payload.with {
            $0.category = .chat
            $0.chatMetadata = .with { $0.type = .tipDm }
        }
        let userInfo = [NotificationPayload.userInfoKey: try Self.base64(for: payload)]
        #expect(NotificationPayload.chatType(userInfo) == .tipDm)
    }

    @Test("chatType is nil for a CHAT push without chat metadata")
    func chatTypeNilWhenMetadataMissing() throws {
        let payload = Flipcash_Push_V1_Payload.with { $0.category = .chat }
        let userInfo = [NotificationPayload.userInfoKey: try Self.base64(for: payload)]
        #expect(NotificationPayload.chatType(userInfo) == nil)
    }

    @Test("chatType is nil for a non-chat category even when chat metadata is present")
    func chatTypeNilForNonChatCategory() throws {
        let payload = Flipcash_Push_V1_Payload.with {
            $0.category = .default
            $0.chatMetadata = .with { $0.type = .tipDm }
        }
        let userInfo = [NotificationPayload.userInfoKey: try Self.base64(for: payload)]
        #expect(NotificationPayload.chatType(userInfo) == nil)
    }

    // MARK: - chatMessage -

    private static func chatPush(
        category: Flipcash_Push_V1_Payload.Category = .chat,
        message: Flipcash_Messaging_V1_Message?
    ) throws -> [String: String] {
        let payload = Flipcash_Push_V1_Payload.with {
            $0.category = category
            $0.chatMetadata = .with {
                $0.type = .contactDm
                if let message { $0.message = message }
            }
        }
        return [NotificationPayload.userInfoKey: try Self.base64(for: payload)]
    }

    @Test("chatMessage maps the message embedded in the push")
    func chatMessageFromMetadata() throws {
        let senderUUID = UUID()
        let embedded = Flipcash_Messaging_V1_Message.with {
            $0.messageID = .with { $0.value = 42 }
            $0.senderID = .with { $0.value = senderUUID.data }
            $0.content = [.with { $0.text = .with { $0.text = "see you there" } }]
            $0.ts = .init(date: Date(timeIntervalSince1970: 1_700_000_000))
            $0.eventSequence = 9
            $0.unreadSeq = 4
        }

        let message = try #require(NotificationPayload.chatMessage(try Self.chatPush(message: embedded)))
        #expect(message.id == MessageID(value: 42))
        #expect(message.senderID == senderUUID)
        #expect(message.content == .text("see you there"))
        #expect(message.date == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(message.unreadSeq == 4)
    }

    /// The whole reason the embedded message can merge with a fetched one instead of duplicating it.
    @Test("chatMessage preserves the event sequence the transcript fetch would return")
    func chatMessageCarriesEventSequence() throws {
        let embedded = Flipcash_Messaging_V1_Message.with {
            $0.messageID = .with { $0.value = 42 }
            $0.content = [.with { $0.text = .with { $0.text = "hi" } }]
            $0.eventSequence = 9
        }

        let message = try #require(NotificationPayload.chatMessage(try Self.chatPush(message: embedded)))
        #expect(message.eventSequence == 9)
    }

    /// A server that predates the embedded message, which is every server until 0.5.0 ships.
    @Test("chatMessage is nil when the push carries no embedded message")
    func chatMessageNilWhenAbsent() throws {
        #expect(NotificationPayload.chatMessage(try Self.chatPush(message: nil)) == nil)
    }

    @Test("chatMessage is nil for a non-chat category even when a message is embedded")
    func chatMessageNilForNonChatCategory() throws {
        let embedded = Flipcash_Messaging_V1_Message.with {
            $0.messageID = .with { $0.value = 42 }
            $0.content = [.with { $0.text = .with { $0.text = "hi" } }]
        }
        #expect(NotificationPayload.chatMessage(try Self.chatPush(category: .default, message: embedded)) == nil)
    }

    /// `ConversationMessage.init?` rejects content this client can't draw. The accessor has to pass
    /// that nil through rather than substituting an empty message.
    @Test("chatMessage is nil for embedded content the client cannot represent")
    func chatMessageNilForUnrepresentableContent() throws {
        let embedded = Flipcash_Messaging_V1_Message.with {
            $0.messageID = .with { $0.value = 42 }
            $0.content = [.with { $0.system = .with { _ in } }]
        }
        #expect(NotificationPayload.chatMessage(try Self.chatPush(message: embedded)) == nil)
    }

    @Test("chatMessage is nil when no payload is present")
    func chatMessageNilWhenNoPayload() {
        #expect(NotificationPayload.chatMessage([:]) == nil)
    }
}
