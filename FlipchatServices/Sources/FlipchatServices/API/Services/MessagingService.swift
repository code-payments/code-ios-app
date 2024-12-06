//
//  MessagingService.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipchatAPI
import Combine
import GRPC
import SwiftProtobuf

@MainActor
class MessagingService: FlipchatService<Flipchat_Messaging_V1_MessagingNIOClient> {
        
    func streamMessages(chatID: ChatID, from messageID: MessageID?, owner: KeyPair, completion: @escaping (Result<[Chat.Message], ErrorStreamMessages>) -> Void) -> StreamMessagesReference {
        trace(.open, components: "Chat \(chatID.description)", "Message ID: \(messageID?.description ?? "nil")", "Opening message stream.")
        
        let streamReference = StreamMessagesReference()
        streamReference.retain()
        
        streamReference.timeoutHandler = { [weak self, weak streamReference] in
            guard let streamReference else {
                return
            }
            
            trace(.warning, components: "Chat \(chatID.description)", "Stream (message) timed out")
            
            self?.streamMessages(
                chatID: chatID,
                from: messageID,
                owner: owner,
                assigningTo: streamReference,
                completion: completion
            )
        }
        
        streamMessages(
            chatID: chatID,
            from: messageID,
            owner: owner,
            assigningTo: streamReference,
            completion: completion
        )
        
        return streamReference
    }
    
    private func streamMessages(chatID: ChatID, from messageID: MessageID?, owner: KeyPair, assigningTo reference: StreamMessagesReference, completion: @escaping (Result<[Chat.Message], ErrorStreamMessages>) -> Void) {
        let queue = self.queue
        
        reference.cancel()
        reference.stream = service.streamMessages { [weak reference] response in
            
            guard let result = response.type else {
                trace(.failure, components: "Chat \(chatID.description)]", "Server sent empty message. This is unexpected.")
                return
            }
            
            switch result {
            case .messages(let messageBatch):
                
                let messages = messageBatch.messages.compactMap { Chat.Message($0) }
                queue.async {
                    trace(.receive, components: "Chat \(chatID.description)", "Received \(messages.count) events.")
                    completion(.success(messages))
                }
                
            case .ping(let ping):
                guard let stream = reference?.stream else {
                    break
                }
                
                let request = Flipchat_Messaging_V1_StreamMessagesRequest.with {
                    $0.pong = .with {
                        $0.timestamp = Google_Protobuf_Timestamp(date: .now)
                    }
                }
                
                reference?.receivedPing(updatedTimeout: Int(ping.pingDelay.seconds))
                
                _ = stream.sendMessage(request)
//                trace(.receive, components: "Pong", "Chat \(chatID.description)", "Server timestamp: \(ping.timestamp.date)")
                
            case .error(let streamError):
                queue.async {
                    let error = ErrorStreamMessages(rawValue: streamError.code.rawValue) ?? .unknown
                    completion(.failure(error))
                }
            }
        }
        
        reference.stream?.status.whenCompleteBlocking(onto: queue) { [weak self, weak reference] result in
            guard let self = self, let streamReference = reference else { return }
            
            if case .success(let status) = result, status.code == .unavailable {
                Task {
                    // Reconnect only if the stream was closed as a result of
                    // server actions and not cancelled by the client, etc.
                    trace(.note, components: "Chat \(chatID.description)", "Reconnecting keepalive stream...")
                    await self.streamMessages(
                        chatID: chatID,
                        from: messageID,
                        owner: owner,
                        assigningTo: streamReference,
                        completion: completion
                    )
                }
            } else {
                trace(.warning, components: "Chat \(chatID.description)", "Closing stream.")
            }
        }
        
        let request = Flipchat_Messaging_V1_StreamMessagesRequest.with {
            $0.params = .with {
                $0.chatID    = .with { $0.value = chatID.data }
                $0.resume    = messageID == nil ? .latestOnly(true) : .lastKnownMessageID(.with({ $0.value = messageID!.data }))
                $0.auth      = owner.authFor(message: $0)
            }
        }
        
        _ = reference.stream?.sendMessage(request)
        trace(.success, components: "Chat \(chatID.description)]", "Initiating a connection...")
    }
    
    func sendMessage(chatID: ChatID, owner: KeyPair, text: String, completion: @escaping (Result<Chat.Message, ErrorSendMessage>) -> Void) {
        trace(.send, components: "Owner: \(owner.publicKey.base58)")
        
        let request = Flipchat_Messaging_V1_SendMessageRequest.with {
            $0.chatID  = .with { $0.value = chatID.data }
            $0.content = [
                .with {
                    $0.text = .with { $0.text = text }
                }
            ]
            $0.auth = owner.authFor(message: $0)
        }
        
        let call = service.sendMessage(request)
        
        call.handle(on: queue) { response in
            let error = ErrorSendMessage(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                let message = Chat.Message(response.message)
                trace(.success, components: "Owner: \(owner.publicKey.base58)", "Message: \(message.id.description)")
                completion(.success(message))
            } else {
                trace(.success, components: "Error: \(error)")
                completion(.failure(error))
            }
            
        } failure: { error in
            completion(.failure(.unknown))
        }
    }

    func fetchMessages(chatID: ChatID, owner: KeyPair, query: PageQuery, completion: @escaping (Result<[Chat.Message], ErrorFetchMessages>) -> Void) {
        trace(.send, components: "Chat ID: \(chatID)", "Query: \(query.description)")
        
        let request = Flipchat_Messaging_V1_GetMessagesRequest.with {
            $0.chatID = .with { $0.value = chatID.data }
            $0.queryOptions = query.protoQueryOptions
            $0.auth = owner.authFor(message: $0)
        }
        
        let call = service.getMessages(request)
        
        call.handle(on: queue) { response in
            let error = ErrorFetchMessages(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                let messages = response.messages.map { Chat.Message($0) }
                trace(.success, components: "Chat ID: \(chatID)", "Messages: \(messages.count)")
                completion(.success(messages))
            } else {
                trace(.success, components: "Error: \(error)")
                completion(.failure(error))
            }
            
        } failure: { error in
            completion(.failure(.unknown))
        }
    }
    
    func advanceReadPointer(chatID: ChatID, to messageID: MessageID, owner: KeyPair, completion: @escaping (Result<Void, ErrorAdvancePointer>) -> Void) {
        trace(.send, components: "Owner: \(owner.publicKey.base58)", "Message ID: \(chatID.data.hexEncodedString())")
        
        let request = Flipchat_Messaging_V1_AdvancePointerRequest.with {
            $0.chatID = .with { $0.value = chatID.data }
            $0.pointer = .with {
                $0.type  = .read
                $0.value = .with { $0.value = messageID.data }
            }
            $0.auth = owner.authFor(message: $0)
        }
        
        let call = service.advancePointer(request)
        
        call.handle(on: queue) { response in
            let error = ErrorAdvancePointer(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                trace(.success, components: "Owner: \(owner.publicKey.base58)", "New Pointer: \(messageID.data.hexEncodedString())")
                completion(.success(()))
            } else {
                trace(.success, components: "Error: \(error)")
                completion(.failure(error))
            }
            
        } failure: { error in
            completion(.failure(.unknown))
        }
    }
}

// MARK: - Errors -

public enum ErrorStreamMessages: Int, Error {
    case denied
    case unknown = -1
}

public enum ErrorSendMessage: Int, Error {
    case ok
    case denied
    case unknown = -1
}

public enum ErrorFetchMessages: Int, Error {
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

// MARK: - Interceptors -

extension InterceptorFactory: Flipchat_Messaging_V1_MessagingClientInterceptorFactoryProtocol {
    func makeGetMessageInterceptors() -> [GRPC.ClientInterceptor<FlipchatAPI.Flipchat_Messaging_V1_GetMessageRequest, FlipchatAPI.Flipchat_Messaging_V1_GetMessageResponse>] {
        makeInterceptors()
    }
    
    func makeDeleteMessageInterceptors() -> [GRPC.ClientInterceptor<FlipchatAPI.Flipchat_Messaging_V1_DeleteMessageRequest, FlipchatAPI.Flipchat_Messaging_V1_DeleteMessageResponse>] {
        makeInterceptors()
    }
    
    func makeStreamMessagesInterceptors() -> [GRPC.ClientInterceptor<FlipchatAPI.Flipchat_Messaging_V1_StreamMessagesRequest, FlipchatAPI.Flipchat_Messaging_V1_StreamMessagesResponse>] {
        makeInterceptors()
    }
    
    func makeGetMessagesInterceptors() -> [GRPC.ClientInterceptor<FlipchatAPI.Flipchat_Messaging_V1_GetMessagesRequest, FlipchatAPI.Flipchat_Messaging_V1_GetMessagesResponse>] {
        makeInterceptors()
    }
    
    func makeSendMessageInterceptors() -> [GRPC.ClientInterceptor<FlipchatAPI.Flipchat_Messaging_V1_SendMessageRequest, FlipchatAPI.Flipchat_Messaging_V1_SendMessageResponse>] {
        makeInterceptors()
    }
    
    func makeAdvancePointerInterceptors() -> [GRPC.ClientInterceptor<FlipchatAPI.Flipchat_Messaging_V1_AdvancePointerRequest, FlipchatAPI.Flipchat_Messaging_V1_AdvancePointerResponse>] {
        makeInterceptors()
    }
    
    func makeNotifyIsTypingInterceptors() -> [GRPC.ClientInterceptor<FlipchatAPI.Flipchat_Messaging_V1_NotifyIsTypingRequest, FlipchatAPI.Flipchat_Messaging_V1_NotifyIsTypingResponse>] {
        makeInterceptors()
    }
}

// MARK: - GRPCClientType -

extension Flipchat_Messaging_V1_MessagingNIOClient: GRPCClientType {
    init(channel: GRPCChannel) {
        self.init(channel: channel, defaultCallOptions: CallOptions(), interceptors: InterceptorFactory())
    }
}
