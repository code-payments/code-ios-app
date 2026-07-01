import Foundation
import Testing
import FlipcashAPI
@testable import FlipcashCore

@Suite("ErrorStatelessSwap parsing")
struct ErrorStatelessSwapTests {

    @Test(
        "invalidSwap collects every non-empty reasonString from errorDetails",
        arguments: [
            (details: [] as [Ocp_Transaction_V1_ErrorDetails], expected: [] as [String]),
            (details: [.reasonString("destination timelock vault account not opened")], expected: ["destination timelock vault account not opened"]),
            (details: [.reasonString("")], expected: []),
            (details: [.denied(code: .unspecified, reason: "ignored")], expected: []),
            (details: [.reasonString("first"), .reasonString("second")], expected: ["first", "second"]),
        ]
    )
    func invalidSwap_reasonExtraction(details: [Ocp_Transaction_V1_ErrorDetails], expected: [String]) throws {
        let proto = makeError(code: .invalidSwap, details: details)

        let reasons = try #require(ErrorStatelessSwap(error: proto).invalidSwapReasons)

        #expect(reasons == expected)
    }

    @Test(
        "denied collects every non-empty deniedReason from errorDetails",
        arguments: [
            (details: [] as [Ocp_Transaction_V1_ErrorDetails], expected: [] as [String]),
            (details: [.denied(code: .unspecified, reason: "rate limited")], expected: ["rate limited"]),
            (details: [.denied(code: .unspecified, reason: "")], expected: []),
            (details: [.reasonString("ignored")], expected: []),
            (
                details: [
                    .denied(code: .unspecified, reason: "first"),
                    .denied(code: .unspecified, reason: "second")
                ],
                expected: ["first", "second"]
            ),
        ]
    )
    func denied_reasonExtraction(details: [Ocp_Transaction_V1_ErrorDetails], expected: [String]) throws {
        let proto = makeError(code: .denied, details: details)

        let reasons = try #require(ErrorStatelessSwap(error: proto).deniedReasons)

        #expect(reasons == expected)
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

    @Test("reportingLevel is .error for .invalidSwap regardless of reasons")
    func reportingLevel_invalidSwap() {
        #expect(ErrorStatelessSwap.invalidSwap(reasons: []).reportingLevel == .error)
        #expect(ErrorStatelessSwap.invalidSwap(reasons: ["anything"]).reportingLevel == .error)
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
    fileprivate var invalidSwapReasons: [String]? {
        guard case .invalidSwap(let reasons) = self else { return nil }
        return reasons
    }

    fileprivate var deniedReasons: [String]? {
        guard case .denied(let reasons) = self else { return nil }
        return reasons
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
