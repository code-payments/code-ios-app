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

    func getDmChatFeed(owner: KeyPair, pageSize: Int = 50, pagingToken: Data?, completion: @Sendable @escaping (Result<DmFeedPage, ErrorGetDmChatFeed>) -> Void) {
        let request = Flipcash_Chat_V1_GetDmChatFeedRequest.with {
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
}

// MARK: - Errors -

public enum ErrorGetDmChatFeed: Int, Error {
    case ok
    case denied
    case notFound
    case unknown          = -1
    case transportFailure = -2
}

public enum ErrorGetChat: Int, Error {
    case ok
    case denied
    case notFound
    case unknown          = -1
    case transportFailure = -2
}

extension ErrorGetDmChatFeed: ServerError, TransportClassifiableError {
    public var isReportable: Bool {
        switch self {
        case .ok, .denied, .notFound, .transportFailure: false
        case .unknown: true
        }
    }
}

extension ErrorGetChat: ServerError, TransportClassifiableError {
    public var isReportable: Bool {
        switch self {
        case .ok, .denied, .notFound, .transportFailure: false
        case .unknown: true
        }
    }
}
