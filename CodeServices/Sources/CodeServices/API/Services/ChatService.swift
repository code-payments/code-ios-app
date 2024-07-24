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

class ChatService: CodeService<Code_Chat_V2_ChatNIOClient> {
        
    func openChatStream(chatID: ChatID, memberID: MemberID, owner: KeyPair, completion: @escaping (Result<[Chat.Event], ErrorOpenChatStream>) -> Void) -> ChatMessageStreamReference {
        trace(.open, components: "Chat \(chatID.description)", "Opening stream.")
        
        let streamReference = ChatMessageStreamReference()
        streamReference.retain()
        
        streamReference.timeoutHandler = { [weak self, weak streamReference] in
            guard let streamReference else {
                return
            }
            
            trace(.warning, components: "Chat \(chatID.description)", "Stream timed out")
            
            self?.openChatStream(
                chatID: chatID,
                memberID: memberID,
                owner: owner,
                assigningTo: streamReference,
                completion: completion
            )
        }
        
        openChatStream(
            chatID: chatID,
            memberID: memberID,
            owner: owner,
            assigningTo: streamReference,
            completion: completion
        )
        
        return streamReference
    }
    
    private func openChatStream(chatID: ChatID, memberID: MemberID, owner: KeyPair, assigningTo reference: ChatMessageStreamReference, completion: @escaping (Result<[Chat.Event], ErrorOpenChatStream>) -> Void) {
        let queue = self.queue
        
        reference.cancel()
        reference.stream = service.streamChatEvents { [weak reference] response in
            
            guard let result = response.type else {
                trace(.failure, components: "Chat \(chatID.description)]", "Server sent empty message. This is unexpected.")
                return
            }
            
            switch result {
            case .events(let eventBatch):
                
                let events = eventBatch.events.compactMap { Chat.Event($0) }
                queue.async {
//                    trace(.receive, components: "Chat \(chatID.description)", "Received \(events.count) events.")
                    completion(.success(events))
                }
                
            case .ping(let ping):
                guard let stream = reference?.stream else {
                    break
                }
                
                let request = Code_Chat_V2_StreamChatEventsRequest.with {
                    $0.type = .pong(.with {
                        $0.timestamp = Google_Protobuf_Timestamp(date: .now())
                    })
                }
                
                reference?.receivedPing(updatedTimeout: Int(ping.pingDelay.seconds))
                
                _ = stream.sendMessage(request)
//                trace(.receive, components: "Pong", "Chat \(chatID.description)", "Server timestamp: \(ping.timestamp.date)")
                
                // TODO: Handle message sent
                
                break
                
            case .error(let streamError):
                let error = ErrorOpenChatStream(rawValue: streamError.code.rawValue) ?? .unknown
                completion(.failure(error))
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
                    memberID: memberID,
                    owner: owner,
                    assigningTo: streamReference,
                    completion: completion
                )
            } else {
                trace(.warning, components: "Chat \(chatID.description)", "Closing stream.")
            }
        }
        
        let request = Code_Chat_V2_StreamChatEventsRequest.with {
            $0.openStream = .with {
                $0.chatID    = .with { $0.value = chatID.data }
                $0.memberID  = .with { $0.value = memberID.data }
                $0.owner     = owner.publicKey.codeAccountID
                $0.signature = $0.sign(with: owner)
            }
        }
        
        _ = reference.stream?.sendMessage(request)
        trace(.success, components: "Chat \(chatID.description)]", "Initiating a connection...")
    }
    
    func startChat(owner: KeyPair, tipIntentID: PublicKey, completion: @escaping (Result<Chat, ErrorStartChat>) -> Void) {
        trace(.send, components: "Owner: \(owner.publicKey.base58)")
        
        let request = Code_Chat_V2_StartChatRequest.with {
            $0.owner = owner.publicKey.codeAccountID
            $0.tipChat = .with {
                $0.intentID = tipIntentID.codeIntentID
            }
            $0.signature = $0.sign(with: owner)
        }
        
        let call = service.startChat(request)
        
        call.handle(on: queue) { response in
            let error = ErrorStartChat(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                DispatchQueue.main.async {
                    let chat = Chat(response.chat)
                    trace(.success, components: "Owner: \(owner.publicKey.base58)", "Chat: \(chat.id.data.hexEncodedString())")
                    completion(.success(chat))
                }
            } else {
                trace(.success, components: "Error: \(error)")
                completion(.failure(error))
            }
            
        } failure: { error in
            completion(.failure(.unknown))
        }
    }
    
    func sendMessage(chatID: ChatID, memberID: MemberID, owner: KeyPair, content: Chat.Content, completion: @escaping (Result<Chat.Message, ErrorSendMessage>) -> Void) {
        trace(.send, components: "Owner: \(owner.publicKey.base58)")
        
        let request = Code_Chat_V2_SendMessageRequest.with {
            $0.chatID    = .with { $0.value = chatID.data }
            $0.memberID  = .with { $0.value = memberID.data }
            $0.content   = [content.codeContent]
            $0.owner     = owner.publicKey.codeAccountID
            $0.signature = $0.sign(with: owner)
        }
        
        let call = service.sendMessage(request)
        
        call.handle(on: queue) { response in
            let error = ErrorSendMessage(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                DispatchQueue.main.async {
                    let message = Chat.Message(response.message)
                    trace(.success, components: "Owner: \(owner.publicKey.base58)", "Message: \(message.id.data.hexEncodedString())")
                    completion(.success(message))
                }
            } else {
                trace(.success, components: "Error: \(error)")
                completion(.failure(error))
            }
            
        } failure: { error in
            completion(.failure(.unknown))
        }
    }
    
    func revealIdentity(chatID: ChatID, memberID: MemberID, twitterUsername: String, owner: KeyPair, completion: @escaping (Result<Chat.Message, ErrorRevealIdentity>) -> Void) {
        trace(.send, components: "Owner: \(owner.publicKey.base58)")
        
        let request = Code_Chat_V2_RevealIdentityRequest.with {
            $0.chatID    = .with { $0.value = chatID.data }
            $0.memberID  = .with { $0.value = memberID.data }
            $0.identity  = .with { $0.platform = .twitter; $0.username = twitterUsername }
            $0.owner     = owner.publicKey.codeAccountID
            $0.signature = $0.sign(with: owner)
        }
        
        let call = service.revealIdentity(request)
        
        call.handle(on: queue) { response in
            let error = ErrorRevealIdentity(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                DispatchQueue.main.async {
                    let message = Chat.Message(response.message)
                    trace(.success, components: "Owner: \(owner.publicKey.base58)", "Message: \(message.id.data.hexEncodedString())")
                    completion(.success(message))
                }
            } else {
                trace(.success, components: "Error: \(error)")
                completion(.failure(error))
            }
            
        } failure: { error in
            completion(.failure(.unknown))
        }
    }
    
    func fetchChats(owner: KeyPair, completion: @escaping (Result<[Chat], ErrorFetchChats>) -> Void) {
//        trace(.send, components: "Owner: \(owner.publicKey.base58)")
        
        let request = Code_Chat_V2_GetChatsRequest.with {
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
    
    func fetchMessages(chatID: ChatID, memberID: MemberID, owner: KeyPair, direction: MessageDirection, pageSize: Int, completion: @escaping (Result<[Chat.Message], ErrorFetchMessages>) -> Void) {
//        trace(.send, components: "Owner: \(owner.publicKey.base58)", "Chat ID: \(chatID.data.hexEncodedString())", "Page size: \(pageSize)")
        
        let request = Code_Chat_V2_GetMessagesRequest.with {
            $0.chatID   = .with { $0.value = chatID.data }
            $0.memberID = .with { $0.value = memberID.data }
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
    
    func advancePointer(chatID: ChatID, to messageID: MessageID, memberID: MemberID, owner: KeyPair, completion: @escaping (Result<Void, ErrorAdvancePointer>) -> Void) {
        trace(.send, components: "Owner: \(owner.publicKey.base58)", "Chat ID: \(chatID.data.hexEncodedString())")
        
        let request = Code_Chat_V2_AdvancePointerRequest.with {
            $0.chatID = .with { $0.value = chatID.data }
            $0.pointer = Code_Chat_V2_Pointer.with {
                $0.type = .read
                $0.value = .with { $0.value = messageID.data }
                $0.memberID = .with { $0.value = memberID.data }
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
    
    func setMuteState(chatID: ChatID, muted: Bool, owner: KeyPair, completion: @escaping (Result<Void, ErrorSetMuteState>) -> Void) {
        trace(.send, components: "Chat ID: \(chatID.data.hexEncodedString())")
        
        let request = Code_Chat_V2_SetMuteStateRequest.with {
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
    
    func setSubscriptionState(chatID: ChatID, subscribed: Bool, owner: KeyPair, completion: @escaping (Result<Void, ErrorSetSubscriptionState>) -> Void) {
        trace(.send, components: "Chat ID: \(chatID.data.hexEncodedString())")
        
        let request = Code_Chat_V2_SetSubscriptionStateRequest.with {
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
    case ascending(from: MessageID?)
    case descending(upTo: MessageID?)
}

// MARK: - Errors -

public enum ErrorOpenChatStream: Int, Error {
    case denied
    case chatNotFound
    case unknown = -1
}

public enum ErrorStartChat: Int, Error {
    case ok
    case denied
    case invalidParameter
    case unknown = -1
}

public enum ErrorSendMessage: Int, Error {
    case ok
    case denied
    case chatNotFound
    case invalidChatType
    case invalidContentType
    case unknown = -1
}

public enum ErrorRevealIdentity: Int, Error {
    case ok
    case denied
    case chatNotFound
    case differentIdentityRevealed
    case unknown = -1
}

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

extension InterceptorFactory: Code_Chat_V2_ChatClientInterceptorFactoryProtocol {
    func makeStartChatInterceptors() -> [GRPC.ClientInterceptor<CodeAPI.Code_Chat_V2_StartChatRequest, CodeAPI.Code_Chat_V2_StartChatResponse>] {
        makeInterceptors()
    }
    
    func makeRevealIdentityInterceptors() -> [GRPC.ClientInterceptor<CodeAPI.Code_Chat_V2_RevealIdentityRequest, CodeAPI.Code_Chat_V2_RevealIdentityResponse>] {
        makeInterceptors()
    }
    
    func makeStreamChatEventsInterceptors() -> [GRPC.ClientInterceptor<CodeAPI.Code_Chat_V2_StreamChatEventsRequest, CodeAPI.Code_Chat_V2_StreamChatEventsResponse>] {
        makeInterceptors()
    }
    
    func makeSendMessageInterceptors() -> [GRPC.ClientInterceptor<CodeAPI.Code_Chat_V2_SendMessageRequest, CodeAPI.Code_Chat_V2_SendMessageResponse>] {
        makeInterceptors()
    }
    
    func makeSetMuteStateInterceptors() -> [GRPC.ClientInterceptor<CodeAPI.Code_Chat_V2_SetMuteStateRequest, CodeAPI.Code_Chat_V2_SetMuteStateResponse>] {
        makeInterceptors()
    }
    
    func makeSetSubscriptionStateInterceptors() -> [GRPC.ClientInterceptor<CodeAPI.Code_Chat_V2_SetSubscriptionStateRequest, CodeAPI.Code_Chat_V2_SetSubscriptionStateResponse>] {
        makeInterceptors()
    }
    
    func makeGetChatsInterceptors() -> [GRPC.ClientInterceptor<CodeAPI.Code_Chat_V2_GetChatsRequest, CodeAPI.Code_Chat_V2_GetChatsResponse>] {
        makeInterceptors()
    }
    
    func makeGetMessagesInterceptors() -> [GRPC.ClientInterceptor<CodeAPI.Code_Chat_V2_GetMessagesRequest, CodeAPI.Code_Chat_V2_GetMessagesResponse>] {
        makeInterceptors()
    }
    
    func makeAdvancePointerInterceptors() -> [GRPC.ClientInterceptor<CodeAPI.Code_Chat_V2_AdvancePointerRequest, CodeAPI.Code_Chat_V2_AdvancePointerResponse>] {
        makeInterceptors()
    }
}

// MARK: - GRPCClientType -

extension Code_Chat_V2_ChatNIOClient: GRPCClientType {
    init(channel: GRPCChannel) {
        self.init(channel: channel, defaultCallOptions: CallOptions(), interceptors: InterceptorFactory())
    }
}
