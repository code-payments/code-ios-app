import Foundation
import Testing
import FlipcashAPI
@testable import FlipcashCore

@Suite("ErrorSwap parsing")
struct ErrorSwapTests {

    // MARK: - Denied

    @Test("denied with UNSPECIFIED code and reason preserves both")
    func deniedWithReason() throws {
        let proto = makeError(code: .denied, details: [
            makeDeniedDetails(code: .unspecified, reason: "spam guard triggered")
        ])

        let denied = try #require(ErrorSwap(error: proto).deniedPayload)

        #expect(denied.reasons == [.unspecified])
        #expect(denied.kinds.isEmpty)
        #expect(denied.messages == ["spam guard triggered"])
    }

    @Test("denied with no error details produces empty reasons, kinds, and messages")
    func deniedWithoutDetails() throws {
        let proto = makeError(code: .denied, details: [])

        let denied = try #require(ErrorSwap(error: proto).deniedPayload)

        #expect(denied.reasons.isEmpty)
        #expect(denied.kinds.isEmpty)
        #expect(denied.messages.isEmpty)
    }

    @Test("denied with multiple details collects every reason and message")
    func deniedWithMultipleDetails() throws {
        let proto = makeError(code: .denied, details: [
            makeDeniedDetails(code: .unspecified, reason: "first"),
            makeDeniedDetails(code: .unspecified, reason: "second")
        ])

        let denied = try #require(ErrorSwap(error: proto).deniedPayload)

        #expect(denied.reasons == [.unspecified, .unspecified])
        #expect(denied.kinds.isEmpty)
        #expect(denied.messages == ["first", "second"])
    }

    @Test("denied drops empty reason strings but keeps the code")
    func deniedWithEmptyReason() throws {
        let proto = makeError(code: .denied, details: [
            makeDeniedDetails(code: .unspecified, reason: "")
        ])

        let denied = try #require(ErrorSwap(error: proto).deniedPayload)

        #expect(denied.reasons == [.unspecified])
        #expect(denied.kinds.isEmpty)
        #expect(denied.messages.isEmpty)
    }

    @Test("denied with unknown future code drops the code but keeps the message")
    func deniedWithUnrecognizedCode() throws {
        let proto = makeError(code: .denied, details: [
            makeDeniedDetails(code: .UNRECOGNIZED(99), reason: "future reason")
        ])

        let denied = try #require(ErrorSwap(error: proto).deniedPayload)

        #expect(denied.reasons.isEmpty)
        #expect(denied.kinds.isEmpty)
        #expect(denied.messages == ["future reason"])
    }

    @Test("denied ignores non-denied error detail types")
    func deniedIgnoresOtherDetailTypes() throws {
        var reasonStringDetails = Ocp_Transaction_V1_ErrorDetails()
        reasonStringDetails.reasonString = .with { $0.reason = "should be ignored" }

        let proto = makeError(code: .denied, details: [reasonStringDetails])

        let denied = try #require(ErrorSwap(error: proto).deniedPayload)

        #expect(denied.reasons.isEmpty)
        #expect(denied.kinds.isEmpty)
        #expect(denied.messages.isEmpty)
    }

    // MARK: - DeniedKind

    @Test("denied with 'swap would not generate a sell fee' classifies as insufficientSellFee")
    func deniedClassifiesInsufficientSellFee() throws {
        let proto = makeError(code: .denied, details: [
            makeDeniedDetails(code: .unspecified, reason: "swap would not generate a sell fee")
        ])

        let denied = try #require(ErrorSwap(error: proto).deniedPayload)

        #expect(denied.kinds == [.insufficientSellFee])
        #expect(denied.messages == ["swap would not generate a sell fee"])
    }

    @Test("duplicate denial reasons produce a single kind entry")
    func deniedKindDeduplication() throws {
        let proto = makeError(code: .denied, details: [
            makeDeniedDetails(code: .unspecified, reason: "swap would not generate a sell fee"),
            makeDeniedDetails(code: .unspecified, reason: "swap would not generate a sell fee")
        ])

        let denied = try #require(ErrorSwap(error: proto).deniedPayload)

        #expect(denied.kinds == [.insufficientSellFee])
        #expect(denied.messages.count == 2)
    }

    @Test(
        "DeniedKind.init(serverReason:) maps known strings and returns nil otherwise",
        arguments: [
            ("swap would not generate a sell fee", ErrorSwap.DeniedKind?.some(.insufficientSellFee)),
            ("Swap Would Not Generate A Sell Fee", .insufficientSellFee),
            ("prefix would not generate a sell fee suffix", .insufficientSellFee),
            ("some unrelated guard triggered", nil),
            ("", nil)
        ] as [(String, ErrorSwap.DeniedKind?)]
    )
    func deniedKindParsing(serverReason: String, expected: ErrorSwap.DeniedKind?) {
        #expect(ErrorSwap.DeniedKind(serverReason: serverReason) == expected)
    }

    // MARK: - Other codes

    @Test("invalidSwap code maps to .invalidSwap")
    func invalidSwap() {
        let proto = makeError(code: .invalidSwap, details: [])

        let error = ErrorSwap(error: proto)

        guard case .invalidSwap = error else {
            Issue.record("Expected .invalidSwap, got \(error)")
            return
        }
    }

    @Test("signatureError code maps to .signatureError")
    func signatureError() {
        let proto = makeError(code: .signatureError, details: [])

        let error = ErrorSwap(error: proto)

        guard case .signatureError = error else {
            Issue.record("Expected .signatureError, got \(error)")
            return
        }
    }

    @Test("UNRECOGNIZED top-level code maps to .unknown")
    func unrecognizedCode() {
        let proto = makeError(code: .UNRECOGNIZED(99), details: [])

        let error = ErrorSwap(error: proto)

        guard case .unknown = error else {
            Issue.record("Expected .unknown, got \(error)")
            return
        }
    }

    // MARK: - Fixture helpers

    private func makeError(
        code: Ocp_Transaction_V1_StatefulSwapResponse.Error.Code,
        details: [Ocp_Transaction_V1_ErrorDetails]
    ) -> Ocp_Transaction_V1_StatefulSwapResponse.Error {
        var error = Ocp_Transaction_V1_StatefulSwapResponse.Error()
        error.code = code
        error.errorDetails = details
        return error
    }

    private func makeDeniedDetails(
        code: Ocp_Transaction_V1_DeniedErrorDetails.Code,
        reason: String
    ) -> Ocp_Transaction_V1_ErrorDetails {
        var deniedDetails = Ocp_Transaction_V1_DeniedErrorDetails()
        deniedDetails.code = code
        deniedDetails.reason = reason

        var details = Ocp_Transaction_V1_ErrorDetails()
        details.denied = deniedDetails
        return details
    }
}

// MARK: - Test helpers

extension ErrorSwap {
    fileprivate var deniedPayload: (reasons: [DeniedReason], kinds: Set<DeniedKind>, messages: [String])? {
        guard case let .denied(reasons, kinds, messages) = self else { return nil }
        return (reasons, kinds, messages)
    }
}
