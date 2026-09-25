import Foundation
import Testing
@testable import FlipcashCore

/// Drawability section of `test-vectors/reactions.json`: only emoji whose answer is the same on
/// every OS both apps support, so this runs on whatever simulator or host is available.
@Suite struct ReactionDrawabilityVectorTests {

    @Test func drawabilityMatchesTheCrossPlatformVectors() throws {
        let fixture = try loadReactionFixture()
        #expect(!fixture.drawability.isEmpty)

        for vector in fixture.drawability {
            #expect(
                EmojiDrawability.isDrawable(vector.emoji) == vector.drawable,
                "emoji \(vector.emoji): \(vector.note)"
            )
        }
    }
}
