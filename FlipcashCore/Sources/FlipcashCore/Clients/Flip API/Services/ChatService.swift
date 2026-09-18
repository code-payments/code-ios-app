//
//  ChatService.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI
import GRPCCore

private let logger = Logger(label: "flipcash.chat-service")

final class ChatService: Sendable {

    private let service: Flipcash_Chat_V1_Chat.Client<AppTransport>

    init(client: GRPCClient<AppTransport>) {
        self.service = Flipcash_Chat_V1_Chat.Client(wrapping: client)
    }

    struct DmFeedPage: Sendable {
        let conversations: [Conversation]
        let pagingToken: Data
        let hasMore: Bool
    }

    func getDmChatFeed(owner: KeyPair, type: ConversationType, pageSize: Int = 50, pagingToken: Data?, completion: @Sendable @escaping (Result<DmFeedPage, ErrorGetDmChatFeed>) -> Void) {
        let request = Flipcash_Chat_V1_GetDmChatFeedRequest.with {
            $0.queryOptions = .with {
                $0.pageSize = Int32(pageSize)
                if let pagingToken {
                    $0.pagingToken = .with { $0.value = pagingToken }
                }
            }
            $0.dmChatType = type.proto
            $0.auth = owner.authFor(message: $0)
        }

        Task {
            do {
                let response = try await service.getDmChatFeed(request, options: .unaryDefault)
                let error = ErrorGetDmChatFeed(rawValue: response.result.rawValue) ?? .unknown
                guard error == .ok else {
                    logger.error("Failed to fetch DM chat feed")
                    await MainActor.run { completion(.failure(error)) }
                    return
                }
                let page = DmFeedPage(
                    conversations: response.chats.map(Conversation.init),
                    pagingToken: response.pagingToken.value,
                    hasMore: response.hasMore_p
                )
                await MainActor.run { completion(.success(page)) }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

    func getChat(owner: KeyPair, conversationID: ConversationID, viewMode: ConversationViewMode = .full, completion: @Sendable @escaping (Result<Conversation, ErrorGetChat>) -> Void) {
        let request = Flipcash_Chat_V1_GetChatRequest.with {
            $0.chatID = conversationID.proto
            $0.viewMode = viewMode.proto
            $0.auth = owner.authFor(message: $0)
        }

        Task {
            do {
                let response = try await service.getChat(request, options: .unaryDefault)
                let error = ErrorGetChat(rawValue: response.result.rawValue) ?? .unknown
                guard error == .ok, response.hasMetadata else {
                    logger.error("Failed to fetch chat")
                    await MainActor.run { completion(.failure(error == .ok ? .notFound : error)) }
                    return
                }
                await MainActor.run { completion(.success(Conversation(response.metadata))) }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }
    struct GroupFeedPage: Sendable {
        let conversations: [Conversation]
        let pagingToken: Data
        let hasMore: Bool
    }

    func getGroupChatFeed(owner: KeyPair, pageSize: Int = 50, pagingToken: Data?, completion: @Sendable @escaping (Result<GroupFeedPage, ErrorGetGroupChatFeed>) -> Void) {
        let request = Flipcash_Chat_V1_GetGroupChatFeedRequest.with {
            $0.queryOptions = .with {
                $0.pageSize = Int32(pageSize)
                if let pagingToken {
                    $0.pagingToken = .with { $0.value = pagingToken }
                }
            }
            $0.auth = owner.authFor(message: $0)
        }

        Task {
            do {
                let response = try await service.getGroupChatFeed(request, options: .unaryDefault)
                let error = ErrorGetGroupChatFeed(rawValue: response.result.rawValue) ?? .unknown
                guard error == .ok else {
                    logger.error("Failed to fetch group chat feed")
                    await MainActor.run { completion(.failure(error)) }
                    return
                }
                let page = GroupFeedPage(
                    conversations: response.chats.map(Conversation.init),
                    pagingToken: response.pagingToken.value,
                    hasMore: response.hasMore_p
                )
                await MainActor.run { completion(.success(page)) }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

    /// Starts a new group chat. `pictureBlobID` must already be `READY` (uploaded via
    /// `BlobService`); `rules` gate who may read/join and who may send — `nil` means no
    /// restrictions. On `.titleModerated` the server also reports which category flagged the
    /// title; `ErrorStartChat.titleModerated` carries it through so callers can say why, not just
    /// that the title was rejected.
    ///
    /// `idempotencyKey` is required by the server: caller and key together identify the chat being
    /// created, so a retry with the same key returns the original chat (result `.ok`) rather than
    /// creating a duplicate, even if `title`/`pictureBlobID`/`rules` differ on the retry. Mint it once
    /// where the user's intent to create the chat originates and reuse it for every retry of that same
    /// attempt — never generate a fresh key per call, or retries lose their idempotency.
    func startChat(owner: KeyPair, title: String, pictureBlobID: BlobID?, rules: ConversationRules?, idempotencyKey: UUID, completion: @Sendable @escaping (Result<Conversation, ErrorStartChat>) -> Void) {
        let request = Flipcash_Chat_V1_StartChatRequest.with {
            $0.group = .with {
                $0.title = title
                if let pictureBlobID {
                    $0.picture = .with { $0.value = pictureBlobID.data }
                }
                if let rules {
                    $0.rules = rules.proto
                }
            }
            $0.idempotencyKey = .with { $0.value = idempotencyKey.data }
            $0.auth = owner.authFor(message: $0)
        }

        Task {
            do {
                let response = try await service.startChat(request, options: .unaryDefault)
                guard response.result == .ok else {
                    logger.error("Failed to start chat")
                    await MainActor.run { completion(.failure(ErrorStartChat(response.result, flaggedCategory: response.flaggedCategory))) }
                    return
                }
                guard response.hasChat else {
                    logger.error("Failed to start chat")
                    await MainActor.run { completion(.failure(.unknown)) }
                    return
                }
                await MainActor.run { completion(.success(Conversation(response.chat))) }
            } catch let error as RPCError {
                // The six StartChat results all arrive as `.ok`-shaped responses, so a transport
                // status is the one failure whose cause isn't in the result — name its code.
                logger.error("Failed to start chat at the transport", metadata: ["code": "\(error.code)"])
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

    func joinChat(owner: KeyPair, conversationID: ConversationID, completion: @Sendable @escaping (Result<Conversation, ErrorJoinChat>) -> Void) {
        let request = Flipcash_Chat_V1_JoinChatRequest.with {
            $0.chatID = conversationID.proto
            $0.auth = owner.authFor(message: $0)
        }

        Task {
            do {
                let response = try await service.joinChat(request, options: .unaryDefault)
                let error = ErrorJoinChat(rawValue: response.result.rawValue) ?? .unknown
                guard error == .ok, response.hasChat else {
                    logger.error("Failed to join chat")
                    await MainActor.run { completion(.failure(error == .ok ? .unknown : error)) }
                    return
                }
                await MainActor.run { completion(.success(Conversation(response.chat))) }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

    func leaveChat(owner: KeyPair, conversationID: ConversationID, completion: @Sendable @escaping (Result<Void, ErrorLeaveChat>) -> Void) {
        let request = Flipcash_Chat_V1_LeaveChatRequest.with {
            $0.chatID = conversationID.proto
            $0.auth = owner.authFor(message: $0)
        }

        Task {
            do {
                let response = try await service.leaveChat(request, options: .unaryDefault)
                let error = ErrorLeaveChat(rawValue: response.result.rawValue) ?? .unknown
                guard error == .ok else {
                    logger.error("Failed to leave chat")
                    await MainActor.run { completion(.failure(error)) }
                    return
                }
                await MainActor.run { completion(.success(())) }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

    func muteChat(owner: KeyPair, conversationID: ConversationID, mute: ConversationMuteState, completion: @Sendable @escaping (Result<ConversationViewerState, ErrorMuteChat>) -> Void) {
        let request = Flipcash_Chat_V1_MuteChatRequest.with {
            $0.chatID = conversationID.proto
            $0.mute = mute.proto
            $0.auth = owner.authFor(message: $0)
        }

        Task {
            do {
                let response = try await service.muteChat(request, options: .unaryDefault)
                let error = ErrorMuteChat(rawValue: response.result.rawValue) ?? .unknown
                guard error == .ok, response.hasViewerState else {
                    logger.error("Failed to mute chat")
                    await MainActor.run { completion(.failure(error == .ok ? .unknown : error)) }
                    return
                }
                await MainActor.run { completion(.success(ConversationViewerState(response.viewerState))) }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

    func unmuteChat(owner: KeyPair, conversationID: ConversationID, completion: @Sendable @escaping (Result<ConversationViewerState, ErrorUnmuteChat>) -> Void) {
        let request = Flipcash_Chat_V1_UnmuteChatRequest.with {
            $0.chatID = conversationID.proto
            $0.auth = owner.authFor(message: $0)
        }

        Task {
            do {
                let response = try await service.unmuteChat(request, options: .unaryDefault)
                let error = ErrorUnmuteChat(rawValue: response.result.rawValue) ?? .unknown
                guard error == .ok, response.hasViewerState else {
                    logger.error("Failed to unmute chat")
                    await MainActor.run { completion(.failure(error == .ok ? .unknown : error)) }
                    return
                }
                await MainActor.run { completion(.success(ConversationViewerState(response.viewerState))) }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }
}

// MARK: - Errors -

public enum ErrorGetDmChatFeed: Int, Error {
    case ok
    case denied
    case notFound
    case unknown          = -1
    case transportFailure = -2
    case cancelled = -3
    case rejected = -4
}

public enum ErrorGetChat: Int, Error {
    case ok
    case denied
    case notFound
    case unknown          = -1
    case transportFailure = -2
    case cancelled = -3
    case rejected = -4
}

public enum ErrorGetGroupChatFeed: Int, Error {
    case ok
    case denied
    case notFound
    case unknown          = -1
    case transportFailure = -2
    case cancelled = -3
    case rejected = -4
}

/// Associated-value error, modelled on `ErrorProfile`, so `.titleModerated` can carry the
/// `flaggedCategory` the server reports for it — the moderation category the plain-Int pattern
/// used by this file's other error enums has no room for. No `.ok` case: a success response
/// resolves to `Conversation` in `startChat`'s `Result`, it never reaches this type.
public enum ErrorStartChat: Error, Sendable, Equatable {
    case denied
    case titleModerated(Flipcash_Moderation_V1_FlaggedCategory)
    case pictureBlobNotAccepted
    case invalidRules
    case rulesNotSatisfied
    case unknown
    case transportFailure
    case cancelled
    case rejected
}

public enum ErrorJoinChat: Int, Error {
    case ok
    case denied
    case notFound
    case rulesNotSatisfied
    case unknown          = -1
    case transportFailure = -2
    case cancelled = -3
    case rejected = -4
}

public enum ErrorLeaveChat: Int, Error {
    case ok
    case denied
    case notFound
    case unknown          = -1
    case transportFailure = -2
    case cancelled = -3
    case rejected = -4
}

public enum ErrorMuteChat: Int, Error {
    case ok
    case denied
    case notFound
    case unknown          = -1
    case transportFailure = -2
    case cancelled = -3
    case rejected = -4
}

public enum ErrorUnmuteChat: Int, Error {
    case ok
    case denied
    case notFound
    case unknown          = -1
    case transportFailure = -2
    case cancelled = -3
    case rejected = -4
}

extension ErrorGetDmChatFeed: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .ok, .transportFailure: .suppressed
        case .cancelled: .info
        case .denied, .notFound: .info
        case .unknown, .rejected: .error
        }
    }
}

extension ErrorGetChat: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .ok, .transportFailure: .suppressed
        case .cancelled: .info
        case .denied, .notFound: .info
        case .unknown, .rejected: .error
        }
    }
}

extension ErrorGetGroupChatFeed: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .ok, .transportFailure: .suppressed
        case .cancelled: .info
        case .denied, .notFound: .info
        case .unknown, .rejected: .error
        }
    }
}

extension ErrorStartChat: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .transportFailure: .suppressed
        case .cancelled: .info
        case .denied, .titleModerated, .pictureBlobNotAccepted, .invalidRules, .rulesNotSatisfied: .info
        case .unknown, .rejected: .error
        }
    }
}

extension ErrorStartChat {
    /// Maps a non-`.ok` `StartChatResponse.Result` to its domain error, carrying `flaggedCategory`
    /// through on `.titleModerated` rather than flattening it. Pure and synchronous so the mapping is
    /// unit-testable without a live RPC. Callers only reach this once they've confirmed `result != .ok`;
    /// `.ok` itself resolves to `Conversation` in `ChatService.startChat`, not this type, but is handled
    /// here too (as `.unknown`) so the mapping is total over every case of the proto enum.
    init(_ result: Flipcash_Chat_V1_StartChatResponse.Result, flaggedCategory: Flipcash_Moderation_V1_FlaggedCategory) {
        switch result {
        case .ok:
            self = .unknown
        case .denied:
            self = .denied
        case .titleModerated:
            self = .titleModerated(flaggedCategory)
        case .pictureBlobNotAccepted:
            self = .pictureBlobNotAccepted
        case .invalidRules:
            self = .invalidRules
        case .rulesNotSatisfied:
            self = .rulesNotSatisfied
        case .UNRECOGNIZED:
            self = .unknown
        }
    }
}

extension ErrorJoinChat: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .ok, .transportFailure: .suppressed
        case .cancelled: .info
        case .denied, .notFound, .rulesNotSatisfied: .info
        case .unknown, .rejected: .error
        }
    }
}

extension ErrorLeaveChat: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .ok, .transportFailure: .suppressed
        case .cancelled: .info
        case .denied, .notFound: .info
        case .unknown, .rejected: .error
        }
    }
}

extension ErrorMuteChat: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .ok, .transportFailure: .suppressed
        case .cancelled: .info
        case .denied, .notFound: .info
        case .unknown, .rejected: .error
        }
    }
}

extension ErrorUnmuteChat: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .ok, .transportFailure: .suppressed
        case .cancelled: .info
        case .denied, .notFound: .info
        case .unknown, .rejected: .error
        }
    }
}
