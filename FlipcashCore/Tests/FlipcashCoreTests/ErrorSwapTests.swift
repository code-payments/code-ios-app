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
            .denied(code: .unspecified, reason: "spam guard triggered")
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
            .denied(code: .unspecified, reason: "first"),
            .denied(code: .unspecified, reason: "second")
        ])

        let denied = try #require(ErrorSwap(error: proto).deniedPayload)

        #expect(denied.reasons == [.unspecified, .unspecified])
        #expect(denied.kinds.isEmpty)
        #expect(denied.messages == ["first", "second"])
    }

    @Test("denied drops empty reason strings but keeps the code")
    func deniedWithEmptyReason() throws {
        let proto = makeError(code: .denied, details: [
            .denied(code: .unspecified, reason: "")
        ])

        let denied = try #require(ErrorSwap(error: proto).deniedPayload)

        #expect(denied.reasons == [.unspecified])
        #expect(denied.kinds.isEmpty)
        #expect(denied.messages.isEmpty)
    }

    @Test("denied with unknown future code drops the code but keeps the message")
    func deniedWithUnrecognizedCode() throws {
        let proto = makeError(code: .denied, details: [
            .denied(code: .UNRECOGNIZED(99), reason: "future reason")
        ])

        let denied = try #require(ErrorSwap(error: proto).deniedPayload)

        #expect(denied.reasons.isEmpty)
        #expect(denied.kinds.isEmpty)
        #expect(denied.messages == ["future reason"])
    }

    @Test("denied ignores non-denied error detail types")
    func deniedIgnoresOtherDetailTypes() throws {
        let proto = makeError(code: .denied, details: [
            .reasonString("should be ignored")
        ])

        let denied = try #require(ErrorSwap(error: proto).deniedPayload)

        #expect(denied.reasons.isEmpty)
        #expect(denied.kinds.isEmpty)
        #expect(denied.messages.isEmpty)
    }

    // MARK: - DeniedKind

    @Test("denied with 'swap would not generate a sell fee' classifies as insufficientSellFee")
    func deniedClassifiesInsufficientSellFee() throws {
        let proto = makeError(code: .denied, details: [
            .denied(code: .unspecified, reason: "swap would not generate a sell fee")
        ])

        let denied = try #require(ErrorSwap(error: proto).deniedPayload)

        #expect(denied.kinds == [.insufficientSellFee])
        #expect(denied.messages == ["swap would not generate a sell fee"])
    }

    @Test("duplicate denial reasons produce a single kind entry")
    func deniedKindDeduplication() throws {
        let proto = makeError(code: .denied, details: [
            .denied(code: .unspecified, reason: "swap would not generate a sell fee"),
            .denied(code: .unspecified, reason: "swap would not generate a sell fee")
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

    // MARK: - InvalidSwap

    @Test(
        "invalidSwap takes the first non-empty reasonString from errorDetails",
        arguments: [
            (details: [] as [Ocp_Transaction_V1_ErrorDetails], expected: String?.none),
            (details: [.reasonString("swap amount out of allowed range")], expected: .some("swap amount out of allowed range")),
            (details: [.reasonString("")], expected: .none),
            (details: [.denied(code: .unspecified, reason: "ignored")], expected: .none),
            (details: [.reasonString(""), .reasonString("second")], expected: .some("second")),
        ]
    )
    func invalidSwap_reasonExtraction(details: [Ocp_Transaction_V1_ErrorDetails], expected: String?) throws {
        let proto = makeError(code: .invalidSwap, details: details)

        let reason = try #require(ErrorSwap(error: proto).invalidSwapReason)

        #expect(reason == expected)
    }

    // MARK: - Other codes

    @Test("signatureError code maps to .signatureError")
    func signatureError() {
        let error = ErrorSwap(error: makeError(code: .signatureError, details: []))

        #expect(error.isSignatureError)
    }

    @Test("UNRECOGNIZED top-level code maps to .unknown")
    func unrecognizedCode() {
        let error = ErrorSwap(error: makeError(code: .UNRECOGNIZED(99), details: []))

        #expect(error.isUnknown)
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
}

// MARK: - Test payload extractors

extension ErrorSwap {
    fileprivate var deniedPayload: (reasons: [DeniedReason], kinds: Set<DeniedKind>, messages: [String])? {
        guard case let .denied(reasons, kinds, messages) = self else { return nil }
        return (reasons, kinds, messages)
    }

    /// Double-optional so `try #require` distinguishes "not `.invalidSwap`"
    /// (outer `nil`) from "`.invalidSwap(reason: nil)`" (inner `nil`).
    fileprivate var invalidSwapReason: String?? {
        guard case .invalidSwap(let reason) = self else { return nil }
        return .some(reason)
    }

    fileprivate var isSignatureError: Bool {
        if case .signatureError = self { return true }
        return false
    }

    fileprivate var isUnknown: Bool {
        if case .unknown = self { return true }
        return false
    }
}
