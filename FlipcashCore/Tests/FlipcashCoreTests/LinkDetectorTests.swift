import Testing
import Foundation
@testable import FlipcashCore

@Suite("LinkDetector web link detection")
struct LinkDetectorTests {

    private let detector = LinkDetector()

    @Test("A bare https URL is detected")
    func soleHTTPSURL() {
        let preview = detector.webLink(in: "https://apple.com")
        #expect(preview?.url.absoluteString == "https://apple.com")
    }

    @Test("A scheme-less domain is detected")
    func schemelessDomain_isSole() {
        let preview = detector.webLink(in: "apple.com")
        #expect(preview?.url.scheme == "http")
    }

    @Test("A URL is detected alongside surrounding text")
    func textPlusURL_notSole() {
        let preview = detector.webLink(in: "look at this https://apple.com")
        #expect(preview?.url.absoluteString == "https://apple.com")
    }

    @Test("The trailing URL is chosen when there are several")
    func multipleURLs_picksTrailing() {
        let preview = detector.webLink(in: "https://a.com then https://b.com")
        #expect(preview?.url.absoluteString == "https://b.com")
    }

    @Test("Trailing punctuation is not part of the URL")
    func trailingPunctuation_excluded() {
        let preview = detector.webLink(in: "see https://apple.com.")
        #expect(preview?.url.absoluteString == "https://apple.com")
    }

    @Test("A mid-sentence URL is still detected")
    func midSentenceURL_keepsFullText() {
        let preview = detector.webLink(in: "prices went up 20% https://apple.com, check it")
        #expect(preview?.url.absoluteString == "https://apple.com")
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

    @Test("A mangled trailing URL is rejected, letting an earlier clean URL win")
    func nonASCIIMangledTrailingURL_fallsBackToEarlierCleanMatch() {
        let preview = detector.webLink(in: "https://a.com then https://b.com😀")
        #expect(preview?.url.absoluteString == "https://a.com")
    }

    @Test("A non-ASCII path keeps the URL — only a mangled host is rejected")
    func nonASCIIPath_isDetected() {
        let preview = detector.webLink(in: "https://en.wikipedia.org/wiki/Café")
        #expect(preview?.url.host() == "en.wikipedia.org")
    }
}
