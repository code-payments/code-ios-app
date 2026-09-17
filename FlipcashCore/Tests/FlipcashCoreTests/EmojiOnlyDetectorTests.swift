//
//  EmojiOnlyDetectorTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
@testable import FlipcashCore

@Suite("EmojiOnlyDetector")
struct EmojiOnlyDetectorTests {

    @Test("One, two and three emoji qualify")
    func upToThreeQualify() {
        #expect(EmojiOnlyDetector.isEmojiOnly("👍"))
        #expect(EmojiOnlyDetector.isEmojiOnly("👍😀"))
        #expect(EmojiOnlyDetector.isEmojiOnly("👍😀🎉"))
    }

    @Test("A fourth emoji disqualifies")
    func fourIsTooMany() {
        #expect(!EmojiOnlyDetector.isEmojiOnly("👍😀🎉🔥"))
    }

    @Test("Whitespace around and between emoji is ignored")
    func whitespaceIsIgnored() {
        #expect(EmojiOnlyDetector.isEmojiOnly(" 👍 👍 \n"))
    }

    @Test("Emoji mixed with text does not qualify")
    func emojiPlusTextFails() {
        #expect(!EmojiOnlyDetector.isEmojiOnly("👍 nice"))
        #expect(!EmojiOnlyDetector.isEmojiOnly("nice 👍"))
    }

    @Test("Composed sequences count as one emoji each")
    func composedSequencesQualify() {
        #expect(EmojiOnlyDetector.isEmojiOnly("👨‍👩‍👧‍👦"))   // ZWJ family
        #expect(EmojiOnlyDetector.isEmojiOnly("👍🏽"))          // skin-tone modifier
        #expect(EmojiOnlyDetector.isEmojiOnly("🇺🇸"))          // regional-indicator flag
        #expect(EmojiOnlyDetector.isEmojiOnly("#️⃣"))          // keycap
        #expect(EmojiOnlyDetector.isEmojiOnly("👨‍👩‍👧‍👦👍🏽🇺🇸"))   // three of them together
    }

    @Test("Characters that carry the emoji property but render as text do not qualify")
    func emojiPropertyAloneIsNotEnough() {
        #expect(!EmojiOnlyDetector.isEmojiOnly("1"))
        #expect(!EmojiOnlyDetector.isEmojiOnly("#"))
        #expect(!EmojiOnlyDetector.isEmojiOnly("*"))
        #expect(!EmojiOnlyDetector.isEmojiOnly("e\u{0301}"))  // letter + combining mark
    }

    @Test("Empty and whitespace-only bodies do not qualify")
    func emptyDoesNotQualify() {
        #expect(!EmojiOnlyDetector.isEmojiOnly(""))
        #expect(!EmojiOnlyDetector.isEmojiOnly("   \n "))
    }

    @Test("The limit is a parameter")
    func limitIsConfigurable() {
        #expect(EmojiOnlyDetector.isEmojiOnly("👍😀🎉🔥", limit: 4))
        #expect(!EmojiOnlyDetector.isEmojiOnly("👍😀", limit: 1))
    }
}
