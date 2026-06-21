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
        #expect(substitution.contact.value == "+15551234567")
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
}
