//
//  UsernameValidatorTests.swift
//  FlipcashCoreTests
//

import Testing
@testable import FlipcashCore

@Suite("UsernameValidator")
struct UsernameValidatorTests {

    private let validator = UsernameValidator()

    @Test("Uppercase input is accepted as its lowercase handle")
    func validate_uppercase_lowercases() {
        #expect(validator.validate("Taylor")?.value == "taylor")
    }

    @Test("Surrounding whitespace is trimmed rather than rejected")
    func validate_surroundingWhitespace_trimmed() {
        #expect(validator.validate("  taylor ")?.value == "taylor")
    }

    @Test("Two characters is the shortest accepted handle")
    func validate_minimumLength_boundary() {
        #expect(validator.validate("ab")?.value == "ab")
        #expect(validator.validate("a") == nil)
    }

    @Test("Fifteen characters is the longest accepted handle")
    func validate_maximumLength_boundary() {
        #expect(validator.validate("abcdefghijklmno")?.value == "abcdefghijklmno")
        #expect(validator.validate("abcdefghijklmnop") == nil)
    }

    @Test("Digits and underscores are legal, other characters are not")
    func validate_characterSet() {
        #expect(validator.validate("a_9")?.value == "a_9")
        #expect(validator.validate("a-9") == nil)
        #expect(validator.validate("a 9") == nil)
        #expect(validator.validate("año") == nil)
    }

    @Test("A one-character input reports too short")
    func failure_oneCharacter_tooShort() {
        #expect(validator.failure(for: "a") == .tooShort)
    }

    @Test("A sixteen-character input reports too long")
    func failure_sixteenCharacters_tooLong() {
        #expect(validator.failure(for: "abcdefghijklmnop") == .tooLong)
    }

    @Test("Length is reported ahead of the character set")
    func failure_tooLongWithIllegalCharacter_reportsLength() {
        #expect(validator.failure(for: "abcdefghijklmno!") == .tooLong)
    }

    @Test("A legal length with an illegal character reports the character set")
    func failure_illegalCharacter_invalidCharacters() {
        #expect(validator.failure(for: "tay-lor") == .invalidCharacters)
    }

    @Test("A valid handle has no failure")
    func failure_validHandle_none() {
        #expect(validator.failure(for: "Taylor") == nil)
    }

    @Test("The minimum length agrees with what Username itself accepts")
    func minimumLength_matchesUsername_boundary() {
        let atMinimum = String(repeating: "a", count: UsernameValidator.minimumLength)
        let belowMinimum = String(repeating: "a", count: UsernameValidator.minimumLength - 1)

        #expect(Username(atMinimum) != nil)
        #expect(Username(belowMinimum) == nil)
    }

    @Test("The maximum length agrees with what Username itself accepts")
    func maximumLength_matchesUsername_boundary() {
        let atMaximum = String(repeating: "a", count: UsernameValidator.maximumLength)
        let aboveMaximum = String(repeating: "a", count: UsernameValidator.maximumLength + 1)

        #expect(Username(atMaximum) != nil)
        #expect(Username(aboveMaximum) == nil)
    }

    @Test("An empty field is too short, not invalid")
    func failure_emptyString_tooShort() {
        #expect(UsernameValidator().failure(for: "") == .tooShort)
        #expect(UsernameValidator().validate("") == nil)
    }

    @Test("A short input reports its length, not its illegal character")
    func failure_tooShortWithIllegalCharacter_reportsLength() {
        #expect(UsernameValidator().failure(for: "!") == .tooShort)
    }

    @Test("Length counts what the user sees, so combining marks read as one character")
    func failure_combiningMarks_countedAsOneCharacter() {
        // 17 Unicode scalars, one grapheme cluster. Length is measured the way
        // the field displays it, so this is short rather than over-long.
        let accented = "a" + String(repeating: "\u{0301}", count: 16)

        #expect(UsernameValidator().failure(for: accented) == .tooShort)
    }
}
