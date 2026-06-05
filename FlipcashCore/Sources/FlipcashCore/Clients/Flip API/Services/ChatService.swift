//
//  ChatService.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI
import GRPC

private let logger = Logger(label: "flipcash.chat-service")

class ChatService: CodeService<Flipcash_Chat_V1_ChatNIOClient> {

    struct DmFeedPage: Sendable {
        let chats: [Conversation]
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

        let call = service.getDmChatFeed(request)
        call.handle(on: queue) { response in
            let error = ErrorGetDmChatFeed(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                let page = DmFeedPage(
                    chats: response.chats.map(Conversation.init),
                    pagingToken: response.pagingToken.value,
                    hasMore: response.hasMore_p
                )
                completion(.success(page))
            } else {
                logger.error("Failed to fetch DM chat feed")
                completion(.failure(error))
            }
        } failure: { _ in
            completion(.failure(.unknown))
        }
    }

    func getChat(owner: KeyPair, chatID: ChatID, completion: @Sendable @escaping (Result<Conversation, ErrorGetChat>) -> Void) {
        let request = Flipcash_Chat_V1_GetChatRequest.with {
            $0.chatID = chatID.proto
            $0.auth = owner.authFor(message: $0)
        }

        let call = service.getChat(request)
        call.handle(on: queue) { response in
            let error = ErrorGetChat(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok, response.hasMetadata {
                completion(.success(Conversation(response.metadata)))
            } else {
                logger.error("Failed to fetch chat")
                completion(.failure(error == .ok ? .notFound : error))
            }
        } failure: { _ in
            completion(.failure(.unknown))
        }
    }
}

// MARK: - Errors -

public enum ErrorGetDmChatFeed: Int, Error {
    case ok
    case denied
    case notFound
    case unknown = -1
}

public enum ErrorGetChat: Int, Error {
    case ok
    case denied
    case notFound
    case unknown = -1
}

extension ErrorGetDmChatFeed: ServerError {
    public var isReportable: Bool {
        switch self {
        case .ok, .denied, .notFound: false
        case .unknown: true
        }
    }
}

extension ErrorGetChat: ServerError {
    public var isReportable: Bool {
        switch self {
        case .ok, .denied, .notFound: false
        case .unknown: true
        }
    }
}

// MARK: - Interceptors -

extension InterceptorFactory: Flipcash_Chat_V1_ChatClientInterceptorFactoryProtocol {
    func makeGetChatInterceptors() -> [GRPC.ClientInterceptor<Flipcash_Chat_V1_GetChatRequest, Flipcash_Chat_V1_GetChatResponse>] {
        makeInterceptors()
    }

    func makeGetDmChatFeedInterceptors() -> [GRPC.ClientInterceptor<Flipcash_Chat_V1_GetDmChatFeedRequest, Flipcash_Chat_V1_GetDmChatFeedResponse>] {
        makeInterceptors()
    }
}

// MARK: - GRPCClientType -

extension Flipcash_Chat_V1_ChatNIOClient: GRPCClientType {
    init(channel: GRPCChannel) {
        self.init(channel: channel, defaultCallOptions: .default, interceptors: InterceptorFactory())
    }
}
