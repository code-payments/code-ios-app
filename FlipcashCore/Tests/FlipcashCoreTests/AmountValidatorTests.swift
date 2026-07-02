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
}
