import Foundation
import Testing
@testable import FlipcashCore

@Suite("PhoneValidator")
struct PhoneValidatorTests {

    @Test("Accepts parseable numbers and returns the E.164 form", arguments: [
        ("+1 415 555 0100", "+14155550100"),
        ("+14155550100", "+14155550100"),
        ("+44 7400 123456", "+447400123456"),
        ("+1 (415) 555-0100", "+14155550100"),
    ])
    func accepts_validPhone(input: String, e164: String) {
        let validator = PhoneValidator()
        #expect(validator.validate(input)?.e164 == e164)
    }

    @Test("Rejects strings that do not parse to a valid number", arguments: [
        "",
        "   ",
        "hello",
        "+1",
        "+1 415 555",
        "+999 123 4567",
    ])
    func rejects_invalidPhone(input: String) {
        let validator = PhoneValidator()
        #expect(validator.validate(input) == nil)
    }
}
