//
//  BlobRejectionReasonTests.swift
//  FlipcashCoreTests
//

import Testing
import FlipcashAPI
@testable import FlipcashCore

@Suite("Blob rejection reason")
struct BlobRejectionReasonTests {

    @Test("Keeps an internal rejection distinct from an unset reason")
    func internal_isNotUnknown() {
        #expect(BlobRejectionReason(.internal) == .internal)
        #expect(BlobRejectionReason(.unknown) == .unknown)
    }

    @Test("Keeps the raw value of a reason this build doesn't know")
    func unrecognized_keepsRawValue() {
        let reason = BlobRejectionReason(.UNRECOGNIZED(42))
        #expect(reason == .unrecognized(42))
        #expect("\(reason)" == "unrecognized(42)")
    }

    @Test("A rejected status carries the mapped reason")
    func rejectedState_carriesReason() {
        let rejection = Flipcash_Blob_V1_RejectionMetadata.with { $0.reason = .internal }
        #expect(BlobState(status: .rejected, rejection: rejection) == .rejected(.internal))
    }
}
