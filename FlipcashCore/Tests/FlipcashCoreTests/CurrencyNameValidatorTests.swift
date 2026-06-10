import Foundation
import Testing
@testable import FlipcashCore

@Suite("CurrencyNameValidator")
struct CurrencyNameValidatorTests {

    @Test("Accepts printable-ASCII names and returns them unchanged", arguments: [
        "A",
        "My Coin",
        "Coin!$#@",
        String(repeating: "A", count: 32),
    ])
    func accepts_validName(input: String) {
        let validator = CurrencyNameValidator()
        #expect(validator.validate(input) == input)
    }

    @Test("Rejects empty, overlong, non-ASCII, and edge-whitespace names", arguments: [
        "",
        String(repeating: "A", count: 33),
        " Coin",
        "Coin ",
        "   ",
        "café",
        "Coin🎉",
        "Co\nin",
    ])
    func rejects_invalidName(input: String) {
        let validator = CurrencyNameValidator()
        #expect(validator.validate(input) == nil)
    }
}
