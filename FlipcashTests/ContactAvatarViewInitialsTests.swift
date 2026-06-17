//
//  ContactAvatarViewInitialsTests.swift
//  FlipcashTests
//

import Testing
import FlipcashUI

@Suite("ContactAvatarView.monogram(for:)")
struct ContactAvatarViewInitialsTests {

    @Test("Two-word name yields first letter of first + last word")
    func twoWords() {
        #expect(ContactAvatarView.monogram(for: "Jane Doe") == .initials("JD"))
    }

    @Test("Three-word name still takes first and LAST word")
    func threeWords() {
        #expect(ContactAvatarView.monogram(for: "Mary Jane Doe") == .initials("MD"))
    }

    @Test("Single-word name yields first two letters")
    func singleWord() {
        #expect(ContactAvatarView.monogram(for: "Madonna") == .initials("MA"))
    }

    @Test("Single short word yields just that character")
    func singleLetter() {
        #expect(ContactAvatarView.monogram(for: "A") == .initials("A"))
    }

    @Test("Lowercase input is uppercased")
    func lowercased() {
        #expect(ContactAvatarView.monogram(for: "jane doe") == .initials("JD"))
    }

    @Test("Empty string yields a placeholder")
    func empty() {
        #expect(ContactAvatarView.monogram(for: "") == .placeholder)
    }

    @Test("Whitespace-only yields a placeholder")
    func whitespaceOnly() {
        #expect(ContactAvatarView.monogram(for: "   \n  ") == .placeholder)
    }

    @Test("Leading/trailing whitespace is trimmed before split")
    func surroundingWhitespace() {
        #expect(ContactAvatarView.monogram(for: "  Jane Doe  ") == .initials("JD"))
    }

    @Test("Repeated inner whitespace collapses")
    func collapsedWhitespace() {
        #expect(ContactAvatarView.monogram(for: "Jane   Doe") == .initials("JD"))
    }

    @Test("A phone number has no letters, so it yields a placeholder")
    func phoneNumber() {
        #expect(ContactAvatarView.monogram(for: "(586) 980-2333") == .placeholder)
    }

    @Test("Non-letter words are ignored when forming initials")
    func nonLetterWordsIgnored() {
        #expect(ContactAvatarView.monogram(for: "John (work)") == .initials("JO"))
    }
}
