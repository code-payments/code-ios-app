import Foundation
import Testing
@testable import FlipcashCore

@Suite("ServerError reportability")
struct ServerErrorTests {

    @Test("ErrorLoginAccount reportability", arguments: [
        (ErrorLoginAccount.denied, false),
        (ErrorLoginAccount.invalidTimestamp, false),
        (ErrorLoginAccount.unknown, true),
    ])
    func loginAccount_isReportable(error: ErrorLoginAccount, expected: Bool) {
        #expect(error.isReportable == expected)
    }

    @Test("ErrorRegisterAccount reportability", arguments: [
        (ErrorRegisterAccount.denied, false),
        (ErrorRegisterAccount.invalidSignature, false),
        (ErrorRegisterAccount.unknown, true),
    ])
    func registerAccount_isReportable(error: ErrorRegisterAccount, expected: Bool) {
        #expect(error.isReportable == expected)
    }

    @Test("ErrorSubmitIntent reportability", arguments: [
        (ErrorSubmitIntent.denied([], messages: []), false),
        (ErrorSubmitIntent.invalidIntent([]), false),
        (ErrorSubmitIntent.staleState([], kinds: []), false),
        (ErrorSubmitIntent.signatureError, true),
        (ErrorSubmitIntent.unknown, true),
        (ErrorSubmitIntent.deviceTokenUnavailable, true),
    ])
    func submitIntent_isReportable(error: ErrorSubmitIntent, expected: Bool) {
        #expect(error.isReportable == expected)
    }

    @Test("ErrorSwap.fundingIntent delegates to wrapped ErrorSubmitIntent", arguments: [
        (ErrorSubmitIntent.denied([], messages: []), false),
        (ErrorSubmitIntent.signatureError, true),
    ])
    func errorSwap_fundingIntentDelegates(inner: ErrorSubmitIntent, expected: Bool) {
        #expect(ErrorSwap.fundingIntent(inner).isReportable == expected)
    }

    @Test("Default protocol implementation returns false")
    func defaultIsReportable_returnsFalse() {
        struct Sample: ServerError {}
        #expect(Sample().isReportable == false)
    }
}
