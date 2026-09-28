import Testing
import Foundation
@testable import FlipcashCore

@Suite("MentionDetector @handle detection")
struct MentionDetectorTests {

    private func handles(_ text: String, links: [DetectedLink] = []) -> [String] {
        MentionDetector.mentions(in: text, excluding: links).map(\.username.value)
    }

    @Test("A handle at the start of the text is a mention")
    func leadingHandle() {
        let mentions = MentionDetector.mentions(in: "@jeff hi", excluding: [])
        #expect(mentions.map(\.username.value) == ["jeff"])
        #expect(mentions.first?.range == NSRange(location: 0, length: 5))
    }

    @Test("The range covers the @ and the handle, not the character before it")
    func midSentenceRange() {
        let mentions = MentionDetector.mentions(in: "ask @jeff.", excluding: [])
        #expect(mentions.first?.range == NSRange(location: 4, length: 5))
    }

    @Test("Uppercase letters fold to the stored lowercase handle")
    func uppercaseFolds() {
        #expect(handles("hey @Jeff_99") == ["jeff_99"])
    }

    @Test("Every handle in a message is found, in order")
    func several() {
        #expect(handles("@ab and @cd,@ef") == ["ab", "cd", "ef"])
    }

    @Test("Trailing punctuation ends the handle")
    func trailingPunctuation() {
        #expect(handles("thanks @jeff!") == ["jeff"])
        #expect(handles("(@jeff)") == ["jeff"])
    }

    @Test("An email address is not a mention")
    func email() {
        #expect(handles("write me@example.com") == [])
    }

    @Test("A doubled @ is not a mention")
    func doubledAt() {
        #expect(handles("@@jeff") == [])
        #expect(handles("@jeff@") == [])
    }

    @Test("Handles outside 2–15 characters are not mentions")
    func lengthBounds() {
        #expect(handles("@a") == [])
        #expect(handles("@abcdefghijklmnop") == [])
        #expect(handles("@abcdefghijklmno") == ["abcdefghijklmno"])
    }

    @Test("Characters a handle cannot hold end it rather than extend it")
    func invalidCharacters() {
        #expect(handles("@jeff-smith") == ["jeff"])
        #expect(handles("@je.ff") == ["je"])
    }

    @Test("A handle inside a web link is left to the link")
    func insideLink() {
        let text = "see x.com/@jeff"
        let links = LinkDetector().webLinks(in: text)
        #expect(!links.isEmpty)
        #expect(handles(text, links: links) == [])
    }

    @Test("A handle beside a web link is still a mention")
    func besideLink() {
        let text = "@jeff https://apple.com"
        let links = LinkDetector().webLinks(in: text)
        #expect(handles(text, links: links) == ["jeff"])
    }

    @Test("Ranges are UTF-16 offsets, past an emoji")
    func utf16Offsets() {
        let mentions = MentionDetector.mentions(in: "🎉 @jeff", excluding: [])
        #expect(mentions.first?.range == NSRange(location: 3, length: 5))
    }

    @Test("Plain text has no mentions")
    func plainText() {
        #expect(handles("no handles here") == [])
        #expect(handles("just an @ sign") == [])
    }
}
