//
//  Regression_6a1b80a.swift
//  Flipcash
//
//  Symptom:  On a device with no connectivity, sendVerificationCode times out
//            and PhoneService's failure callback collapses the gRPC deadline
//            into ErrorSendVerificationCode.unknown, which is reportable. The
//            PhoneVerificationViewModel catch-all then ships a Bugsnag warning
//            per retry, misrepresenting a transport timeout as a server
//            "unknown". checkVerificationCode and unlinkPhone share the shape.
//
//  Fix:      Add `.transportFailure` (isReportable: false) and a static
//            `from(transportError:)` helper to each of the three phone error
//            enums, classifying gRPC timeout / unavailable into it. The three
//            PhoneService failure callbacks route through the helper.
//            ErrorReporting already honors ServerError.isReportable, so the
//            viewModel catch suppresses these reports automatically.
//

import Foundation
import Testing
import GRPC
import FlipcashCore

@Suite("Regression: 6a1b80a – Phone verification no longer reports RPC timeouts", .bug(id: "6a1b80a33b49fe77ec7d4aec"))
struct Regression_6a1b80a {

    @Test("ErrorSendVerificationCode reportability is correct for every case", arguments: [
        (ErrorSendVerificationCode.ok,                   false),
        (ErrorSendVerificationCode.denied,               false),
        (ErrorSendVerificationCode.rateLimited,          false),
        (ErrorSendVerificationCode.invalidPhoneNumber,   false),
        (ErrorSendVerificationCode.unsupportedPhoneType, false),
        (ErrorSendVerificationCode.unknown,              true),
        (ErrorSendVerificationCode.transportFailure,     false),
    ])
    func sendReportability(error: ErrorSendVerificationCode, expected: Bool) {
        #expect(error.isReportable == expected)
    }

    @Test("gRPC transport errors map to the right ErrorSendVerificationCode case", arguments: [
        (GRPCStatus.Code.deadlineExceeded, ErrorSendVerificationCode.transportFailure),
        (GRPCStatus.Code.unavailable,      ErrorSendVerificationCode.transportFailure),
        (GRPCStatus.Code.cancelled,        ErrorSendVerificationCode.unknown),
        (GRPCStatus.Code.invalidArgument,  ErrorSendVerificationCode.unknown),
        (GRPCStatus.Code.permissionDenied, ErrorSendVerificationCode.unknown),
        (GRPCStatus.Code.internalError,    ErrorSendVerificationCode.unknown),
    ])
    func sendTransportMapping(code: GRPCStatus.Code, expected: ErrorSendVerificationCode) {
        let status = GRPCStatus(code: code, message: nil)
        #expect(ErrorSendVerificationCode.from(transportError: status) == expected)
    }

    @Test("GRPCError.RPCTimedOut routes through .transportFailure end-to-end")
    func rpcTimedOut_routesThroughTransportFailure() {
        let timeout = GRPCError.RPCTimedOut(.deadline(.now()))
        let status = timeout.makeGRPCStatus()
        let mapped = ErrorSendVerificationCode.from(transportError: status)

        #expect(status.code == .deadlineExceeded)
        #expect(mapped == .transportFailure)
        #expect(mapped.isReportable == false)
    }

    @Test("checkVerificationCode and unlinkPhone share the transport-failure classification", arguments: [
        GRPCStatus.Code.deadlineExceeded,
        GRPCStatus.Code.unavailable,
    ])
    func siblingsClassifyTransportFailure(code: GRPCStatus.Code) {
        let status = GRPCStatus(code: code, message: nil)

        #expect(ErrorCheckVerificationCode.from(transportError: status) == .transportFailure)
        #expect(ErrorCheckVerificationCode.transportFailure.isReportable == false)

        #expect(ErrorUnlinkPhone.from(transportError: status) == .transportFailure)
        #expect(ErrorUnlinkPhone.transportFailure.isReportable == false)
    }
}
