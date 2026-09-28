import Foundation
import Testing
@testable import FlipcashCore

/// Downscale half of `test-vectors/chat_media.json`. The canonical copy lives in the
/// orchestrator repo; this one is synced. A failure here is either a real regression or a
/// deliberate cross-platform decision that has to be made in the canonical fixture and
/// re-synced to both platforms — never a local edit.
@Suite struct ChatMediaDownscaleVectorTests {

    struct Vector: Decodable, Sendable, CustomTestStringConvertible {
        struct Expected: Decodable, Sendable { let width: Int; let height: Int }
        let name: String
        let sourceWidth: Int
        let sourceHeight: Int
        let maxWidth: Int
        let maxHeight: Int
        let maxPixels: Int
        let expected: Expected
        let note: String

        var testDescription: String { name }
    }

    struct Fixture: Decodable {
        let downscale: [Vector]
    }

    /// Loaded when the suite is built, so each vector runs, and fails, as its own case. A fixture
    /// that is missing or doesn't decode fails `fixtureLoads` instead of every vector at once.
    static let vectors: [Vector] = (try? loadFixture().downscale) ?? []

    private static func loadFixture() throws -> Fixture {
        let url = try #require(
            Bundle.module.url(forResource: "chat_media", withExtension: "json", subdirectory: "Fixtures")
        )
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    @Test func fixtureLoads() throws {
        #expect(try !Self.loadFixture().downscale.isEmpty)
    }

    @Test(arguments: vectors)
    func targetMatchesTheCrossPlatformVector(_ vector: Vector) {
        let result = ChatMediaDownscale.target(
            sourceWidth: vector.sourceWidth,
            sourceHeight: vector.sourceHeight,
            maxWidth: vector.maxWidth,
            maxHeight: vector.maxHeight,
            maxPixels: vector.maxPixels
        )
        #expect(result.width == vector.expected.width, "\(vector.note)")
        #expect(result.height == vector.expected.height, "\(vector.note)")
    }
}
