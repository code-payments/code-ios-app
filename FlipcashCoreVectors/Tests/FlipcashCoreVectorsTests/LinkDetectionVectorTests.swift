import Foundation
import Testing
@testable import FlipcashCore

/// Detection half of `test-vectors/link_detection.json`. The canonical copy lives in the
/// orchestrator repo; this one is synced. A failure here is either a real regression or a
/// deliberate cross-platform decision that has to be made in the canonical fixture and
/// re-synced to both platforms — never a local edit.
@Suite struct LinkDetectionVectorTests {

    struct Vector: Decodable {
        struct Span: Decodable, Equatable {
            let start: Int
            let end: Int
            let url: String
        }
        let name: String
        let text: String
        let spans: [Span]
        let note: String
    }

    struct Fixture: Decodable {
        let vectors: [Vector]
    }

    private func loadFixture() throws -> Fixture {
        let url = try #require(
            Bundle.module.url(forResource: "link_detection", withExtension: "json", subdirectory: "Fixtures")
        )
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    @Test func spansMatchTheCrossPlatformVectors() throws {
        let detector = LinkDetector()

        for vector in try loadFixture().vectors {
            let actual = detector.webLinks(in: vector.text).map {
                Vector.Span(
                    start: $0.range.location,
                    end: $0.range.location + $0.range.length,
                    url: $0.url.absoluteString
                )
            }
            #expect(actual == vector.spans, "vector `\(vector.name)`: \(vector.note)")
        }
    }
}
