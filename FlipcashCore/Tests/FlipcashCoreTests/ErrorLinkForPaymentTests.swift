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

    @Test("Only the unknown case is reportable")
    func reportability() {
        #expect(ErrorLinkForPayment.ok.isReportable == false)
        #expect(ErrorLinkForPayment.denied.isReportable == false)
        #expect(ErrorLinkForPayment.notAssociated.isReportable == false)
        #expect(ErrorLinkForPayment.unknown.isReportable == true)
    }

    @Test("A result code the client doesn't model maps to nil, which the caller coalesces to .unknown")
    func unmodeledResultCodeIsNil() {
        #expect(ErrorLinkForPayment(rawValue: 99) == nil)
    }
}
