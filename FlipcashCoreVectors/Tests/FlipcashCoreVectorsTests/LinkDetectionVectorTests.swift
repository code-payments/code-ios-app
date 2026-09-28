import Foundation
import Testing
@testable import FlipcashCore

/// Detection half of `test-vectors/link_detection.json`. The canonical copy lives in the
/// orchestrator repo; this one is synced. A failure here is either a real regression or a
/// deliberate cross-platform decision that has to be made in the canonical fixture and
/// re-synced to both platforms — never a local edit.
@Suite struct LinkDetectionVectorTests {

    struct Vector: Decodable, Sendable, CustomTestStringConvertible {
        struct Span: Decodable, Equatable, Sendable {
            let start: Int
            let end: Int
            let url: String
        }
        let name: String
        let text: String
        let spans: [Span]
        let note: String

        var testDescription: String { name }
    }

    struct Fixture: Decodable {
        let vectors: [Vector]
    }

    /// Loaded when the suite is built, so each vector runs, and fails, as its own case. A fixture
    /// that is missing or doesn't decode fails `fixtureLoads` instead of every vector at once.
    static let vectors: [Vector] = (try? loadFixture().vectors) ?? []

    private static func loadFixture() throws -> Fixture {
        let url = try #require(
            Bundle.module.url(forResource: "link_detection", withExtension: "json", subdirectory: "Fixtures")
        )
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    @Test func fixtureLoads() throws {
        #expect(try !Self.loadFixture().vectors.isEmpty)
    }

    @Test(arguments: vectors)
    func spansMatchTheCrossPlatformVector(_ vector: Vector) {
        let actual = LinkDetector().webLinks(in: vector.text).map {
            Vector.Span(
                start: $0.range.location,
                end: $0.range.location + $0.range.length,
                url: $0.url.absoluteString
            )
        }
        #expect(actual == vector.spans, "\(vector.note)")
    }
}
