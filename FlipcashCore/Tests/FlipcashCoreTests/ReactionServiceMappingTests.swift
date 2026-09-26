//
//  ReactionServiceMappingTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
import FlipcashAPI
@testable import FlipcashCore

@Suite("Reaction RPC response mapping")
struct ReactionServiceMappingTests {

    private let selfID = UUID()

    private func reactionProto(emoji: String = "👍", count: UInt64 = 2, version: UInt64 = 7, selfReacted: Bool = true) -> Flipcash_Messaging_V1_EmojiReaction {
        .with {
            $0.emoji = .with { $0.value = emoji }
            $0.count = count
            $0.version = version
            if selfReacted {
                $0.selfReactor = .with {
                    $0.userID = .with { $0.value = selfID.data }
                    $0.reactedTs = .init(date: Date(timeIntervalSince1970: 100))
                    $0.version = version
                }
            }
        }
    }

    @Test("An OK add maps to the returned aggregate")
    func addOK() throws {
        let response = Flipcash_Messaging_V1_AddReactionResponse.with {
            $0.result = .ok
            $0.reaction = reactionProto()
        }
        let reaction = try ChatMessagingService.addReactionResult(response).get()
        #expect(reaction.emoji == "👍")
        #expect(reaction.count == 2)
        #expect(reaction.version == 7)
        #expect(reaction.selfReactor?.userID == selfID)
        #expect(reaction.result == .ok(count: 2, selfReacted: true, version: 7, selfReactedAt: Date(timeIntervalSince1970: 100)))
    }

    @Test("An OK add without a reaction is malformed")
    func addOKWithoutReaction() {
        let response = Flipcash_Messaging_V1_AddReactionResponse.with { $0.result = .ok }
        #expect(throws: ErrorAddReaction.unknown) { try ChatMessagingService.addReactionResult(response).get() }
    }

    @Test("Add failures map to their reaction failure", arguments: [
        (Flipcash_Messaging_V1_AddReactionResponse.Result.denied, ErrorAddReaction.denied, ReactionFailure.denied),
        (.messageNotFound, .messageNotFound, .messageNotFound),
        (.cannotReact, .cannotReact, .cannotReact),
        (.tooManyReactionTypes, .tooManyReactionTypes, .tooManyReactionTypes),
    ])
    func addFailures(result: Flipcash_Messaging_V1_AddReactionResponse.Result, error: ErrorAddReaction, failure: ReactionFailure) {
        let response = Flipcash_Messaging_V1_AddReactionResponse.with { $0.result = result }
        #expect(throws: error) { try ChatMessagingService.addReactionResult(response).get() }
        #expect(error.reactionFailure == failure)
    }

    @Test("Transport and unknown failures settle as a network failure")
    func transportIsNetwork() {
        #expect(ErrorAddReaction.transportFailure.reactionFailure == .network)
        #expect(ErrorAddReaction.unknown.reactionFailure == .network)
        #expect(ErrorRemoveReaction.transportFailure.reactionFailure == .network)
    }

    @Test("A remove with no self reactor maps to an unreacted aggregate")
    func removeOK() throws {
        let response = Flipcash_Messaging_V1_RemoveReactionResponse.with {
            $0.result = .ok
            $0.reaction = reactionProto(count: 1, version: 8, selfReacted: false)
        }
        let reaction = try ChatMessagingService.removeReactionResult(response).get()
        #expect(reaction.result == .ok(count: 1, selfReacted: false, version: 8, selfReactedAt: nil))
    }

    @Test("Remove failures map to their reaction failure")
    func removeFailures() {
        let denied = Flipcash_Messaging_V1_RemoveReactionResponse.with { $0.result = .denied }
        #expect(throws: ErrorRemoveReaction.denied) { try ChatMessagingService.removeReactionResult(denied).get() }
        let missing = Flipcash_Messaging_V1_RemoveReactionResponse.with { $0.result = .messageNotFound }
        #expect(throws: ErrorRemoveReaction.messageNotFound) { try ChatMessagingService.removeReactionResult(missing).get() }
        #expect(ErrorRemoveReaction.messageNotFound.reactionFailure == .messageNotFound)
    }

    @Test("A reactor page carries the next token only while more remain")
    func reactorsPaging() throws {
        let token = Data([1, 2, 3])
        let more = Flipcash_Messaging_V1_GetReactorsResponse.with {
            $0.result = .ok
            $0.reactors = [.with { $0.userID = .with { $0.value = selfID.data }; $0.version = 3 }]
            $0.pagingToken = .with { $0.value = token }
            $0.hasMore_p = true
            $0.version = 9
        }
        let page = try ChatMessagingService.reactorsResult(more).get()
        #expect(page.reactors == [Reactor(userID: selfID, reactedAt: nil, version: 3)])
        #expect(page.nextPageToken == token)
        #expect(page.version == 9)

        var last = more
        last.hasMore_p = false
        #expect(try ChatMessagingService.reactorsResult(last).get().nextPageToken == nil)
    }

    @Test("A reaction summary seeds the state")
    func summarySeedsState() {
        let summary = Flipcash_Messaging_V1_ReactionSummary.with {
            $0.reactions = [reactionProto(emoji: "🔥", count: 3, version: 2, selfReacted: false), reactionProto()]
        }
        let state = ReactionState(summary)
        #expect(state.pills.map(\.emoji) == ["🔥", "👍"])
        #expect(state.selfReactions.map(\.emoji) == ["👍"])
    }
}
