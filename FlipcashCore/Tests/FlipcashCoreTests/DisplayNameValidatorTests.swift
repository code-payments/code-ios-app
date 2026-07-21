//
//  DisplayNameValidatorTests.swift
//  FlipcashCoreTests
//

import Testing
import FlipcashCore

@Suite("Display name validation")
struct DisplayNameValidatorTests {

    private let validator = DisplayNameValidator()

    @Test("Accepts names within the scalar limit",
          arguments: [
              "A",
              "Ted Livingston",
              "Ra\u{00FA}l Riera",
              "\u{5C71}\u{7530}\u{592A}\u{90CE}",
              "\u{1F389}",
              String(repeating: "A", count: 64),
          ])
    func acceptsValidNames(_ input: String) {
        #expect(validator.validate(input) == input)
    }

    @Test("Rejects empty, whitespace-only, and over-limit names",
          arguments: [
              "",
              "   ",
              "\n\t",
              String(repeating: "A", count: 65),
          ])
    func rejectsInvalidNames(_ input: String) {
        #expect(validator.validate(input) == nil)
    }

    @Test("Trims surrounding whitespace rather than rejecting it",
          arguments: [
              (input: "  Ted Livingston  ", expected: "Ted Livingston"),
              (input: "\nTed\n",            expected: "Ted"),
              (input: "Ted Livingston",     expected: "Ted Livingston"),
          ] as [(input: String, expected: String)])
    func trimsWhitespace(input: String, expected: String) {
        #expect(validator.validate(input) == expected)
    }

    /// A grapheme-based limit would accept names the server rejects: one ZWJ
    /// family emoji is a single grapheme but five scalars.
    @Test("Counts Unicode scalars, not grapheme clusters")
    func countsScalarsNotGraphemes() {
        let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}"
        #expect(family.count == 1)
        #expect(family.unicodeScalars.count == 5)

        let thirteen = String(repeating: family, count: 13)
        #expect(thirteen.count <= DisplayNameValidator.maxScalars)
        #expect(thirteen.unicodeScalars.count == 65)
        #expect(validator.validate(thirteen) == nil)

        let twelve = String(repeating: family, count: 12)
        #expect(twelve.unicodeScalars.count == 60)
        #expect(validator.validate(twelve) == twelve)
    }

    @Test("A combining mark spends its own scalar")
    func combiningMarksCount() {
        let decomposed = "e\u{0301}"
        #expect(decomposed.count == 1)
        #expect(decomposed.unicodeScalars.count == 2)

        #expect(validator.validate(String(repeating: decomposed, count: 32)) != nil)
        #expect(validator.validate(String(repeating: decomposed, count: 33)) == nil)
    }

    @Test("Remaining agrees with validity at the boundary")
    func remainingAgreesWithValidity() {
        let atLimit = String(repeating: "A", count: 64)
        #expect(validator.remaining(in: atLimit) == 0)
        #expect(validator.validate(atLimit) != nil)

        let overLimit = String(repeating: "A", count: 65)
        #expect(validator.remaining(in: overLimit) == -1)
        #expect(validator.validate(overLimit) == nil)
    }

    @Test("Remaining counts the trimmed name, which is what gets submitted")
    func remainingIgnoresSurroundingWhitespace() {
        #expect(validator.remaining(in: "  Ted  ") == DisplayNameValidator.maxScalars - 3)
    }
}
