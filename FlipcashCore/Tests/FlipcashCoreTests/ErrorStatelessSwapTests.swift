import Foundation
import Testing
import FlipcashAPI
@testable import FlipcashCore

@Suite("ErrorStatelessSwap parsing")
struct ErrorStatelessSwapTests {

    @Test(
        "invalidSwap takes the first non-empty reasonString from errorDetails",
        arguments: [
            (details: [] as [Ocp_Transaction_V1_ErrorDetails], expected: String?.none),
            (details: [.reasonString("destination timelock vault account not opened")], expected: .some("destination timelock vault account not opened")),
            (details: [.reasonString("")], expected: .none),
            (details: [.denied(code: .unspecified, reason: "ignored")], expected: .none),
            (details: [.reasonString(""), .reasonString("second")], expected: .some("second")),
        ]
    )
    func invalidSwap_reasonExtraction(details: [Ocp_Transaction_V1_ErrorDetails], expected: String?) throws {
        let proto = makeError(code: .invalidSwap, details: details)

        let reason = try #require(ErrorStatelessSwap(error: proto).invalidSwapReason)

        #expect(reason == expected)
    }

    @Test("denied with reason detail extracts the reason")
    func denied_extractsReason() throws {
        let proto = makeError(code: .denied, details: [
            .denied(code: .unspecified, reason: "rate limited")
        ])

        let reason = try #require(ErrorStatelessSwap(error: proto).deniedReason)

        #expect(reason == "rate limited")
    }

    @Test("signatureError code maps to .signatureError")
    func signatureError() {
        let error = ErrorStatelessSwap(error: makeError(code: .signatureError, details: []))

        #expect(error.isSignatureError)
    }

    @Test("transactionFailed code maps to .transactionFailed")
    func transactionFailed() {
        let error = ErrorStatelessSwap(error: makeError(code: .transactionFailed, details: []))

        #expect(error.isTransactionFailed)
    }

    @Test("UNRECOGNIZED code maps to .unknown")
    func unrecognized() {
        let error = ErrorStatelessSwap(error: makeError(code: .UNRECOGNIZED(99), details: []))

        #expect(error.isUnknown)
    }

    @Test("isReportable returns true for .invalidSwap regardless of reason")
    func isReportable_invalidSwap() {
        #expect(ErrorStatelessSwap.invalidSwap(reason: nil).isReportable)
        #expect(ErrorStatelessSwap.invalidSwap(reason: "anything").isReportable)
    }

    // MARK: - Fixture helpers

    private func makeError(
        code: Ocp_Transaction_V1_StatelessSwapResponse.Error.Code,
        details: [Ocp_Transaction_V1_ErrorDetails]
    ) -> Ocp_Transaction_V1_StatelessSwapResponse.Error {
        var error = Ocp_Transaction_V1_StatelessSwapResponse.Error()
        error.code = code
        error.errorDetails = details
        return error
    }
}

// MARK: - Test payload extractors

extension ErrorStatelessSwap {
    /// Double-optional so `try #require` distinguishes "not `.invalidSwap`"
    /// (outer `nil`) from "`.invalidSwap(reason: nil)`" (inner `nil`).
    fileprivate var invalidSwapReason: String?? {
        guard case .invalidSwap(let reason) = self else { return nil }
        return .some(reason)
    }

    fileprivate var deniedReason: String? {
        guard case .denied(let reason) = self else { return nil }
        return reason
    }

    fileprivate var isSignatureError: Bool {
        if case .signatureError = self { return true }
        return false
    }

    fileprivate var isTransactionFailed: Bool {
        if case .transactionFailed = self { return true }
        return false
    }

    fileprivate var isUnknown: Bool {
        if case .unknown = self { return true }
        return false
    }
}
