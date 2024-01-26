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

class ChatService: CodeService<Code_Chat_V1_ChatNIOClient> {
    
    func fetchChats(owner: KeyPair, completion: @escaping (Result<[Chat], ErrorFetchChats>) -> Void) {
        trace(.send, components: "Owner: \(owner.publicKey.base58)")
        
        let request = Code_Chat_V1_GetChatsRequest.with {
            $0.owner = owner.publicKey.codeAccountID
            $0.signature = $0.sign(with: owner)
        }
        
        let call = service.getChats(request)
        
        call.handle(on: queue) { response in
            let error = ErrorFetchChats(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                let chats = response.chats.map { Chat($0) }
                trace(.success, components: "Owner: \(owner.publicKey.base58)", "Chats: \(chats.count)")
                completion(.success(chats))
            } else {
                trace(.success, components: "Error: \(error)")
                completion(.failure(error))
            }
            
        } failure: { error in
            completion(.failure(.unknown))
        }
    }
    
    func fetchMessages(chatID: ID, owner: KeyPair, direction: MessageDirection, pageSize: Int, completion: @escaping (Result<[Chat.Message], ErrorFetchMessages>) -> Void) {
        trace(.send, components: "Owner: \(owner.publicKey.base58)", "Chat ID: \(chatID.data.hexEncodedString())", "Page size: \(pageSize)")
        
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
            if error == .ok {
                let messages = response.messages.map { Chat.Message($0) }
                trace(.success, components: "Owner: \(owner.publicKey.base58)", "Messages: \(messages.count)")
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

// MARK: - Interceptors -

extension InterceptorFactory: Code_Chat_V1_ChatClientInterceptorFactoryProtocol {
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
