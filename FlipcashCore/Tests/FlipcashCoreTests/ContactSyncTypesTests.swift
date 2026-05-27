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

    // MARK: - ErrorContactSync reportability -

    @Test(
        "transient/recoverable cases non-reportable; only .checksumMismatch / .unknown bugsnag",
        arguments: [
            (ErrorContactSync.ok,              false),
            (.denied,            false),
            (.tooManyContacts,   false),
            (.checksumDrift,     false),
            (.networkError,      false),
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
        "Resolve transient/denied cases are non-reportable; only .unknown bugsnags",
        arguments: [
            (ErrorResolve.ok,           false),
            (.denied,       false),
            (.networkError, false),
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
