//
//  Regression_6a10ebf.swift
//  Flipcash
//
//  Symptom:  UsdcSweepOperation fires on every scenePhase → active. After a
//            long background the gRPC connection needs to reconnect; the unary
//            15s deadline expires first and AccountInfoService's failure
//            handling collapses the timeout into ErrorFetchBalance.unknown,
//            which is reportable. Result: a Bugsnag report per cold resume
//            that misrepresents a transport timeout as a server "unknown".
//
//  Fix:      Add ErrorFetchBalance.transportFailure (isReportable: false) and
//            a static `from(transportError:)` helper that classifies gRPC
//            timeout / unavailable into it. AccountInfoService's failure paths
//            route through the helper. ErrorReporting already honors
//            ServerError.isReportable, so the sweep catch suppresses these
//            reports automatically.
//

import Foundation
import Testing
import GRPCCore
import FlipcashCore

@Suite("Regression: 6a10ebf – USDC sweep no longer reports cold-resume RPC timeouts", .bug("6a10ebfc8c3285d1a545d656"))
struct Regression_6a10ebf {

    @Test("ErrorFetchBalance reportability is correct for every case", arguments: [
        (ErrorFetchBalance.ok,               false),
        (ErrorFetchBalance.notFound,         false),
        (ErrorFetchBalance.accountNotInList, false),
        (ErrorFetchBalance.unknown,          true),
        (ErrorFetchBalance.parseFailed,      true),
        (ErrorFetchBalance.transportFailure, false),
    ])
    func reportability(error: ErrorFetchBalance, expected: Bool) {
        #expect(error.isReportable == expected)
    }

    @Test("gRPC transport errors map to the right ErrorFetchBalance case", arguments: [
        (RPCError.Code.deadlineExceeded, ErrorFetchBalance.transportFailure),
        (RPCError.Code.unavailable,      ErrorFetchBalance.transportFailure),
        (RPCError.Code.cancelled,        ErrorFetchBalance.unknown),
        (RPCError.Code.invalidArgument,  ErrorFetchBalance.unknown),
        (RPCError.Code.permissionDenied, ErrorFetchBalance.unknown),
        (RPCError.Code.internalError,    ErrorFetchBalance.unknown),
    ])
    func transportErrorMapping(code: RPCError.Code, expected: ErrorFetchBalance) {
        let error = RPCError(code: code, message: "")
        #expect(ErrorFetchBalance.from(transportError: error) == expected)
    }

    @Test("A deadline-exceeded RPCError routes through .transportFailure end-to-end")
    func deadlineExceeded_routesThroughTransportFailure() {
        let error = RPCError(code: .deadlineExceeded, message: "")
        let mapped = ErrorFetchBalance.from(transportError: error)

        #expect(mapped == .transportFailure)
        #expect(mapped.isReportable == false)
    }
}
