import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

/// Card half of `test-vectors/link_detection.json`. Synced copy — a failure is fixed in the
/// canonical fixture and re-synced to both platforms, never edited here.
@Suite struct LinkCardClassifierTests {

    private final class BundleToken {}

    struct Vector: Decodable {
        struct Span: Decodable { let url: String }
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
            let urls = vector.spans.compactMap { URL(string: $0.url) }
            let actual = classifier.firstCard(in: urls)

            guard let expected = vector.card else {
                #expect(actual == nil, "vector `\(vector.name)`: \(vector.note)")
                continue
            }

            #expect(expected.kind == "cash", "vector `\(vector.name)` is not a cash case")
            guard case .cash(let cash)? = actual else {
                Issue.record("vector `\(vector.name)` produced no cash card: \(vector.note)")
                continue
            }
            #expect(cash.url.absoluteString == expected.url, "vector `\(vector.name)`: \(vector.note)")
            #expect(cash.state == .unresolved, "vector `\(vector.name)` must start unresolved")
        }
    }

    @Test func theHostAllowlistMatchesTheCrossPlatformFixture() throws {
        #expect(Set(try loadFixture().cardHosts) == LinkCardClassifier.cardHosts)
    }
}
