import Testing
import Foundation
@testable import FlipcashCore

@Suite("LinkDetector web link detection")
struct LinkDetectorTests {

    private let detector = LinkDetector()

    @Test("A bare https URL leaves an empty bubble text")
    func soleHTTPSURL() {
        let preview = detector.webLink(in: "https://apple.com")
        #expect(preview?.url.absoluteString == "https://apple.com")
        #expect(preview?.bubbleText == "")
    }

    @Test("A scheme-less domain is detected and leaves an empty bubble text")
    func schemelessDomain_isSole() {
        let preview = detector.webLink(in: "apple.com")
        #expect(preview?.url.scheme == "http")
        #expect(preview?.bubbleText == "")
    }

    @Test("Text around a URL keeps the text, minus the link, as bubble text")
    func textPlusURL_notSole() {
        let preview = detector.webLink(in: "look at this https://apple.com")
        #expect(preview?.url.absoluteString == "https://apple.com")
        #expect(preview?.bubbleText == "look at this")
    }

    @Test("The trailing URL is chosen when there are several; the leading one stays in the bubble text")
    func multipleURLs_picksTrailing() {
        let preview = detector.webLink(in: "https://a.com then https://b.com")
        #expect(preview?.url.absoluteString == "https://b.com")
        #expect(preview?.bubbleText == "https://a.com then")
    }

    @Test("Trailing punctuation is not part of the URL, but the punctuation after it keeps the bubble text intact")
    func trailingPunctuation_excluded() {
        let text = "see https://apple.com."
        let preview = detector.webLink(in: text)
        #expect(preview?.url.absoluteString == "https://apple.com")
        // NSDataDetector's match excludes the ".", so the character after the match isn't whitespace —
        // the match isn't trailing, so the bubble keeps the full original text.
        #expect(preview?.bubbleText == text)
    }

    @Test("A mid-sentence URL keeps the full text as bubble text; the URL stays visible inline")
    func midSentenceURL_keepsFullText() {
        let text = "prices went up 20% https://apple.com, check it"
        let preview = detector.webLink(in: text)
        #expect(preview?.url.absoluteString == "https://apple.com")
        #expect(preview?.bubbleText == text)
    }

    @Test("A leading URL followed by more text keeps the full text as bubble text")
    func leadingURLWithTrailingText_keepsFullText() {
        let text = "https://apple.com, thanks"
        let preview = detector.webLink(in: text)
        #expect(preview?.bubbleText == text)
    }

    @Test("Email addresses do not produce a web link")
    func email_noLink() {
        #expect(detector.webLink(in: "write me@example.com") == nil)
    }

    @Test("Custom schemes are ignored")
    func customScheme_ignored() {
        #expect(detector.webLink(in: "flipcash://pay/123") == nil)
    }

    @Test("Plain text has no link")
    func plainText_noLink() {
        #expect(detector.webLink(in: "hello there") == nil)
    }

    @Test("A URL mangled by a glued-on emoji is rejected outright")
    func nonASCIIMangledURL_rejected() {
        #expect(detector.webLink(in: "https://apple.com😀 nice right") == nil)
    }

    @Test("A mangled trailing URL is rejected, letting an earlier clean URL win — which then reads as not-trailing")
    func nonASCIIMangledTrailingURL_fallsBackToEarlierCleanMatch() {
        let text = "https://a.com then https://b.com😀"
        let preview = detector.webLink(in: text)
        #expect(preview?.url.absoluteString == "https://a.com")
        #expect(preview?.bubbleText == text)
    }

    @Test("A non-ASCII path keeps the URL — only a mangled host is rejected")
    func nonASCIIPath_isDetected() {
        let preview = detector.webLink(in: "https://en.wikipedia.org/wiki/Café")
        #expect(preview?.url.host() == "en.wikipedia.org")
    }
}
