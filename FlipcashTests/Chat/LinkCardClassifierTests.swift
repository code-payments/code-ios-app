import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

/// Card half of `test-vectors/link_detection.json`. Synced copy — a failure is fixed in the
/// canonical fixture and re-synced to both platforms, never edited here.
@Suite struct LinkCardClassifierTests {

    private final class BundleToken {}

    struct Vector: Decodable {
        struct Span: Decodable { let start: Int; let end: Int; let url: String }
        struct Card: Decodable { let kind: String; let url: String }
        let name: String
        let spans: [Span]
        let card: Card?
        let note: String
    }

    struct Fixture: Decodable {
        let cardHosts: [String]
        let vectors: [Vector]
    }

    private func loadFixture() throws -> Fixture {
        let bundle = Bundle(for: BundleToken.self)
        let url = try #require(bundle.url(forResource: "link_detection", withExtension: "json"))
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    @Test func cardEligibilityMatchesTheCrossPlatformVectors() throws {
        let classifier = LinkCardClassifier()

        for vector in try loadFixture().vectors {
            let links = vector.spans.compactMap { span in
                URL(string: span.url).map {
                    DetectedLink(range: NSRange(location: span.start, length: span.end - span.start), url: $0)
                }
            }
            let actual = classifier.firstCard(in: links)

            guard let expected = vector.card else {
                #expect(actual == nil, "vector `\(vector.name)`: \(vector.note)")
                continue
            }

            // Phase 1 is cash links only. The token vector is canonical's commitment that both
            // platforms draw that link as a card eventually, and iOS does not yet — so the gap is
            // recorded here rather than hidden by holding the fixture back. `withKnownIssue` closes
            // itself: the day the classifier returns a token card this fails, and this branch goes.
            guard expected.kind == "cash" else {
                withKnownIssue("iOS has no \(expected.kind) card yet: vector `\(vector.name)`") {
                    #expect(actual != nil)
                }
                continue
            }
            guard case .cash(let cash)? = actual else {
                Issue.record("vector `\(vector.name)` produced no cash card: \(vector.note)")
                continue
            }
            #expect(cash.url.absoluteString == expected.url, "vector `\(vector.name)`: \(vector.note)")
            #expect(cash.state == .unresolved, "vector `\(vector.name)` must start unresolved")
            // The card carries the span it was built from, which is what the bubble cuts out of the
            // body. For a jump link that span is the wrapper, not `cash.url`, so it is matched
            // against the detected spans rather than against the card's own target.
            #expect(
                links.contains { $0.range == cash.range },
                "vector `\(vector.name)` card range \(cash.range) is not one of its detected spans"
            )
        }
    }

    /// Not in the canonical fixture, which wraps only an allowlisted host. Android's classifier
    /// unwraps before the host gate for exactly this case; a gate on the wrapper alone lets the
    /// wrapper choose the host behind it, and `Route` classifies the target by path alone.
    @Test func aJumpWrapperCannotSmuggleAHostPastTheAllowlist() throws {
        let inner = "https://send.flipcash.com.evil.com/c/#/e=KNi8pQr1n5hRU65vKJGge3"
        let wrapper = "https://jump.flipcash.com/#source=" + inner.addingPercentEncoding(
            withAllowedCharacters: .alphanumerics
        )!
        let url = try #require(URL(string: wrapper))
        let link = DetectedLink(range: NSRange(location: 0, length: (wrapper as NSString).length), url: url)

        #expect(LinkCardClassifier().firstCard(in: [link]) == nil)
    }

    @Test func theHostAllowlistMatchesTheCrossPlatformFixture() throws {
        #expect(Set(try loadFixture().cardHosts) == LinkCardClassifier.cardHosts)
    }
}
