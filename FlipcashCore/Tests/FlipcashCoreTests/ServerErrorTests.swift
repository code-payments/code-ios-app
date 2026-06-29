import Foundation
import Testing
@testable import FlipcashCore

@Suite("ServerError reporting level")
struct ServerErrorTests {

    @Test("ErrorLoginAccount reporting level", arguments: [
        (ErrorLoginAccount.denied, ErrorReportingLevel.info),
        (ErrorLoginAccount.invalidTimestamp, .info),
        (ErrorLoginAccount.unknown, .error),
    ])
    func loginAccount_reportingLevel(error: ErrorLoginAccount, expected: ErrorReportingLevel) {
        #expect(error.reportingLevel == expected)
    }

    @Test("ErrorRegisterAccount reporting level", arguments: [
        (ErrorRegisterAccount.denied, ErrorReportingLevel.info),
        (ErrorRegisterAccount.invalidSignature, .info),
        (ErrorRegisterAccount.unknown, .error),
    ])
    func registerAccount_reportingLevel(error: ErrorRegisterAccount, expected: ErrorReportingLevel) {
        #expect(error.reportingLevel == expected)
    }

    @Test("ErrorSubmitIntent reporting level", arguments: [
        (ErrorSubmitIntent.denied([], messages: []), ErrorReportingLevel.info),
        (ErrorSubmitIntent.invalidIntent([]), .info),
        (ErrorSubmitIntent.staleState([], kinds: []), .info),
        (ErrorSubmitIntent.signatureError, .error),
        (ErrorSubmitIntent.unknown, .error),
        (ErrorSubmitIntent.deviceTokenUnavailable, .error),
    ])
    func submitIntent_reportingLevel(error: ErrorSubmitIntent, expected: ErrorReportingLevel) {
        #expect(error.reportingLevel == expected)
    }

    @Test("ErrorSwap.fundingIntent delegates to wrapped ErrorSubmitIntent", arguments: [
        (ErrorSubmitIntent.denied([], messages: []), ErrorReportingLevel.info),
        (ErrorSubmitIntent.signatureError, .error),
    ])
    func errorSwap_fundingIntentDelegates(inner: ErrorSubmitIntent, expected: ErrorReportingLevel) {
        #expect(ErrorSwap.fundingIntent(inner).reportingLevel == expected)
    }

}
