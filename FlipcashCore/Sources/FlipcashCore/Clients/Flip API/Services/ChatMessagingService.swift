//
//  ChatMessagingService.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI
import GRPCCore

private let logger = Logger(label: "flipcash.chat-messaging-service")

/// Wraps the Core `messaging.v1` service (chat messages). Named distinctly from
/// the Payments-domain `MessagingService`, which handles bill rendezvous.
final class ChatMessagingService: Sendable {

    private let service: Flipcash_Messaging_V1_Messaging.Client<AppTransport>

    init(client: GRPCClient<AppTransport>) {
        self.service = Flipcash_Messaging_V1_Messaging.Client(wrapping: client)
    }

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

        Task {
            do {
                let response = try await service.getMessages(request, options: .unaryDefault)
                let error = ErrorGetMessages(rawValue: response.result.rawValue) ?? .unknown
                switch error {
                case .ok:
                    await MainActor.run { completion(.success(Array(response.messages.messages.compactMap(ConversationMessage.init).reversed()))) }
                case .notFound:
                    // An empty page is reported as NOT_FOUND, not empty OK.
                    await MainActor.run { completion(.success([])) }
                case .denied, .unknown, .transportFailure:
                    logger.error("Failed to fetch messages")
                    await MainActor.run { completion(.failure(error)) }
                }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

    func sendMessage(owner: KeyPair, conversationID: ConversationID, text: String, clientMessageID: UUID, completion: @Sendable @escaping (Result<ConversationMessage, ErrorSendMessage>) -> Void) {
        let request = Flipcash_Messaging_V1_SendMessageRequest.with {
            $0.chatID = conversationID.proto
            $0.content = [.with { $0.text = .with { $0.text = text } }]
            $0.clientMessageID = .with { $0.value = clientMessageID.data }
            $0.auth = owner.authFor(message: $0)
        }

        Task {
            do {
                let response = try await service.sendMessage(request, options: .unaryDefault)
                let error = ErrorSendMessage(rawValue: response.result.rawValue) ?? .unknown
                if error == .ok, response.hasMessage, let message = ConversationMessage(response.message) {
                    await MainActor.run { completion(.success(message)) }
                } else {
                    logger.error("Failed to send message")
                    await MainActor.run { completion(.failure(error == .ok ? .unknown : error)) }
                }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

    func advancePointer(owner: KeyPair, conversationID: ConversationID, messageID: MessageID, completion: @Sendable @escaping (Result<Void, ErrorAdvancePointer>) -> Void) {
        let request = Flipcash_Messaging_V1_AdvancePointerRequest.with {
            $0.chatID = conversationID.proto
            $0.pointerType = .read
            $0.newValue = messageID.proto
            $0.auth = owner.authFor(message: $0)
        }

        Task {
            do {
                let response = try await service.advancePointer(request, options: .unaryDefault)
                let error = ErrorAdvancePointer(rawValue: response.result.rawValue) ?? .unknown
                await MainActor.run { completion(error == .ok ? .success(()) : .failure(error)) }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

    func notifyIsTyping(owner: KeyPair, conversationID: ConversationID, state: TypingState, completion: @Sendable @escaping (Result<Void, ErrorNotifyIsTyping>) -> Void) {
        let request = Flipcash_Messaging_V1_NotifyIsTypingRequest.with {
            $0.chatID = conversationID.proto
            $0.state = state.proto
            $0.auth = owner.authFor(message: $0)
        }

        Task {
            do {
                let response = try await service.notifyIsTyping(request, options: .unaryDefault)
                let error = ErrorNotifyIsTyping(rawValue: response.result.rawValue) ?? .unknown
                await MainActor.run { completion(error == .ok ? .success(()) : .failure(error)) }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }
}

// MARK: - Errors -

public enum ErrorGetMessages: Int, Error {
    case ok
    case denied
    case notFound
    case unknown          = -1
    case transportFailure = -2
}

public enum ErrorSendMessage: Int, Error {
    case ok
    case denied
    case unknown          = -1
    case transportFailure = -2
}

public enum ErrorAdvancePointer: Int, Error {
    case ok
    case denied
    case messageNotFound
    case unknown          = -1
    case transportFailure = -2
}

public enum ErrorNotifyIsTyping: Int, Error {
    case ok
    case denied
    case unknown          = -1
    case transportFailure = -2
}

extension ErrorGetMessages: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .ok, .transportFailure: .suppressed
        case .denied, .notFound: .info
        case .unknown: .error
        }
    }
}

extension ErrorSendMessage: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .ok, .transportFailure: .suppressed
        case .denied: .info
        case .unknown: .error
        }
    }
}

extension ErrorAdvancePointer: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .ok, .transportFailure: .suppressed
        case .denied, .messageNotFound: .info
        case .unknown: .error
        }
    }
}

extension ErrorNotifyIsTyping: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .ok, .transportFailure: .suppressed
        case .denied: .info
        case .unknown: .error
        }
    }
}
