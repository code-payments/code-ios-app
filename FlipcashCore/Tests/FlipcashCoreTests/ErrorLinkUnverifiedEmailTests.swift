import Testing
@testable import FlipcashCore
import FlipcashAPI

@Suite("ErrorLinkUnverifiedEmail")
struct ErrorLinkUnverifiedEmailTests {

    @Test("Maps every LinkUnverifiedResponse.Result case by raw value")
    func mapsProtoResult() {
        typealias R = Flipcash_Email_V1_LinkUnverifiedResponse.Result
        #expect(ErrorLinkUnverifiedEmail(rawValue: R.ok.rawValue) == .ok)
        #expect(ErrorLinkUnverifiedEmail(rawValue: R.denied.rawValue) == .denied)
    }

    @Test("A result this client doesn't know is not mistaken for a known case")
    func unknownResultHasNoCase() {
        typealias R = Flipcash_Email_V1_LinkUnverifiedResponse.Result
        #expect(ErrorLinkUnverifiedEmail(rawValue: R.UNRECOGNIZED(2).rawValue) == nil)
    }
}
