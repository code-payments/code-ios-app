import Foundation
import Testing
import FlipcashAPI
@testable import FlipcashCore

@Suite("ErrorSubmitIntent parsing")
struct ErrorSubmitIntentTests {

    // MARK: - Denied

    @Test("denied with UNSPECIFIED code and reason preserves both")
    func deniedWithReason() throws {
        let proto = makeError(code: .denied, details: [
            makeDeniedDetails(code: .unspecified, reason: "spam guard triggered")
        ])

        let denied = try #require(ErrorSubmitIntent(error: proto).deniedPayload)

        #expect(denied.reasons == [.unspecified])
        #expect(denied.messages == ["spam guard triggered"])
    }

    @Test("denied with no error details produces empty reasons and messages")
    func deniedWithoutDetails() throws {
        let proto = makeError(code: .denied, details: [])

        let denied = try #require(ErrorSubmitIntent(error: proto).deniedPayload)

        #expect(denied.reasons.isEmpty)
        #expect(denied.messages.isEmpty)
    }

    @Test("denied with multiple details collects every reason and message")
    func deniedWithMultipleDetails() throws {
        let proto = makeError(code: .denied, details: [
            makeDeniedDetails(code: .unspecified, reason: "first"),
            makeDeniedDetails(code: .unspecified, reason: "second")
        ])

        let denied = try #require(ErrorSubmitIntent(error: proto).deniedPayload)

        #expect(denied.reasons == [.unspecified, .unspecified])
        #expect(denied.messages == ["first", "second"])
    }

    @Test("denied drops empty reason strings but keeps the code")
    func deniedWithEmptyReason() throws {
        let proto = makeError(code: .denied, details: [
            makeDeniedDetails(code: .unspecified, reason: "")
        ])

        let denied = try #require(ErrorSubmitIntent(error: proto).deniedPayload)

        #expect(denied.reasons == [.unspecified])
        #expect(denied.messages.isEmpty)
    }

    @Test("denied with unknown future code drops the code but keeps the message")
    func deniedWithUnrecognizedCode() throws {
        let proto = makeError(code: .denied, details: [
            makeDeniedDetails(code: .UNRECOGNIZED(99), reason: "future reason")
        ])

        let denied = try #require(ErrorSubmitIntent(error: proto).deniedPayload)

        #expect(denied.reasons.isEmpty)
        #expect(denied.messages == ["future reason"])
    }

    @Test("denied does not harvest messages from reasonString error details")
    func deniedIgnoresReasonStringDetails() throws {
        var reasonStringDetails = Ocp_Transaction_V1_ErrorDetails()
        reasonStringDetails.reasonString = .with { $0.reason = "should be ignored for .denied" }

        let proto = makeError(code: .denied, details: [reasonStringDetails])

        let denied = try #require(ErrorSubmitIntent(error: proto).deniedPayload)

        #expect(denied.reasons.isEmpty)
        #expect(denied.messages.isEmpty)
    }

    // MARK: - Other codes

    @Test("invalidIntent collects reasonString messages")
    func invalidIntentWithReasons() {
        var details = Ocp_Transaction_V1_ErrorDetails()
        details.reasonString = .with { $0.reason = "invalid amount" }

        let proto = makeError(code: .invalidIntent, details: [details])

        let error = ErrorSubmitIntent(error: proto)

        guard case let .invalidIntent(reasons) = error else {
            Issue.record("Expected .invalidIntent, got \(error)")
            return
        }
        #expect(reasons == ["invalid amount"])
    }

    @Test("signatureError code maps to .signatureError")
    func signatureError() {
        let proto = makeError(code: .signatureError, details: [])

        let error = ErrorSubmitIntent(error: proto)

        guard case .signatureError = error else {
            Issue.record("Expected .signatureError, got \(error)")
            return
        }
    }

    @Test("staleState collects reasonString messages and produces no kinds when nothing matches")
    func staleStateWithReasons() throws {
        var details = Ocp_Transaction_V1_ErrorDetails()
        details.reasonString = .with { $0.reason = "balance changed" }

        let proto = makeError(code: .staleState, details: [details])

        let payload = try #require(ErrorSubmitIntent(error: proto).staleStatePayload)
        #expect(payload.reasons == ["balance changed"])
        #expect(payload.kinds.isEmpty)
    }

    @Test("UNRECOGNIZED top-level code maps to .unknown")
    func unrecognizedCode() {
        let proto = makeError(code: .UNRECOGNIZED(99), details: [])

        let error = ErrorSubmitIntent(error: proto)

        guard case .unknown = error else {
            Issue.record("Expected .unknown, got \(error)")
            return
        }
    }

    // MARK: - StaleStateKind

    @Test(
        "staleState parses .alreadyClaimed across server phrasings (case-insensitive)",
        arguments: [
            "gift card balance has already been claimed",
            "Already Claimed",
            "Gift Card BALANCE Has Already Been CLAIMED",
        ]
    )
    func staleStateParsesAlreadyClaimed(reason: String) throws {
        var details = Ocp_Transaction_V1_ErrorDetails()
        details.reasonString = .with { $0.reason = reason }

        let proto = makeError(code: .staleState, details: [details])

        let payload = try #require(ErrorSubmitIntent(error: proto).staleStatePayload)
        #expect(payload.kinds == [.alreadyClaimed])
    }

    @Test("StaleStateKind.init returns nil for an unrecognized reason")
    func staleStateKindReturnsNilForUnknownReason() {
        #expect(ErrorSubmitIntent.StaleStateKind(serverReason: "something unrelated") == nil)
    }

    @Test("staleState dedupes kinds across multiple matching reasons")
    func staleStateDedupesKinds() throws {
        var first = Ocp_Transaction_V1_ErrorDetails()
        first.reasonString = .with { $0.reason = "gift card balance has already been claimed" }
        var second = Ocp_Transaction_V1_ErrorDetails()
        second.reasonString = .with { $0.reason = "already claimed by another wallet" }

        let proto = makeError(code: .staleState, details: [first, second])

        let payload = try #require(ErrorSubmitIntent(error: proto).staleStatePayload)
        #expect(payload.reasons.count == 2)
        #expect(payload.kinds == [.alreadyClaimed])
    }

    // MARK: - Fixture helpers

    private func makeError(
        code: Ocp_Transaction_V1_SubmitIntentResponse.Error.Code,
        details: [Ocp_Transaction_V1_ErrorDetails]
    ) -> Ocp_Transaction_V1_SubmitIntentResponse.Error {
        var error = Ocp_Transaction_V1_SubmitIntentResponse.Error()
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

extension ErrorSubmitIntent {
    fileprivate var deniedPayload: (reasons: [DeniedReason], messages: [String])? {
        guard case let .denied(reasons, messages) = self else { return nil }
        return (reasons, messages)
    }

    fileprivate var staleStatePayload: (reasons: [String], kinds: Set<StaleStateKind>)? {
        guard case let .staleState(reasons, kinds) = self else { return nil }
        return (reasons, kinds)
    }
}
