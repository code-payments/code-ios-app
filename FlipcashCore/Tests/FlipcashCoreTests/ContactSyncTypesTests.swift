//
//  ContactSyncTypesTests.swift
//  FlipcashCoreTests
//

import Foundation
import Testing
@testable import FlipcashCore
import FlipcashAPI

@Suite("Contact sync types")
struct ContactSyncTypesTests {

    // MARK: - FlipcashContactsBatch.Result mapping -

    @Test(
        "proto Result maps to the matching Swift case",
        arguments: [
            (Flipcash_Contact_V1_GetFlipcashContactsResponse.Result.ok, FlipcashContactsBatch.Result.ok),
            (.denied, .denied),
            (.notFound, .notFound),
            (.checksumDrift, .checksumDrift),
        ]
    )
    func batchResult_knownProtoCase(
        proto: Flipcash_Contact_V1_GetFlipcashContactsResponse.Result,
        expected: FlipcashContactsBatch.Result
    ) {
        #expect(FlipcashContactsBatch.Result(proto) == expected)
    }

    @Test("UNRECOGNIZED proto case maps to .unknown")
    func batchResult_unrecognized() {
        #expect(FlipcashContactsBatch.Result(.UNRECOGNIZED(99)) == .unknown)
    }

    // MARK: - MatchedContact proto mapping -

    @Test("MatchedContact maps phone, dm chat id, and join date from the proto")
    func matchedContact_mapsAllFields() {
        let chatID = Data(repeating: 0xab, count: 32)
        let joined = Date(timeIntervalSince1970: 1_700_000_000)
        let proto = Flipcash_Contact_V1_FlipcashContact.with {
            $0.phone = .with { $0.value = "+15551234567" }
            $0.dmChatID = .with { $0.value = chatID }
            $0.joinTs = .init(date: joined)
        }

        let contact = MatchedContact(proto)

        #expect(contact.e164 == "+15551234567")
        #expect(contact.dmChatID == chatID)
        #expect(contact.joinDate == joined)
    }

    @Test("MatchedContact decodes an empty dm chat id and unset join ts to nil")
    func matchedContact_optionalFieldsNil() {
        let proto = Flipcash_Contact_V1_FlipcashContact.with {
            $0.phone = .with { $0.value = "+15551234567" }
        }

        let contact = MatchedContact(proto)

        #expect(contact.dmChatID == nil)
        #expect(contact.joinDate == nil)
    }

    // MARK: - ErrorContactSync reportability -

    @Test(
        "transient/recoverable cases non-reportable; only .checksumMismatch / .unknown bugsnag",
        arguments: [
            (ErrorContactSync.ok,              false),
            (.denied,            false),
            (.tooManyContacts,   false),
            (.checksumDrift,     false),
            (.transportFailure,  false),
            (.notFound,          false),
            (.checksumMismatch,  true),
            (.unknown,           true),
        ]
    )
    func contactSync_isReportable(error: ErrorContactSync, expected: Bool) {
        #expect(error.isReportable == expected)
    }

    // MARK: - ErrorResolve reportability -

    @Test(
        "Resolve transient/denied/not-found cases are non-reportable; only .unknown bugsnags",
        arguments: [
            (ErrorResolve.ok,           false),
            (.denied,       false),
            (.notFound,     false),
            (.transportFailure, false),
            (.unknown,      true),
        ]
    )
    func resolve_isReportable(error: ErrorResolve, expected: Bool) {
        #expect(error.isReportable == expected)
    }

    // MARK: - CheckSyncResult equality -

    @Test("CheckSyncResult.ok is equal to itself and unequal to .outOfSync")
    func checkSyncResult_okEquality() {
        #expect(CheckSyncResult.ok == .ok)
        #expect(CheckSyncResult.ok != .outOfSync(serverChecksum: Data([0x01])))
    }

    @Test("CheckSyncResult.outOfSync compares by associated checksum")
    func checkSyncResult_outOfSyncEquality() {
        let a = Data(repeating: 0xab, count: 32)
        let b = Data(repeating: 0xcd, count: 32)

        #expect(CheckSyncResult.outOfSync(serverChecksum: a) == .outOfSync(serverChecksum: a))
        #expect(CheckSyncResult.outOfSync(serverChecksum: a) != .outOfSync(serverChecksum: b))
    }
}
