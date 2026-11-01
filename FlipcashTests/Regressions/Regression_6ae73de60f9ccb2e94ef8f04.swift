//
//  Regression_6ae73de60f9ccb2e94ef8f04.swift
//  FlipcashTests
//
//  "Failed to login" reported as ErrorLoginAccount.unknown with nothing in
//  the attached logs saying why: from(transportError:) mapped the RPCError
//  to .unknown and dropped its code and message, and the bare catch in
//  AccountService.login mapped any other error to .unknown silently.
//
//  Fix: both paths log the underlying error before returning .unknown, so the
//  line lands in the ring buffer attached to the next Bugsnag event.
//

import Foundation
import Testing
import GRPCCore
import FlipcashCore

@Suite("Regression: 6ae73de – unknown login error drops the gRPC code", .bug("6ae73de60f9ccb2e94ef8f04"))
struct Regression_6ae73de {

    @Test("An internalError RPCError maps to .unknown and logs its code and message")
    func transportError_internalError_logsCodeAndMessage() {
        let marker = "regression-6ae73de-\(UUID().uuidString)"

        let error = ErrorLoginAccount.from(transportError: RPCError(code: .internalError, message: marker))

        #expect(error == .unknown)
        let line = LogStore.shared.recentEntries().first { $0.contains(marker) }
        #expect(line?.contains("internalError") == true)
        #expect(line?.contains("ErrorLoginAccount") == true)
    }

    @Test("A non-RPC error maps to .unknown and logs its type and description")
    func unexpectedError_logsTypeAndDescription() {
        let marker = "regression-6ae73de-\(UUID().uuidString)"

        let error = ErrorLoginAccount.from(unexpectedError: MarkerError(marker: marker))

        #expect(error == .unknown)
        let line = LogStore.shared.recentEntries().first { $0.contains(marker) }
        #expect(line?.contains("MarkerError") == true)
        #expect(line?.contains("ErrorLoginAccount") == true)
    }
}

private struct MarkerError: Error {
    let marker: String
}
