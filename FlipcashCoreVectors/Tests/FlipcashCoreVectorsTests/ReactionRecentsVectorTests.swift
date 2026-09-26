import Foundation
import Testing
@testable import FlipcashCore

/// Recents section of `test-vectors/reactions.json`: ranking by use, padding with the defaults, and
/// dropping emoji this device cannot draw.
@Suite struct ReactionRecentsVectorTests {

    @Test func defaultsMatchTheCrossPlatformVectors() throws {
        #expect(try loadReactionFixture().defaults == RecentReactions.defaults)
    }

    @Test func rankMatchesTheCrossPlatformVectors() throws {
        let fixture = try loadReactionFixture()
        #expect(!fixture.recents.isEmpty)

        for vector in fixture.recents {
            var stats: [String: RecentReactions.Usage] = [:]
            for use in vector.uses {
                RecentReactions.record(use.emoji, at: Date(timeIntervalSince1970: use.usedAt), in: &stats)
            }
            let actual = RecentReactions.rank(stats: stats, undrawable: Set(vector.undrawable), limit: vector.limit)
            #expect(actual == vector.expect, "vector `\(vector.name)`: \(vector.note)")
        }
    }
}
