import Foundation
import Testing
@testable import FlipcashCore

/// Merge section of `test-vectors/reactions.json`: a message's reactions through summaries, stream
/// updates, taps and call results, run through `ReactionState`.
@Suite struct ReactionMergeVectorTests {

    @Test func mergeMatchesTheCrossPlatformVectors() throws {
        let fixture = try loadReactionFixture()
        #expect(!fixture.merge.isEmpty)

        for vector in fixture.merge {
            var state = ReactionState()
            var calls: [ReactionCall] = []
            var errors: [ReactionError] = []
            let now = Date(timeIntervalSince1970: 0)

            for step in vector.steps {
                switch step {
                case .summary(let reactions):
                    state.applySummary(reactions.map {
                        ReactionState.SummaryEntry(
                            emoji: $0.emoji ?? "",
                            count: $0.count,
                            selfReacted: $0.isSelf,
                            version: $0.version,
                            selfReactedAt: nil
                        )
                    })
                case .update(let emoji, let actor, let action, let count, let version):
                    state.applyUpdate(
                        emoji: emoji,
                        actorIsSelf: actor == vector.selfID,
                        added: action == "ADDED",
                        count: count,
                        version: version,
                        reactedAt: nil
                    )
                case .tap(let emoji):
                    if let call = state.tap(emoji, at: now) { calls.append(call) }
                case .respond(let emoji, let result, let reaction):
                    let outcome = state.respond(emoji: emoji, result: try Self.result(result, reaction, vector.name))
                    if let call = outcome.call { calls.append(call) }
                    if let error = outcome.error { errors.append(error) }
                }
            }

            let pills = state.pills.map {
                ReactionFixture.Pill(emoji: $0.emoji, count: $0.count, selfReacted: $0.selfReacted, pending: $0.pending)
            }
            let callNames = calls.map { call -> ReactionFixture.Call in
                switch call.op {
                case .add: ReactionFixture.Call(op: "add", emoji: call.emoji)
                case .remove: ReactionFixture.Call(op: "remove", emoji: call.emoji)
                }
            }
            let errorNames = errors.map { error -> String in
                switch error {
                case .reactionFailed: "reactionFailed"
                case .tooManyReactionTypes: "tooManyReactionTypes"
                }
            }
            #expect(pills == vector.expect.pills, "vector `\(vector.name)` pills: \(vector.note)")
            #expect(callNames == vector.expect.calls, "vector `\(vector.name)` calls: \(vector.note)")
            #expect(errorNames == vector.expect.errors, "vector `\(vector.name)` errors: \(vector.note)")
        }
    }

    private static func result(_ name: String, _ reaction: ReactionFixture.Reaction?, _ vector: String) throws -> ReactionResult {
        switch name {
        case "OK":
            let reaction = try #require(reaction, "vector `\(vector)`: OK without a reaction")
            return .ok(count: reaction.count, selfReacted: reaction.isSelf, version: reaction.version, selfReactedAt: nil)
        case "NETWORK": return .failed(.network)
        case "DENIED": return .failed(.denied)
        case "MESSAGE_NOT_FOUND": return .failed(.messageNotFound)
        case "CANNOT_REACT": return .failed(.cannotReact)
        case "TOO_MANY_REACTION_TYPES": return .failed(.tooManyReactionTypes)
        default:
            Issue.record("vector `\(vector)`: unknown result \(name)")
            return .failed(.network)
        }
    }
}
