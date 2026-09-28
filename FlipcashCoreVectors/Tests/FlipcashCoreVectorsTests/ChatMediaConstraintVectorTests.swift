import Foundation
import Testing
@testable import FlipcashCore

/// Constraint-selection half of `test-vectors/chat_media.json`. The canonical copy lives in the
/// orchestrator repo; this one is synced. A failure here is either a real regression or a
/// deliberate cross-platform decision that has to be made in the canonical fixture and
/// re-synced to both platforms — never a local edit.
@Suite struct ChatMediaConstraintVectorTests {

    struct Vector: Decodable, Sendable, CustomTestStringConvertible {
        let name: String
        let patterns: [String]
        let mimeType: String
        let expectedIndex: Int?
        let note: String

        var testDescription: String { name }
    }

    struct Fixture: Decodable {
        let constraintSelection: [Vector]
    }

    /// Loaded when the suite is built, so each vector runs, and fails, as its own case. A fixture
    /// that is missing or doesn't decode fails `fixtureLoads` instead of every vector at once.
    static let vectors: [Vector] = (try? loadFixture().constraintSelection) ?? []

    private static func loadFixture() throws -> Fixture {
        let url = try #require(
            Bundle.module.url(forResource: "chat_media", withExtension: "json", subdirectory: "Fixtures")
        )
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    @Test func fixtureLoads() throws {
        #expect(try !Self.loadFixture().constraintSelection.isEmpty)
    }

    @Test(arguments: vectors)
    func firstMatchIndexMatchesTheCrossPlatformVector(_ vector: Vector) {
        let result = ChatMediaConstraints.firstMatchIndex(patterns: vector.patterns, mimeType: vector.mimeType)
        #expect(result == vector.expectedIndex, "\(vector.note)")
    }
}
