//
//  PollServiceTests.swift
//  FlipcashCoreTests
//

import Foundation
import Testing
import FlipcashAPI
@testable import FlipcashCore

@Suite("Poll service error mapping and model decoding")
struct PollServiceTests {

    @Test("ErrorCreatePoll maps every result explicitly and carries the flagged category")
    func createPollResults() {
        #expect(ErrorCreatePoll(.denied, flaggedCategory: .nsfw) == .denied)
        #expect(ErrorCreatePoll(.chatNotSupported, flaggedCategory: .nsfw) == .chatNotSupported)
        #expect(ErrorCreatePoll(.encryptionNotAllowed, flaggedCategory: .nsfw) == .encryptionNotAllowed)
        #expect(ErrorCreatePoll(.encryptionRequired, flaggedCategory: .nsfw) == .encryptionRequired)
        #expect(ErrorCreatePoll(.optionCountMismatch, flaggedCategory: .nsfw) == .optionCountMismatch)
        #expect(ErrorCreatePoll(.invalidEndsAt, flaggedCategory: .nsfw) == .invalidEndsAt)
        #expect(ErrorCreatePoll(.invalidBalanceParameters, flaggedCategory: .nsfw) == .invalidBalanceParameters)
        #expect(ErrorCreatePoll(.textModerated, flaggedCategory: .nsfw) == .textModerated(.nsfw))
        #expect(ErrorCreatePoll(.textModerated, flaggedCategory: .nsfw).reportingLevel == .info)
        #expect(ErrorCreatePoll(.UNRECOGNIZED(99), flaggedCategory: .nsfw) == .unknown)
    }

    @Test("Positional rawValue mapping matches the proto result enums")
    func positionalResults() {
        #expect(ErrorGetPoll(rawValue: Flipcash_Poll_V1_GetPollResponse.Result.notFound.rawValue) == .notFound)
        #expect(ErrorGetPolls(rawValue: Flipcash_Poll_V1_GetPollsResponse.Result.denied.rawValue) == .denied)
        #expect(ErrorVote(rawValue: Flipcash_Poll_V1_VoteResponse.Result.notFound.rawValue) == .notFound)
        #expect(ErrorVote(rawValue: Flipcash_Poll_V1_VoteResponse.Result.pollClosed.rawValue) == .pollClosed)
        #expect(ErrorVote(rawValue: Flipcash_Poll_V1_VoteResponse.Result.invalidSelection.rawValue) == .invalidSelection)
    }

    @Test("A plaintext count poll round-trips through its domain model")
    func pollMapping() {
        let proto = Flipcash_Poll_V1_PollMetadata.with {
            $0.pollID = .with { $0.value = Data(repeating: 1, count: 16) }
            $0.chatID = .with { $0.value = Data(repeating: 2, count: 32) }
            $0.creator = .with { $0.value = UUID().data }
            $0.createdAt = .init(date: Date(timeIntervalSince1970: 1_000))
            $0.definition = .with {
                $0.optionCount = 2
                $0.mode = .count
                $0.endsAt = .init(date: Date(timeIntervalSince1970: 2_000))
                $0.plaintext = .with {
                    $0.question = "Lunch?"
                    $0.options = [.with { $0.text = "Pizza" }, .with { $0.text = "Tacos" }]
                }
            }
            $0.state = .with {
                $0.status = .open
                $0.selfVote = [1]
                $0.results = .with { $0.count = .with { $0.totalVoters = 3; $0.optionVoters = [1, 2] } }
            }
        }

        let poll = Poll(proto)
        #expect(poll.definition.mode == .count)
        #expect(poll.definition.text == .plaintext(question: "Lunch?", options: ["Pizza", "Tacos"]))
        #expect(poll.state.status == .open)
        #expect(poll.state.selfVote == [1])
        #expect(poll.state.results == .count(totalVoters: 3, optionVoters: [1, 2]))
        #expect(poll.definition.proto.optionCount == 2)
        #expect(poll.definition.proto.plaintext.question == "Lunch?")
    }
}
