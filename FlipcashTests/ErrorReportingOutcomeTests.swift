//
//  ErrorReportingOutcomeTests.swift
//  Flipcash
//
//  Covers the `userFacing` floor: a transient transport error (`.suppressed`) that
//  reaches a hard failure dialog is recorded at `.info` — a breadcrumb, never `.error`
//  (so it never pages Slack), and only ever for `.suppressed` (never user-caused).
//

import Foundation
import Testing
import GRPCCore
import FlipcashCore
@testable import Flipcash

@Suite("ErrorReporting.outcome — userFacing floor")
struct ErrorReportingOutcomeTests {

    @Test("Full level × userFacing matrix", arguments: [
        // level, userFacing, expected outcome
        (ErrorReportingLevel.suppressed, false, ErrorReporting.Outcome.drop),
        (.suppressed, true,  .info),   // the floor: transient dialog → breadcrumb
        (.info,       false, .info),
        (.info,       true,  .info),   // unchanged
        (.error,      false, .error),
        (.error,      true,  .error),  // real defect still pages, never downgraded
    ])
    func outcomeMatrix(level: ErrorReportingLevel, userFacing: Bool, expected: ErrorReporting.Outcome) {
        #expect(ErrorReporting.outcome(for: level, userFacing: userFacing) == expected)
    }

    @Test("userFacing never produces .error — cannot page Slack")
    func userFacingNeverPages() {
        for level in [ErrorReportingLevel.suppressed, .info] {
            #expect(ErrorReporting.outcome(for: level, userFacing: true) != .error)
        }
    }

    @Test("#545 shape: transient RPCError reaching a dialog becomes an info breadcrumb")
    func transientTransportFloorsToInfo() {
        // The cold-channel race throws gRPC .unavailable, which classifies .suppressed.
        let transient = RPCError(code: .unavailable, message: "channel not connected")
        #expect(transient.reportingLevel == .suppressed)

        // Without a dialog it is dropped (network weather); with a dialog it is recorded.
        #expect(ErrorReporting.outcome(for: transient.reportingLevel, userFacing: false) == .drop)
        #expect(ErrorReporting.outcome(for: transient.reportingLevel, userFacing: true) == .info)
    }
}
