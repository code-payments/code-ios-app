import Foundation
import Testing
import FlipcashAPI
@testable import FlipcashCore

@Suite("ErrorLinkForPayment")
struct ErrorLinkForPaymentTests {

    @Test(
        "Server result codes map to the matching error case",
        arguments: [
            (result: Flipcash_Phone_V1_LinkForPaymentResponse.Result.ok, expected: ErrorLinkForPayment.ok),
            (result: .denied, expected: .denied),
            (result: .notAssociated, expected: .notAssociated),
        ]
    )
    func resultCodeMapping(result: Flipcash_Phone_V1_LinkForPaymentResponse.Result, expected: ErrorLinkForPayment) {
        #expect(ErrorLinkForPayment(rawValue: result.rawValue) == expected)
    }

    @Test("ok/transport suppressed; denied/not-associated info; only unknown errors")
    func reportingLevel() {
        #expect(ErrorLinkForPayment.ok.reportingLevel == .suppressed)
        #expect(ErrorLinkForPayment.denied.reportingLevel == .info)
        #expect(ErrorLinkForPayment.notAssociated.reportingLevel == .info)
        #expect(ErrorLinkForPayment.transportFailure.reportingLevel == .suppressed)
        #expect(ErrorLinkForPayment.unknown.reportingLevel == .error)
    }

    @Test("A result code the client doesn't model maps to nil, which the caller coalesces to .unknown")
    func unmodeledResultCodeIsNil() {
        #expect(ErrorLinkForPayment(rawValue: 99) == nil)
    }
}
