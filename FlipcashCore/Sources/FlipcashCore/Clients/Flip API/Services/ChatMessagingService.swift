//
//  ChatMessagingService.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI
import GRPC

private let logger = Logger(label: "flipcash.chat-messaging-service")

/// Wraps the Core `messaging.v1` service (chat messages). Named distinctly from
/// the Payments-domain `MessagingService`, which handles bill rendezvous.
class ChatMessagingService: CodeService<Flipcash_Messaging_V1_MessagingNIOClient> {

    /// Fetches the newest `pageSize` messages (descending on the wire — without
    /// an explicit order the server defaults to ascending and a long chat's
    /// first page would be its OLDEST messages), returned oldest-first.
    func getMessages(owner: KeyPair, conversationID: ConversationID, pageSize: Int = 50, pagingToken: Data?, completion: @Sendable @escaping (Result<[ConversationMessage], ErrorGetMessages>) -> Void) {
        let request = Flipcash_Messaging_V1_GetMessagesRequest.with {
            $0.chatID = conversationID.proto
            $0.options = .with {
                $0.pageSize = Int32(pageSize)
                $0.order = .desc
                if let pagingToken {
                    $0.pagingToken = .with { $0.value = pagingToken }
                }
            }
            $0.auth = owner.authFor(message: $0)
        }

        let call = service.getMessages(request)
        call.handle(on: queue) { response in
            let error = ErrorGetMessages(rawValue: response.result.rawValue) ?? .unknown
            switch error {
            case .ok:
                completion(.success(Array(response.messages.messages.compactMap(ConversationMessage.init).reversed())))
            case .notFound:
                // An empty page is reported as NOT_FOUND, not empty OK.
                completion(.success([]))
            case .denied, .unknown:
                logger.error("Failed to fetch messages")
                completion(.failure(error))
            }
        } failure: { _ in
            completion(.failure(.unknown))
        }
    }

    func sendMessage(owner: KeyPair, conversationID: ConversationID, text: String, completion: @Sendable @escaping (Result<ConversationMessage, ErrorSendMessage>) -> Void) {
        let request = Flipcash_Messaging_V1_SendMessageRequest.with {
            $0.chatID = conversationID.proto
            $0.content = [.with { $0.text = .with { $0.text = text } }]
            $0.clientMessageID = .with { $0.value = UUID().data }
            $0.auth = owner.authFor(message: $0)
        }

        let call = service.sendMessage(request)
        call.handle(on: queue) { response in
            let error = ErrorSendMessage(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok, response.hasMessage, let message = ConversationMessage(response.message) {
                completion(.success(message))
            } else {
                logger.error("Failed to send message")
                completion(.failure(error == .ok ? .unknown : error))
            }
        } failure: { _ in
            completion(.failure(.unknown))
        }
    }

    func advancePointer(owner: KeyPair, conversationID: ConversationID, messageID: MessageID, completion: @Sendable @escaping (Result<Void, ErrorAdvancePointer>) -> Void) {
        let request = Flipcash_Messaging_V1_AdvancePointerRequest.with {
            $0.chatID = conversationID.proto
            $0.pointerType = .read
            $0.newValue = messageID.proto
            $0.auth = owner.authFor(message: $0)
        }

        let call = service.advancePointer(request)
        call.handle(on: queue) { response in
            let error = ErrorAdvancePointer(rawValue: response.result.rawValue) ?? .unknown
            completion(error == .ok ? .success(()) : .failure(error))
        } failure: { _ in
            completion(.failure(.unknown))
        }
    }
}

// MARK: - Errors -

public enum ErrorGetMessages: Int, Error {
    case ok
    case denied
    case notFound
    case unknown = -1
}

public enum ErrorSendMessage: Int, Error {
    case ok
    case denied
    case unknown = -1
}

public enum ErrorAdvancePointer: Int, Error {
    case ok
    case denied
    case messageNotFound
    case unknown = -1
}

extension ErrorGetMessages: ServerError {
    public var isReportable: Bool {
        switch self {
        case .ok, .denied, .notFound: false
        case .unknown: true
        }
    }
}

extension ErrorSendMessage: ServerError {
    public var isReportable: Bool {
        switch self {
        case .ok, .denied: false
        case .unknown: true
        }
    }
}

extension ErrorAdvancePointer: ServerError {
    public var isReportable: Bool {
        switch self {
        case .ok, .denied, .messageNotFound: false
        case .unknown: true
        }
    }
}

// MARK: - Interceptors -

extension InterceptorFactory: Flipcash_Messaging_V1_MessagingClientInterceptorFactoryProtocol {
    func makeGetMessageInterceptors() -> [GRPC.ClientInterceptor<Flipcash_Messaging_V1_GetMessageRequest, Flipcash_Messaging_V1_GetMessageResponse>] {
        makeInterceptors()
    }

    func makeGetMessagesInterceptors() -> [GRPC.ClientInterceptor<Flipcash_Messaging_V1_GetMessagesRequest, Flipcash_Messaging_V1_GetMessagesResponse>] {
        makeInterceptors()
    }

    func makeSendMessageInterceptors() -> [GRPC.ClientInterceptor<Flipcash_Messaging_V1_SendMessageRequest, Flipcash_Messaging_V1_SendMessageResponse>] {
        makeInterceptors()
    }

    func makeAdvancePointerInterceptors() -> [GRPC.ClientInterceptor<Flipcash_Messaging_V1_AdvancePointerRequest, Flipcash_Messaging_V1_AdvancePointerResponse>] {
        makeInterceptors()
    }

    func makeNotifyIsTypingInterceptors() -> [GRPC.ClientInterceptor<Flipcash_Messaging_V1_NotifyIsTypingRequest, Flipcash_Messaging_V1_NotifyIsTypingResponse>] {
        makeInterceptors()
    }
}

// MARK: - GRPCClientType -

extension Flipcash_Messaging_V1_MessagingNIOClient: GRPCClientType {
    init(channel: GRPCChannel) {
        self.init(channel: channel, defaultCallOptions: .default, interceptors: InterceptorFactory())
    }
}
