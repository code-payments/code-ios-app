//
//  Regression_6a10ebf.swift
//  Flipcash
//
//  Symptom:  UsdcSweepOperation fires on every scenePhase → active. After a
//            long background the gRPC channel needs to reconnect; the unary
//            15s deadline expires first and AccountInfoService's failure
//            callbacks collapse the timeout into ErrorFetchBalance.unknown,
//            which is reportable. Result: a Bugsnag report per cold resume
//            that misrepresents a transport timeout as a server "unknown".
//
//  Fix:      Add ErrorFetchBalance.transportFailure (isReportable: false) and
//            a static `from(transportError:)` helper that classifies gRPC
//            timeout / unavailable / cancelled into it. AccountInfoService's
//            three failure callbacks route through the helper. ErrorReporting
//            already honors ServerError.isReportable, so the sweep catch
//            suppresses these reports automatically.
//

import Foundation
import Testing
import GRPC
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
        (GRPCStatus.Code.deadlineExceeded, ErrorFetchBalance.transportFailure),
        (GRPCStatus.Code.unavailable,      ErrorFetchBalance.transportFailure),
        (GRPCStatus.Code.cancelled,        ErrorFetchBalance.unknown),
        (GRPCStatus.Code.invalidArgument,  ErrorFetchBalance.unknown),
        (GRPCStatus.Code.permissionDenied, ErrorFetchBalance.unknown),
        (GRPCStatus.Code.internalError,    ErrorFetchBalance.unknown),
    ])
    func transportErrorMapping(code: GRPCStatus.Code, expected: ErrorFetchBalance) {
        let status = GRPCStatus(code: code, message: nil)
        #expect(ErrorFetchBalance.from(transportError: status) == expected)
    }

    @Test("GRPCError.RPCTimedOut routes through .transportFailure end-to-end")
    func rpcTimedOut_routesThroughTransportFailure() {
        let timeout = GRPCError.RPCTimedOut(.deadline(.now()))
        let status = timeout.makeGRPCStatus()
        let mapped = ErrorFetchBalance.from(transportError: status)

        #expect(status.code == .deadlineExceeded)
        #expect(mapped == .transportFailure)
        #expect(mapped.isReportable == false)
    }
}
