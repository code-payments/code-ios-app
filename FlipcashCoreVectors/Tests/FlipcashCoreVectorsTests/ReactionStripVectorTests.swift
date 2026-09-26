import Foundation
import Testing
@testable import FlipcashCore

/// Strip section of `test-vectors/reactions.json`: recents in place, then the user's other
/// reactions newest first, every one of the user's reactions highlighted.
@Suite struct ReactionStripVectorTests {

    @Test func stripMatchesTheCrossPlatformVectors() throws {
        let fixture = try loadReactionFixture()
        #expect(!fixture.strip.isEmpty)

        for vector in fixture.strip {
            let actual = ReactionStrip.entries(
                recents: vector.recents,
                selfReactions: vector.selfReactions.map {
                    SelfReaction(emoji: $0.emoji, reactedAt: Date(timeIntervalSince1970: $0.reactedAt))
                }
            ).map { ReactionFixture.StripVector.Entry(emoji: $0.emoji, highlighted: $0.highlighted) }
            #expect(actual == vector.expect, "vector `\(vector.name)`: \(vector.note)")
        }
    }
}
