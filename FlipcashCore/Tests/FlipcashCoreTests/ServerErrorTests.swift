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

@Suite("ReportingOutcome.resolve(error:)")
struct ReportingOutcomeTests {

    private struct Classified: ServerError {
        let reportingLevel: ErrorReportingLevel
    }

    private struct Unclassified: Error {}

    @Test("Suppressed ServerError is dropped")
    func suppressedDropped() {
        #expect(ReportingOutcome.resolve(error: Classified(reportingLevel: .suppressed)) == .drop)
    }

    @Test("Info ServerError stays info")
    func infoStaysInfo() {
        #expect(ReportingOutcome.resolve(error: Classified(reportingLevel: .info)) == .info)
    }

    @Test("Error-level ServerError reports as error")
    func errorLevelReports() {
        #expect(ReportingOutcome.resolve(error: Classified(reportingLevel: .error)) == .error)
    }

    @Test("Unclassified error reports as error")
    func unclassifiedIsError() {
        #expect(ReportingOutcome.resolve(error: Unclassified()) == .error)
    }

    @Test("CancellationError is dropped")
    func cancellationDropped() {
        #expect(ReportingOutcome.resolve(error: CancellationError()) == .drop)
    }

    @Test("userFacing lifts only suppressed to info")
    func userFacingLift() {
        #expect(ReportingOutcome.resolve(error: Classified(reportingLevel: .suppressed), userFacing: true) == .info)
        #expect(ReportingOutcome.resolve(error: Classified(reportingLevel: .error), userFacing: true) == .error)
    }
}
