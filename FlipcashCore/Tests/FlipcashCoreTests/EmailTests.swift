import Foundation
import Testing
@testable import FlipcashCore

@Suite("Email value type")
struct EmailTests {

    @Test("Accepts ASCII addresses matching the proto regex", arguments: [
        "test@example.com",
        "first.last@example.com",
        "tag+sub@example.co",
        "a_b@example.com",
        "name%percent@example.io",
        "mixed-CASE@Example.COM",
    ])
    func accepts_validEmail(input: String) {
        let email = Email(input)
        #expect(email != nil)
        #expect(email?.value == input)
    }

    @Test("Trims surrounding whitespace before validating and submitting")
    func trims_whitespace() {
        let email = Email("  test@example.com\n")
        #expect(email?.value == "test@example.com")
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
        #expect(Email(input) == nil)
    }

    @Test("Rejects oversized inputs even when the regex would match")
    func rejects_overlong() {
        let local = String(repeating: "a", count: 250)
        let email = "\(local)@example.com"
        #expect(email.utf8.count > 254)
        #expect(Email(email) == nil)
    }
}
