//
//  ModerationAttestationTests.swift
//  FlipcashTests
//

import Testing
import Foundation
import FlipcashAPI
@testable import FlipcashCore

@Suite("ModerationAttestation")
struct ModerationAttestationTests {

    @Test("init(fromModerationProto:) preserves the serialized bytes")
    func initFromModerationProto_preservesBytes() throws {
        var moderationProto = Flipcash_Moderation_V1_ModerationAttestation()
        moderationProto.contentHash = Data([0x01, 0x02, 0x03])

        let attestation = try ModerationAttestation(moderationProto)

        #expect(attestation.rawValue == (try moderationProto.serializedData()))
    }

    @Test("currencyProto wraps rawValue")
    func currencyProto_wrapsRawValue() throws {
        let attestation = ModerationAttestation(rawValue: Data([0x0A, 0x0B]))

        let currencyProto = attestation.currencyProto

        #expect(currencyProto.rawValue == Data([0x0A, 0x0B]))
    }

    @Test("round-trip moderation proto -> attestation -> currency proto preserves bytes")
    func roundTrip_preservesBytes() throws {
        var moderationProto = Flipcash_Moderation_V1_ModerationAttestation()
        moderationProto.contentHash = Data([0xAA])
        moderationProto.timestamp.seconds = 42

        let attestation = try ModerationAttestation(moderationProto)
        let currencyProto = attestation.currencyProto

        #expect(currencyProto.rawValue == (try moderationProto.serializedData()))
    }
}
