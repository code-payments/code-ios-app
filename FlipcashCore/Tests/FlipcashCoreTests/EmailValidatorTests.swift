import Foundation
import Testing
@testable import FlipcashCore

@Suite("EmailValidator")
struct EmailValidatorTests {

    @Test("Accepts ASCII addresses matching the proto regex", arguments: [
        "test@example.com",
        "first.last@example.com",
        "tag+sub@example.co",
        "a_b@example.com",
        "name%percent@example.io",
        "mixed-CASE@Example.COM",
    ])
    func accepts_validEmail(input: String) {
        let validator = EmailValidator()
        #expect(validator.validate(input) == input)
    }

    @Test("Trims surrounding whitespace before validating and returning")
    func trims_whitespace() {
        let validator = EmailValidator()
        #expect(validator.validate("  test@example.com\n") == "test@example.com")
    }

    @Test("Rejects inputs the server's proto regex rejects", arguments: [
        "",                       // empty
        "   ",                    // whitespace only
        "no-at-symbol",           // missing @
        "missing@tld",            // no dot
        "missing@.com",           // empty domain label
        "trailing@dot.",          // empty TLD
        "short@bar.x",            // single-letter TLD
        "numeric@bar.123",        // digits in TLD
        "underscore@my_org.com",  // underscore in domain (server disallows)
        "unicode@café.com",       // non-ASCII domain
        "föö@example.com",        // non-ASCII local
        "spaces in@local.com",    // internal whitespace
    ])
    func rejects_invalidEmail(input: String) {
        let validator = EmailValidator()
        #expect(validator.validate(input) == nil)
    }

    @Test("Rejects oversized inputs even when the regex would match")
    func rejects_overlong() {
        let local = String(repeating: "a", count: 250)
        let input = "\(local)@example.com"
        #expect(input.utf8.count > 254)

        let validator = EmailValidator()
        #expect(validator.validate(input) == nil)
    }
}
