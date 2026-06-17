//
//  ContactAvatarViewInitialsTests.swift
//  FlipcashTests
//

import Testing
import FlipcashUI

@Suite("ContactAvatarView.initials(for:)")
struct ContactAvatarViewInitialsTests {

    @Test("Two-word name yields first letter of first + last word")
    func twoWords() {
        #expect(ContactAvatarView.initials(for: "Jane Doe") == "JD")
    }

    @Test("Three-word name still takes first and LAST word")
    func threeWords() {
        #expect(ContactAvatarView.initials(for: "Mary Jane Doe") == "MD")
    }

    @Test("Single-word name yields first two letters")
    func singleWord() {
        #expect(ContactAvatarView.initials(for: "Madonna") == "MA")
    }

    @Test("Single short word yields just that character")
    func singleLetter() {
        #expect(ContactAvatarView.initials(for: "A") == "A")
    }

    @Test("Lowercase input is uppercased")
    func lowercased() {
        #expect(ContactAvatarView.initials(for: "jane doe") == "JD")
    }

    @Test("Empty string yields fallback")
    func empty() {
        #expect(ContactAvatarView.initials(for: "") == "?")
    }

    @Test("Whitespace-only yields fallback")
    func whitespaceOnly() {
        #expect(ContactAvatarView.initials(for: "   \n  ") == "?")
    }

    @Test("Leading/trailing whitespace is trimmed before split")
    func surroundingWhitespace() {
        #expect(ContactAvatarView.initials(for: "  Jane Doe  ") == "JD")
    }

    @Test("Repeated inner whitespace collapses")
    func collapsedWhitespace() {
        #expect(ContactAvatarView.initials(for: "Jane   Doe") == "JD")
    }
}
