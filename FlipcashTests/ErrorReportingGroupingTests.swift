//
//  ErrorReportingGroupingTests.swift
//  Flipcash
//
//  A catch-all capture groups on file and function. Without the error's type in the
//  hash, `receiveCashLink` merged eight error types into one Bugsnag group.
//

import Foundation
import Testing
@testable import Flipcash

@Suite("ErrorReporting.groupingHash")
struct ErrorReportingGroupingTests {

    private enum ErrorA: Error { case failed, grpcStatus(Int) }
    private enum ErrorB: Error { case failed }

    private func hash(_ error: Swift.Error, id: String? = nil, function: String = "receiveCashLink()") -> String {
        ErrorReporting.groupingHash(fileName: "Session.swift", function: function, id: id, error: error)
    }

    @Test("Different error types from one function get different ids")
    func differentTypesSplit() {
        #expect(hash(ErrorA.failed) != hash(ErrorB.failed))
    }

    @Test("The same error from one function gets the same id")
    func sameErrorGroups() {
        #expect(hash(ErrorA.failed) == hash(ErrorA.failed))
        #expect(hash(ErrorA.grpcStatus(13)) == hash(ErrorA.grpcStatus(13)))
    }

    @Test("Associated values split groups")
    func associatedValuesSplit() {
        #expect(hash(ErrorA.grpcStatus(13)) != hash(ErrorA.grpcStatus(14)))
    }

    @Test("Same error in different functions stays separate")
    func functionsStaySeparate() {
        #expect(hash(ErrorA.failed, function: "a()") != hash(ErrorA.failed, function: "b()"))
    }

    @Test("An explicit id replaces the error type")
    func explicitIdWins() {
        #expect(hash(ErrorA.failed, id: "x") == hash(ErrorB.failed, id: "x"))
        #expect(hash(ErrorA.failed, id: "x") != hash(ErrorA.failed, id: "y"))
    }
}
