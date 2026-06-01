//
//  TransportClassificationTests.swift
//  FlipcashCoreTests
//

import Foundation
import Testing
import GRPC
@testable import FlipcashCore

@Suite("Transport classification — classifiable errors route transient gRPC failures to a non-reportable case")
struct TransportClassificationTests {

    /// Generic contract check, reused by one `@Test` per conformer below. Using
    /// a generic over the concrete type (not a list of erased closures) keeps
    /// arguments `Sendable`-free and the call type-safe.
    private func assertClassifies<E: TransportClassifiableError>(_ type: E.Type) {
        #expect(E.from(transportError: GRPCStatus(code: .deadlineExceeded, message: nil)).isReportable == false)
        #expect(E.from(transportError: GRPCStatus(code: .unavailable, message: nil)).isReportable == false)
        #expect(E.from(transportError: GRPCStatus(code: .internalError, message: nil)).isReportable == true)
    }

    // MARK: - Registry (one line per TransportClassifiableError conformer) -

    @Test func errorFetchBalance() { assertClassifies(ErrorFetchBalance.self) }
}
