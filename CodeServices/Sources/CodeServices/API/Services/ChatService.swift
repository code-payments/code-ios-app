//
//  ChatService.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import CodeAPI
import Combine
import GRPC
import SwiftProtobuf

class ChatService: CodeService<Code_Chat_V1_ChatNIOClient> {
        
    func openChatStream(chatID: ID, owner: KeyPair, completion: @escaping (Result<[Chat.Message], Error>) -> Void) -> ChatMessageStreamReference {
        trace(.open, components: "Chat \(chatID.description)]", "Opening stream.")
        
        let streamReference = ChatMessageStreamReference()
        streamReference.retain()
        
        streamReference.timeoutHandler = { [weak self, weak streamReference] in
            guard let streamReference else {
                return
            }
            
            trace(.warning, components: "Chat \(chatID.description)]", "Stream timed out")
            
            self?.openChatStream(
                chatID: chatID,
                owner: owner,
                assigningTo: streamReference,
                completion: completion
            )
        }
        
        openChatStream(
            chatID: chatID,
            owner: owner,
            assigningTo: streamReference,
            completion: completion
        )
        
        return streamReference
    }
    
    private func openChatStream(chatID: ID, owner: KeyPair, assigningTo reference: ChatMessageStreamReference, completion: @escaping (Result<[Chat.Message], Error>) -> Void) {
        let queue = self.queue
        
        reference.cancel()
        reference.stream = service.streamChatEvents { [weak reference] response in
            
            guard let result = response.type else {
                trace(.failure, components: "Chat \(chatID.description)]", "Server sent empty message. This is unexpected.")
                return
            }
            
            switch result {
            case .events(let eventBatch):
                
                let messages = eventBatch.events
                    .flatMap { $0.messages }
                    .map { Chat.Message($0) }
                
                queue.async {
                    trace(.receive, components: "Chat \(chatID.description)", "Received \(messages.count) messages.")
                    completion(.success(messages))
                }
                
            case .ping(let ping):
                guard let stream = reference?.stream else {
                    break
                }
                
                // TODO: Track ping timestamps and reopen stream if we haven't received a ping in `pingDelay` * 2
                
                let request = Code_Chat_V1_StreamChatEventsRequest.with {
                    $0.type = .pong(.with {
                        $0.timestamp = Google_Protobuf_Timestamp(date: .now())
                    })
                }
                
                reference?.receivedPing(updatedTimeout: Int(ping.pingDelay.seconds))
                
                _ = stream.sendMessage(request)
                trace(.receive, components: "Pong", "Chat \(chatID.description)", "Server timestamp: \(ping.timestamp.date)")
                
                // TODO: Handle message sent
                
                break
            }
        }
        
        reference.stream?.status.whenCompleteBlocking(onto: queue) { [weak self, weak reference] result in
            guard let self = self, let streamReference = reference else { return }
            
            if case .success(let status) = result, status.code == .unavailable {
                // Reconnect only if the stream was closed as a result of
                // server actions and not cancelled by the client, etc.
                trace(.note, components: "Chat \(chatID.description)", "Reconnecting keepalive stream...")
                self.openChatStream(
                    chatID: chatID,
                    owner: owner,
                    assigningTo: streamReference,
                    completion: completion
                )
            } else {
                trace(.warning, components: "Chat \(chatID.description)", "Closing stream.")
            }
        }
        
        let request = Code_Chat_V1_StreamChatEventsRequest.with {
            $0.openStream = .with {
                $0.chatID    = .with { $0.value = chatID.data }
                $0.owner     = owner.publicKey.codeAccountID
                $0.signature = $0.sign(with: owner)
            }
        }
        
        _ = reference.stream?.sendMessage(request)
        trace(.success, components: "Chat \(chatID.description)]", "Initiating a connection...")
    }
    
    func fetchChats(owner: KeyPair, completion: @escaping (Result<[Chat], ErrorFetchChats>) -> Void) {
//        trace(.send, components: "Owner: \(owner.publicKey.base58)")
        
        let request = Code_Chat_V1_GetChatsRequest.with {
            $0.owner = owner.publicKey.codeAccountID
            $0.signature = $0.sign(with: owner)
        }
        
        let call = service.getChats(request)
        
        call.handle(on: queue) { response in
            let error = ErrorFetchChats(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok || error == .notFound {
//                trace(.success, components: "Owner: \(owner.publicKey.base58)", "Chats: \(chats.count)")
                DispatchQueue.main.async {
                    let chats = response.chats.map { Chat($0) }
                    completion(.success(chats))
                }
            } else {
                trace(.success, components: "Error: \(error)")
                completion(.failure(error))
            }
            
        } failure: { error in
            completion(.failure(.unknown))
        }
    }
    
    func fetchMessages(chatID: ID, owner: KeyPair, direction: MessageDirection, pageSize: Int, completion: @escaping (Result<[Chat.Message], ErrorFetchMessages>) -> Void) {
//        trace(.send, components: "Owner: \(owner.publicKey.base58)", "Chat ID: \(chatID.data.hexEncodedString())", "Page size: \(pageSize)")
        
        let request = Code_Chat_V1_GetMessagesRequest.with {
            $0.chatID   = .with { $0.value = chatID.data }
            $0.owner    = owner.publicKey.codeAccountID
            $0.pageSize = UInt32(pageSize)
            
            switch direction {
            case .ascending(let id):
                $0.direction = .asc
                if let id {
                    $0.cursor = .with { $0.value = id.data }
                }
                
            case .descending(let id):
                $0.direction = .desc
                if let id {
                    $0.cursor = .with { $0.value = id.data }
                }
            }
            
            $0.signature = $0.sign(with: owner)
        }
        
        let call = service.getMessages(request)
        
        call.handle(on: queue) { response in
            let error = ErrorFetchMessages(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok || error == .notFound {
                let messages = response.messages.map { Chat.Message($0) }
//                trace(.success, components: "Owner: \(owner.publicKey.base58)", "Messages: \(messages.count)")
                completion(.success(messages))
            } else {
                trace(.success, components: "Error: \(error)")
                completion(.failure(error))
            }
            
        } failure: { error in
            completion(.failure(.unknown))
        }
    }
    
    func advancePointer(chatID: ID, to messageID: ID, owner: KeyPair, completion: @escaping (Result<Void, ErrorAdvancePointer>) -> Void) {
        trace(.send, components: "Owner: \(owner.publicKey.base58)", "Chat ID: \(chatID.data.hexEncodedString())")
        
        let request = Code_Chat_V1_AdvancePointerRequest.with {
            $0.chatID = .with { $0.value = chatID.data }
            $0.pointer = Code_Chat_V1_Pointer.with {
                $0.kind = .read
                $0.value = Code_Chat_V1_ChatMessageId.with { $0.value = messageID.data }
            }
            $0.owner = owner.publicKey.codeAccountID
            $0.signature = $0.sign(with: owner)
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
    
    func setMuteState(chatID: ID, muted: Bool, owner: KeyPair, completion: @escaping (Result<Void, ErrorSetMuteState>) -> Void) {
        trace(.send, components: "Chat ID: \(chatID.data.hexEncodedString())")
        
        let request = Code_Chat_V1_SetMuteStateRequest.with {
            $0.chatID = .with { $0.value = chatID.data }
            $0.isMuted = muted
            $0.owner = owner.publicKey.codeAccountID
            $0.signature = $0.sign(with: owner)
        }
        
        let call = service.setMuteState(request)
        
        call.handle(on: queue) { response in
            let error = ErrorSetMuteState(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                trace(.success, components: "Chat ID: \(chatID.data.hexEncodedString())", "Muted: \(muted)")
                completion(.success(()))
            } else {
                trace(.success, components: "Error: \(error)")
                completion(.failure(error))
            }
            
        } failure: { error in
            completion(.failure(.unknown))
        }
    }
    
    func setSubscriptionState(chatID: ID, subscribed: Bool, owner: KeyPair, completion: @escaping (Result<Void, ErrorSetSubscriptionState>) -> Void) {
        trace(.send, components: "Chat ID: \(chatID.data.hexEncodedString())")
        
        let request = Code_Chat_V1_SetSubscriptionStateRequest.with {
            $0.chatID = .with { $0.value = chatID.data }
            $0.isSubscribed = subscribed
            $0.owner = owner.publicKey.codeAccountID
            $0.signature = $0.sign(with: owner)
        }
        
        let call = service.setSubscriptionState(request)
        
        call.handle(on: queue) { response in
            let error = ErrorSetSubscriptionState(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                trace(.success, components: "Chat ID: \(chatID.data.hexEncodedString())", "Subscribed: \(subscribed)")
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

// MARK: - Types -

public enum MessageDirection {
    case ascending(from: ID?)
    case descending(upTo: ID?)
}

// MARK: - Errors -

public enum ErrorFetchChats: Int, Error {
    case ok
    case notFound
    case unknown = -1
}

public enum ErrorFetchMessages: Int, Error {
    case ok
    case notFound
    case unknown = -1
}

public enum ErrorAdvancePointer: Int, Error {
    case ok
    case chatNotFound
    case messageNotFound
    case unknown = -1
}

public enum ErrorSetMuteState: Int, Error {
    case ok
    case chatNotFound
    case cantMute
    case unknown = -1
}

public enum ErrorSetSubscriptionState: Int, Error {
    case ok
    case chatNotFound
    case cantUnsubscribe
    case unknown = -1
}

// MARK: - Interceptors -

extension InterceptorFactory: Code_Chat_V1_ChatClientInterceptorFactoryProtocol {
    func makeStreamChatEventsInterceptors() -> [GRPC.ClientInterceptor<CodeAPI.Code_Chat_V1_StreamChatEventsRequest, CodeAPI.Code_Chat_V1_StreamChatEventsResponse>] {
        makeInterceptors()
    }
    
    func makeSendMessageInterceptors() -> [GRPC.ClientInterceptor<CodeAPI.Code_Chat_V1_SendMessageRequest, CodeAPI.Code_Chat_V1_SendMessageResponse>] {
        makeInterceptors()
    }
    
    func makeSetMuteStateInterceptors() -> [GRPC.ClientInterceptor<CodeAPI.Code_Chat_V1_SetMuteStateRequest, CodeAPI.Code_Chat_V1_SetMuteStateResponse>] {
        makeInterceptors()
    }
    
    func makeSetSubscriptionStateInterceptors() -> [GRPC.ClientInterceptor<CodeAPI.Code_Chat_V1_SetSubscriptionStateRequest, CodeAPI.Code_Chat_V1_SetSubscriptionStateResponse>] {
        makeInterceptors()
    }
    
    func makeGetChatsInterceptors() -> [GRPC.ClientInterceptor<CodeAPI.Code_Chat_V1_GetChatsRequest, CodeAPI.Code_Chat_V1_GetChatsResponse>] {
        makeInterceptors()
    }
    
    func makeGetMessagesInterceptors() -> [GRPC.ClientInterceptor<CodeAPI.Code_Chat_V1_GetMessagesRequest, CodeAPI.Code_Chat_V1_GetMessagesResponse>] {
        makeInterceptors()
    }
    
    func makeAdvancePointerInterceptors() -> [GRPC.ClientInterceptor<CodeAPI.Code_Chat_V1_AdvancePointerRequest, CodeAPI.Code_Chat_V1_AdvancePointerResponse>] {
        makeInterceptors()
    }
}

// MARK: - GRPCClientType -

extension Code_Chat_V1_ChatNIOClient: GRPCClientType {
    init(channel: GRPCChannel) {
        self.init(channel: channel, defaultCallOptions: CallOptions(), interceptors: InterceptorFactory())
    }
}
