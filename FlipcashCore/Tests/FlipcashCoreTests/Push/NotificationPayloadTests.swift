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
}
