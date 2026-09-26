import Foundation
import Testing
@testable import FlipcashCore

/// Order section of `test-vectors/reactions.json`: boost total, then count, then UTF-8 bytes.
@Suite struct ReactionOrderVectorTests {

    @Test func orderMatchesTheCrossPlatformVectors() throws {
        let fixture = try loadReactionFixture()
        #expect(!fixture.order.isEmpty)

        for vector in fixture.order {
            let pills = vector.pills.map {
                ReactionPill(
                    emoji: $0.emoji,
                    count: $0.count,
                    selfReacted: false,
                    pending: false,
                    boost: $0.boostTotal > 0 ? ReactionBoost(total: $0.boostTotal) : nil
                )
            }
            let actual = ReactionOrdering.sorted(pills).map(\.emoji)
            #expect(actual == vector.expect, "vector `\(vector.name)`: \(vector.note)")
        }
    }
}
