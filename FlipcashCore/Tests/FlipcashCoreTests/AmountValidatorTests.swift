import Foundation
import Testing
@testable import FlipcashCore

@Suite("AmountValidator")
struct AmountValidatorTests {

    @Test("Comma-locale keypad input keeps its fractional part")
    func commaSeparator_keepsFraction() {
        #expect(AmountValidator(separator: ",").validate("1,50") == Decimal(string: "1.5"))
    }

    @Test("Dot-locale keypad input parses unchanged")
    func dotSeparator_keepsFraction() {
        #expect(AmountValidator(separator: ".").validate("1.50") == Decimal(string: "1.5"))
    }

    @Test("Empty input returns nil")
    func emptyInput_returnsNil() {
        #expect(AmountValidator(separator: ",").validate("") == nil)
    }

    @Test("Trailing separator parses as the integer part")
    func trailingSeparator_parsesIntegerPart() {
        #expect(AmountValidator(separator: ",").validate("5,") == 5)
    }

    @Test("Integer-only input is unaffected by the separator")
    func integerOnly_parses() {
        #expect(AmountValidator(separator: ",").validate("150") == 150)
    }

    @Test("Default separator follows the device locale")
    func defaultSeparator_followsLocale() {
        let entered = "2\(AmountValidator.localizedDecimalSeparator)25"
        #expect(AmountValidator().validate(entered) == Decimal(string: "2.25"))
    }

    // MARK: - Rendering back into the keypad's own form

    @Test("A rendered amount parses back to the same value")
    func string_roundTripsThroughValidate() {
        let validator = AmountValidator(separator: ".")

        let rendered = validator.string(from: Decimal(string: "9.9")!, fractionDigits: 2)

        #expect(rendered == "9.90")
        #expect(validator.validate(rendered) == Decimal(string: "9.9"))
    }

    @Test("Rendering uses the keypad's own decimal separator")
    func string_usesConfiguredSeparator() {
        let validator = AmountValidator(separator: ",")

        let rendered = validator.string(from: Decimal(string: "9.9")!, fractionDigits: 2)

        #expect(rendered == "9,90")
        #expect(validator.validate(rendered) == Decimal(string: "9.9"))
    }

    @Test("A zero-decimal currency renders without a separator")
    func string_zeroFractionDigits_hasNoSeparator() {
        #expect(AmountValidator(separator: ".").string(from: 990, fractionDigits: 0) == "990")
    }

    @Test("Rendering never groups digits — the keypad emits none")
    func string_doesNotGroupDigits() {
        #expect(AmountValidator(separator: ".").string(from: Decimal(string: "12345.67")!, fractionDigits: 2) == "12345.67")
    }
}
