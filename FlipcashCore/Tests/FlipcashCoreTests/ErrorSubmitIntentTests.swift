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

    @Test("staleState collects reasonString messages")
    func staleStateWithReasons() {
        var details = Ocp_Transaction_V1_ErrorDetails()
        details.reasonString = .with { $0.reason = "balance changed" }

        let proto = makeError(code: .staleState, details: [details])

        let error = ErrorSubmitIntent(error: proto)

        guard case let .staleState(reasons) = error else {
            Issue.record("Expected .staleState, got \(error)")
            return
        }
        #expect(reasons == ["balance changed"])
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

    // MARK: - staleState(matchingAny:)

    @Test("staleState matches a fragment present in any reason")
    func staleStateMatchesPresentFragment() {
        let error = ErrorSubmitIntent.staleState([
            "gift card balance has already been claimed"
        ])
        #expect(error.staleState(matchingAny: "already been claimed"))
    }

    @Test("staleState matches case-insensitively on both sides")
    func staleStateCaseInsensitive() {
        let error = ErrorSubmitIntent.staleState(["BALANCE Already Claimed"])
        #expect(error.staleState(matchingAny: "already claimed"))
    }

    @Test("staleState returns true when any of multiple fragments match")
    func staleStateAnyOfMany() {
        let error = ErrorSubmitIntent.staleState(["cached balance version is stale"])
        #expect(error.staleState(
            matchingAny: "already claimed", "cached balance version is stale"
        ))
    }

    @Test("staleState returns false when no fragment is present")
    func staleStateNoMatch() {
        let error = ErrorSubmitIntent.staleState(["unrelated reason"])
        #expect(!error.staleState(matchingAny: "already claimed"))
    }

    @Test("staleState returns false on a non-staleState case")
    func staleStateOnDifferentCase() {
        let error = ErrorSubmitIntent.denied([], messages: ["already claimed"])
        #expect(!error.staleState(matchingAny: "already claimed"))
    }

    @Test("staleState returns false on an empty reasons array")
    func staleStateEmptyReasons() {
        let error = ErrorSubmitIntent.staleState([])
        #expect(!error.staleState(matchingAny: "already claimed"))
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
}
