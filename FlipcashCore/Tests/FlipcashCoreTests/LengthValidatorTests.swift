import Foundation
import Testing
@testable import FlipcashCore

@Suite("LengthValidator")
struct LengthValidatorTests {

    @Test("Accepts non-blank input up to the limit", arguments: [
        "a",
        " padded ",
        String(repeating: "x", count: 10),
    ])
    func accepts_withinLimit(input: String) {
        let validator = LengthValidator(maxLength: 10)
        #expect(validator.validate(input) == input)
    }

    @Test("Rejects blank and overlong input", arguments: [
        "",
        "   ",
        "\n\t",
        String(repeating: "x", count: 11),
    ])
    func rejects_blankOrOverlong(input: String) {
        let validator = LengthValidator(maxLength: 10)
        #expect(validator.validate(input) == nil)
    }
}
