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

    func getChat(owner: KeyPair, conversationID: ConversationID, completion: @Sendable @escaping (Result<Conversation, ErrorGetChat>) -> Void) {
        let request = Flipcash_Chat_V1_GetChatRequest.with {
            $0.chatID = conversationID.proto
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
    /// title, but that detail isn't surfaced through this Int-rawValue error — callers only see
    /// that the title was rejected.
    func startChat(owner: KeyPair, title: String, pictureBlobID: BlobID?, rules: ConversationRules?, completion: @Sendable @escaping (Result<Conversation, ErrorStartChat>) -> Void) {
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
            $0.auth = owner.authFor(message: $0)
        }

        Task {
            do {
                let response = try await service.startChat(request, options: .unaryDefault)
                let error = ErrorStartChat(rawValue: response.result.rawValue) ?? .unknown
                guard error == .ok, response.hasChat else {
                    logger.error("Failed to start chat")
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

/// The proto also reports a `flaggedCategory` on `.titleModerated`; this Int-rawValue enum can't
/// carry that payload, so callers only learn the title was rejected, not why.
public enum ErrorStartChat: Int, Error {
    case ok
    case denied
    case titleModerated
    case pictureBlobNotAccepted
    case invalidRules
    case rulesNotSatisfied
    case unknown          = -1
    case transportFailure = -2
    case cancelled = -3
    case rejected = -4
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
        case .ok, .transportFailure: .suppressed
        case .cancelled: .info
        case .denied, .titleModerated, .pictureBlobNotAccepted, .invalidRules, .rulesNotSatisfied: .info
        case .unknown, .rejected: .error
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
