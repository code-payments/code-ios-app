//
//  FlipClient+Poll.swift
//  FlipcashCore
//

import Foundation

extension FlipClient {

    /// Opens a poll in a group chat. `idempotencyKey` must be minted where the user's intent to
    /// create the poll begins; a retry of the same intent reuses it.
    public func createPoll(owner: KeyPair, conversationID: ConversationID, definition: PollDefinition, idempotencyKey: UUID) async throws -> Poll {
        try await withCheckedThrowingContinuation { c in
            pollService.createPoll(owner: owner, conversationID: conversationID, definition: definition, idempotencyKey: idempotencyKey) { c.resume(with: $0) }
        }
    }

    public func getPoll(owner: KeyPair, pollID: PollID) async throws -> Poll {
        try await withCheckedThrowingContinuation { c in
            pollService.getPoll(owner: owner, pollID: pollID) { c.resume(with: $0) }
        }
    }

    public func getPolls(owner: KeyPair, pollIDs: [PollID]) async throws -> [Poll] {
        try await withCheckedThrowingContinuation { c in
            pollService.getPolls(owner: owner, pollIDs: pollIDs) { c.resume(with: $0) }
        }
    }

    /// Records the viewer's selection, replacing any earlier one, and returns the updated state.
    public func vote(owner: KeyPair, pollID: PollID, optionIndices: [Int]) async throws -> PollState {
        try await withCheckedThrowingContinuation { c in
            pollService.vote(owner: owner, pollID: pollID, optionIndices: optionIndices) { c.resume(with: $0) }
        }
    }
}
