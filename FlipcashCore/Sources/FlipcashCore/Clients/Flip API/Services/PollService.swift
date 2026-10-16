//
//  PollService.swift
//  FlipcashCore
//

import Foundation
import FlipcashAPI
import GRPCCore

private let logger = Logger(label: "flipcash.poll-service")

final class PollService: Sendable {

    private let service: Flipcash_Poll_V1_Poll.Client<AppTransport>

    init(client: GRPCClient<AppTransport>) {
        self.service = Flipcash_Poll_V1_Poll.Client(wrapping: client)
    }

    /// Opens a poll in a group chat. `idempotencyKey` must be minted where the user's intent to
    /// create the poll begins, so a retry of the same intent cannot create a second poll.
    func createPoll(owner: KeyPair, conversationID: ConversationID, definition: PollDefinition, idempotencyKey: UUID, completion: @Sendable @escaping (Result<Poll, ErrorCreatePoll>) -> Void) {
        let request = Flipcash_Poll_V1_CreatePollRequest.with {
            $0.chatID = conversationID.proto
            $0.definition = definition.proto
            $0.idempotencyKey = .with { $0.value = idempotencyKey.data }
            $0.auth = owner.authFor(message: $0)
        }

        Task {
            do {
                let response = try await service.createPoll(request, options: .unaryDefault)
                guard response.result == .ok, response.hasPoll else {
                    logger.error("Failed to create poll")
                    let error = ErrorCreatePoll(response.result, flaggedCategory: response.flaggedCategory)
                    await MainActor.run { completion(.failure(error == .ok ? .unknown : error)) }
                    return
                }
                await MainActor.run { completion(.success(Poll(response.poll))) }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

    func getPoll(owner: KeyPair, pollID: PollID, completion: @Sendable @escaping (Result<Poll, ErrorGetPoll>) -> Void) {
        let request = Flipcash_Poll_V1_GetPollRequest.with {
            $0.pollID = pollID.proto
            $0.auth = owner.authFor(message: $0)
        }

        Task {
            do {
                let response = try await service.getPoll(request, options: .unaryDefault)
                let error = ErrorGetPoll(rawValue: response.result.rawValue) ?? .unknown
                guard error == .ok, response.hasPoll else {
                    logger.error("Failed to get poll")
                    await MainActor.run { completion(.failure(error == .ok ? .unknown : error)) }
                    return
                }
                await MainActor.run { completion(.success(Poll(response.poll))) }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

    /// Fetches up to 100 polls in one call. Polls the server doesn't return (unknown or not
    /// visible to the caller) are simply absent from the result.
    func getPolls(owner: KeyPair, pollIDs: [PollID], completion: @Sendable @escaping (Result<[Poll], ErrorGetPolls>) -> Void) {
        let request = Flipcash_Poll_V1_GetPollsRequest.with {
            $0.pollIds = pollIDs.map(\.proto)
            $0.auth = owner.authFor(message: $0)
        }

        Task {
            do {
                let response = try await service.getPolls(request, options: .unaryDefault)
                let error = ErrorGetPolls(rawValue: response.result.rawValue) ?? .unknown
                guard error == .ok else {
                    logger.error("Failed to get polls")
                    await MainActor.run { completion(.failure(error)) }
                    return
                }
                await MainActor.run { completion(.success(response.polls.map(Poll.init))) }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

    /// Records the viewer's selection, replacing any earlier one, and returns the updated state.
    func vote(owner: KeyPair, pollID: PollID, optionIndices: [Int], completion: @Sendable @escaping (Result<PollState, ErrorVote>) -> Void) {
        let request = Flipcash_Poll_V1_VoteRequest.with {
            $0.pollID = pollID.proto
            $0.optionIndices = optionIndices.map { UInt32($0) }
            $0.auth = owner.authFor(message: $0)
        }

        Task {
            do {
                let response = try await service.vote(request, options: .unaryDefault)
                let error = ErrorVote(rawValue: response.result.rawValue) ?? .unknown
                guard error == .ok, response.hasState else {
                    logger.error("Failed to vote")
                    await MainActor.run { completion(.failure(error == .ok ? .unknown : error)) }
                    return
                }
                await MainActor.run { completion(.success(PollState(response.state))) }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }
}

// MARK: - Errors -

/// Associated-value error, modelled on `ErrorStartChat`, so `.textModerated` can carry the
/// `flaggedCategory` the server reports for it. `.ok` exists only so `init(_:flaggedCategory:)` is
/// total over the proto enum; a success response resolves to `Poll` and never reaches this type.
public enum ErrorCreatePoll: Error, Sendable, Equatable {
    case ok
    case denied
    case chatNotSupported
    case encryptionNotAllowed
    case encryptionRequired
    case optionCountMismatch
    case invalidEndsAt
    case invalidBalanceParameters
    case textModerated(Flipcash_Moderation_V1_FlaggedCategory)
    case unknown
    case transportFailure
    case cancelled
    case rejected
}

public enum ErrorGetPoll: Int, Error {
    case ok
    case denied
    case notFound
    case unknown          = -1
    case transportFailure = -2
    case cancelled        = -3
    case rejected         = -4
}

public enum ErrorGetPolls: Int, Error {
    case ok
    case denied
    case unknown          = -1
    case transportFailure = -2
    case cancelled        = -3
    case rejected         = -4
}

public enum ErrorVote: Int, Error {
    case ok
    case denied
    case notFound
    case pollClosed
    case invalidSelection
    case unknown          = -1
    case transportFailure = -2
    case cancelled        = -3
    case rejected         = -4
}

extension ErrorCreatePoll: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .ok, .transportFailure: .suppressed
        case .cancelled: .info
        case .denied, .chatNotSupported, .encryptionNotAllowed, .encryptionRequired, .textModerated: .info
        // Validation the client is expected to satisfy before sending; a hit is a client defect.
        case .optionCountMismatch, .invalidEndsAt, .invalidBalanceParameters: .error
        case .unknown, .rejected: .error
        }
    }
}

extension ErrorCreatePoll {
    /// Maps `CreatePollResponse.Result` to its domain error, carrying `flaggedCategory` through on
    /// `.textModerated`. Pure so the mapping is unit-testable without a live RPC.
    init(_ result: Flipcash_Poll_V1_CreatePollResponse.Result, flaggedCategory: Flipcash_Moderation_V1_FlaggedCategory) {
        switch result {
        case .ok:                       self = .ok
        case .denied:                   self = .denied
        case .chatNotSupported:         self = .chatNotSupported
        case .encryptionNotAllowed:     self = .encryptionNotAllowed
        case .encryptionRequired:       self = .encryptionRequired
        case .optionCountMismatch:      self = .optionCountMismatch
        case .invalidEndsAt:            self = .invalidEndsAt
        case .invalidBalanceParameters: self = .invalidBalanceParameters
        case .textModerated:            self = .textModerated(flaggedCategory)
        case .UNRECOGNIZED:             self = .unknown
        }
    }
}

extension ErrorGetPoll: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .ok, .transportFailure: .suppressed
        case .cancelled: .info
        case .denied, .notFound: .info
        case .unknown, .rejected: .error
        }
    }
}

extension ErrorGetPolls: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .ok, .transportFailure: .suppressed
        case .cancelled: .info
        case .denied: .info
        case .unknown, .rejected: .error
        }
    }
}

extension ErrorVote: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .ok, .transportFailure: .suppressed
        case .cancelled: .info
        case .denied, .notFound, .pollClosed: .info
        case .invalidSelection: .error
        case .unknown, .rejected: .error
        }
    }
}
