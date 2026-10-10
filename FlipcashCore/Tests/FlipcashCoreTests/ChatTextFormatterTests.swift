import Testing
import Foundation
@testable import FlipcashCore

@Suite("ChatTextFormatter display text and link remapping")
struct ChatTextFormatterTests {

    @Test("Plain text is its own display and carries no format")
    func plainText() {
        let result = ChatTextFormatter.format(detecting: "hello there")
        #expect(result.display == "hello there")
        #expect(result.format == nil)
    }

    @Test("Bold markers come out of the display and become a span")
    func bold() {
        let result = ChatTextFormatter.format(detecting: "a *b* c")
        #expect(result.display == "a b c")
        #expect(result.format?.raw == "a *b* c")
        #expect(result.format?.spans == [ChatTextSpan(style: .bold, range: NSRange(location: 2, length: 1))])
    }

    @Test("displayText drops markers for one-line surfaces")
    func displayText() {
        #expect(ChatTextFormatter.displayText(of: "_hi_ ~there~") == "hi there")
    }

    @Test("A bare link keeps its URL and moves to its display offsets")
    func bareLinkMoves() throws {
        let result = ChatTextFormatter.format(detecting: "*hey* https://example.com")
        let link = try #require(result.preview?.links.first)
        #expect(result.display == "hey https://example.com")
        #expect(link.range == NSRange(location: 4, length: 19))
        #expect(link.url.absoluteString == "https://example.com")
        #expect(link.maskedLabel == nil)
    }

    @Test("A masked link becomes a link over its text, pointing at its target")
    func maskedLink() throws {
        let result = ChatTextFormatter.format(detecting: "[my site](https://example.com)")
        let link = try #require(result.preview?.links.first)
        #expect(result.display == "my site")
        #expect(link.range == NSRange(location: 0, length: 7))
        #expect(link.url.absoluteString == "https://example.com")
        #expect(link.maskedLabel == "my site")
        #expect(result.preview?.links.count == 1)
    }

    @Test("A mention moves to its display offsets")
    func mentionMoves() throws {
        let result = ChatTextFormatter.format(detecting: "*hi* @jeff")
        let mention = try #require(result.preview?.mentions.first)
        #expect(result.display == "hi @jeff")
        #expect(mention.range == NSRange(location: 3, length: 5))
        #expect(mention.username.value == "jeff")
    }

    @Test("The address inside a masked link is recognised as a mask target")
    func maskTarget() {
        let text = "[a](https://example.com)" as NSString
        #expect(ChatTextFormatter.isMaskTarget(NSRange(location: 4, length: 19), in: text))
        #expect(!ChatTextFormatter.isMaskTarget(NSRange(location: 0, length: 3), in: text))
    }
}
