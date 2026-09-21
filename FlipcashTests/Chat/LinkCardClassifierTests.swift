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
        struct Card: Decodable { let kind: String; let url: String; let mint: String? }
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

            guard let card = actual else {
                Issue.record("vector `\(vector.name)` produced no \(expected.kind) card: \(vector.note)")
                continue
            }
            #expect(card.kindName == expected.kind, "vector `\(vector.name)`: \(vector.note)")
            #expect(card.url.absoluteString == expected.url, "vector `\(vector.name)`: \(vector.note)")
            // The card carries the span it was built from, which is what the bubble cuts out of the
            // body. For a jump link that span is the wrapper, not `card.url`, so it is matched
            // against the detected spans rather than against the card's own target.
            #expect(
                links.contains { $0.range == card.range },
                "vector `\(vector.name)` card range \(card.range) is not one of its detected spans"
            )
            // The mint is read out of the path rather than matched against the URL, so the fixture
            // states it separately and the classifier has to agree.
            if case .token(let token) = card {
                #expect(token.mint.base58 == expected.mint, "vector `\(vector.name)`: \(vector.note)")
            }
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
        #expect(Set(try loadFixture().cardHosts) == Route.flipcashHosts)
    }
}

/// The fixture names a card's kind as a string; this is the one place that string meets the enum.
private extension LinkCard {
    var kindName: String {
        switch self {
        case .cash: "cash"
        case .token: "token"
        }
    }
}
