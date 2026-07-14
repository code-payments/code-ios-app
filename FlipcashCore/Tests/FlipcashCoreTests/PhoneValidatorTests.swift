import Foundation
import Testing
@testable import FlipcashCore

@Suite("PhoneValidator")
struct PhoneValidatorTests {

    // Nothing to judge yet — the validator's `nil`.
    @Test("Returns nil when no digits have been entered", arguments: [
        "",
        "   ",
        "hello",
    ])
    func validate_empty(input: String) {
        #expect(PhoneValidator(region: .us).validate(input) == nil)
    }

    // Too few digits to be judged — the user is still typing, so we stay quiet.
    @Test("Reports incomplete while a number is still too short", arguments: [
        "4",
        "415",
        "613 809",
    ])
    func validate_incomplete(input: String) {
        #expect(PhoneValidator(region: .us).validate(input) == .incomplete)
    }

    // Full length but cannot resolve against the region: a leading 1 is read as
    // the country code so the remainder is too short, and over-length input
    // can't fit. These earn the red error.
    @Test("Reports invalid for full-length numbers that cannot resolve", arguments: [
        "1234567890",       // leading 1 → country code → remainder too short
        "415555010099",     // too many digits
    ])
    func validate_invalid(input: String) {
        #expect(PhoneValidator(region: .us).validate(input) == .invalid)
    }

    // Client validation is deliberately lenient: a plausible, full-length
    // number proceeds and the server is the authority on deliverability. That
    // is what lets a real number advance without a false error — even one with
    // an unusual exchange the numbering plan would technically reject.
    @Test("Accepts a plausible full-length number rather than false-rejecting it", arguments: [
        "4151234567",
        "2120112345",
    ])
    func validate_lenient(input: String) {
        #expect(PhoneValidator(region: .us).validate(input) != .invalid)
    }

    // Validation honours the selected flag: a bare national number is valid
    // only against its own country, while an international-format number
    // carries its own country code and wins over the flag.
    @Test("Validates against the selected region")
    func validate_respectsRegion() {
        #expect(PhoneValidator(region: .us).validate("4155550100") == .valid(Phone("4155550100", defaultRegion: .us)!))
        #expect(PhoneValidator(region: .gb).validate("7400123456") == .valid(Phone("7400123456", defaultRegion: .gb)!))
        #expect(PhoneValidator(region: .us).validate("+44 7400 123456") == .valid(Phone("+44 7400 123456", defaultRegion: .us)!))
    }

    // Autofill / QuickType drops in the whole number at once, sometimes with
    // the country code included. Every form must read as valid and proceed
    // with no error — the Apple-review path.
    @Test("Accepts a full autofilled number in every form", arguments: [
        "6138096933",     // national only
        "16138096933",    // with the leading country digit
        "+16138096933",   // full E.164
    ])
    func validate_autofill(input: String) {
        guard case .valid(let phone)? = PhoneValidator(region: .ca).validate(input) else {
            Issue.record("expected .valid for \(input)")
            return
        }
        #expect(phone.e164 == "+16138096933")
    }

    // End-to-end guard: the screen's binding strips non-digits, prepends the
    // selected country code, and formats before anything is validated. An
    // autofilled full number must survive that round-trip and still proceed.
    @Test("A full number survives the screen's prepend-and-format binding", arguments: [
        "+16138096933",     // QuickType full E.164
        "6138096933",       // national
        "(613) 809-6933",   // pre-formatted
    ])
    func binding_autofill_proceeds(autofillText: String) {
        let entered = PhoneFormatter().format("+1\(autofillText.filter(\.isNumber))")
        guard case .valid(let phone)? = PhoneValidator(region: .ca).validate(entered) else {
            Issue.record("expected .valid for autofill \(autofillText) → entered \(entered)")
            return
        }
        #expect(phone.e164 == "+16138096933")
    }
}
