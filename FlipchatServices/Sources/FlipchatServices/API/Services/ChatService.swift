//
//  ChatService.swift
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
class ChatService: FlipchatService<Flipchat_Chat_V1_ChatNIOClient> {
        
    func streamChatEvents(owner: KeyPair, completion: @escaping (Result<[Chat.BatchUpdate], ErrorStreamChatEvents>) -> Void) -> StreamChatsReference {
        trace(.open, components: "Owner \(owner.publicKey.base58)", "Opening chat stream.")
        
        let streamReference = StreamChatsReference()
        streamReference.retain()
        
        streamReference.timeoutHandler = { [weak self, weak streamReference] in
            guard let streamReference else {
                return
            }
            
            trace(.warning, components: "Owner \(owner.publicKey.base58)", "Stream (chat) timed out")
            
            self?.streamChatEvents(
                owner: owner,
                assigningTo: streamReference,
                completion: completion
            )
        }
        
        streamChatEvents(
            owner: owner,
            assigningTo: streamReference,
            completion: completion
        )
        
        return streamReference
    }
    
    private func streamChatEvents(owner: KeyPair, assigningTo reference: StreamChatsReference, completion: @escaping (Result<[Chat.BatchUpdate], ErrorStreamChatEvents>) -> Void) {
        let queue = self.queue
        
        reference.cancel()
        reference.stream = service.streamChatEvents { [weak reference] response in
            
            guard let result = response.type else {
                trace(.failure, components: "Server sent empty message. This is unexpected.")
                return
            }
            
            switch result {
            case .events(let eventBatch):
                let updates = eventBatch.updates.compactMap { Chat.BatchUpdate($0) }
                queue.async {
                    trace(.receive, components: "Owner \(owner.publicKey.base58)", "Received \(updates.count) events.")
                    completion(.success(updates))
                }
                
            case .ping(let ping):
                guard let stream = reference?.stream else {
                    break
                }
                
                let request = Flipchat_Chat_V1_StreamChatEventsRequest.with {
                    $0.pong = .with {
                        $0.timestamp = Google_Protobuf_Timestamp(date: .now)
                    }
                }
                
                reference?.receivedPing(updatedTimeout: Int(ping.pingDelay.seconds))
                
                _ = stream.sendMessage(request)
                
            case .error(let streamError):
                let error = ErrorStreamChatEvents(rawValue: streamError.code.rawValue) ?? .unknown
                completion(.failure(error))
            }
        }
        
        reference.stream?.status.whenCompleteBlocking(onto: queue) { [weak self, weak reference] result in
            guard let self = self, let streamReference = reference else { return }
            
            if case .success(let status) = result, status.code == .unavailable {
                Task {
                    // Reconnect only if the stream was closed as a result of
                    // server actions and not cancelled by the client, etc.
                    trace(.note, components: "Owner \(owner.publicKey.base58)", "Reconnecting keepalive stream...")
                    await self.streamChatEvents(
                        owner: owner,
                        assigningTo: streamReference,
                        completion: completion
                    )
                }
            } else {
                trace(.warning, components: "Owner \(owner.publicKey.base58)", "Closing stream.")
            }
        }
        
        let request = Flipchat_Chat_V1_StreamChatEventsRequest.with {
            $0.params = .with {
                $0.ts = .init(date: .now)
                $0.auth = owner.authFor(message: $0)
            }
        }
        
        _ = reference.stream?.sendMessage(request)
        trace(.success, components: "Owner \(owner.publicKey.base58)", "Initiating a connection...")
    }
    
    func startGroupChat(with users: [UserID], owner: KeyPair, completion: @escaping (Result<Chat.Metadata, ErrorStartChat>) -> Void) {
        trace(.send, components: "Users: \(users.map { "\($0.description)" }.joined(separator: ", "))")
        
        let request = Flipchat_Chat_V1_StartChatRequest.with {
            $0.groupChat = .with {
                $0.users = users.map { userID in
                    .with {
                        $0.value = userID.data
                    }
                }
            }
            
            $0.auth = owner.authFor(message: $0)
        }
        
        let call = service.startChat(request)
        
        call.handle(on: queue) { response in
            let error = ErrorStartChat(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                let chatMetadata = Chat.Metadata(response.chat)
                trace(.success, components: "Owner: \(owner.publicKey.base58)", "Chat: \(chatMetadata.id.description)")
                completion(.success(chatMetadata))
            } else {
                trace(.failure, components: "Error: \(error)")
                completion(.failure(error))
            }
            
        } failure: { error in
            completion(.failure(.unknown))
        }
    }
    
    func joinGroupChat(chatID: ChatID, intentID: PublicKey, owner: KeyPair, completion: @escaping (Result<(Chat.Metadata, [Chat.Member]), ErrorJoinChat>) -> Void) {
        trace(.send, components: "Chat ID: \(chatID.description)", "Intent: \(intentID.base58)", "Signed by: \(owner.publicKey.base58)")
        
        let request = Flipchat_Chat_V1_JoinChatRequest.with {
            $0.chatID = .with { $0.value = chatID.data }
            $0.paymentIntent = .with { $0.value = intentID.data }
            $0.auth = owner.authFor(message: $0)
        }
        
        let call = service.joinChat(request)
        
        call.handle(on: queue) { response in
            let error = ErrorJoinChat(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                let chat = Chat.Metadata(response.metadata)
                let members = response.members.map { Chat.Member($0) }
                trace(.success, components: "Owner: \(owner.publicKey.base58)", "Chat: \(chat.id.description)")
                completion(.success((chat, members)))
            } else {
                trace(.failure, components: "Error: \(error)")
                completion(.failure(error))
            }
            
        } failure: { error in
            completion(.failure(.unknown))
        }
    }
    
    func fetchChats(owner: KeyPair, query: PageQuery, completion: @escaping (Result<[Chat.Metadata], ErrorFetchChats>) -> Void) {
        trace(.send, components: "Owner: \(owner.publicKey.base58)", "Query: \(query.description)")
        
        let request = Flipchat_Chat_V1_GetChatsRequest.with {
            $0.queryOptions = query.protoQueryOptions
            $0.auth = owner.authFor(message: $0)
        }
        
        let call = service.getChats(request)
        
        call.handle(on: queue) { response in
            let error = ErrorFetchChats(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                trace(.success, components: "Owner: \(owner.publicKey.base58)", "Chats: \(response.chats.count)")
                let chats = response.chats.map { Chat.Metadata($0) }
                completion(.success(chats))
            } else {
                trace(.success, components: "Error: \(error)")
                completion(.failure(error))
            }
            
        } failure: { error in
            completion(.failure(.unknown))
        }
    }
    
    func fetchChat(for identifier: ChatIdentifier, owner: KeyPair, completion: @escaping (Result<(Chat.Metadata, [Chat.Member]), ErrorFetchChat>) -> Void) {
        trace(.send, components: "ID: \(identifier)")
        
        let request = Flipchat_Chat_V1_GetChatRequest.with {
            $0.identifier = identifier.protoIdentifier
            $0.auth = owner.authFor(message: $0)
        }
        
        let call = service.getChat(request)
        
        call.handle(on: queue) { response in
            let error = ErrorFetchChat(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                trace(.success, components: "ID: \(identifier)")
                let chat = Chat.Metadata(response.metadata)
                let members = response.members.map { Chat.Member($0) }
                completion(.success((chat, members)))
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

public enum ChatIdentifier {
    
    case chatID(ChatID)
    case roomNumber(RoomNumber)
    
    var protoIdentifier: Flipchat_Chat_V1_GetChatRequest.OneOf_Identifier {
        switch self {
        case .chatID(let chatID):
            return .chatID(.with { $0.value = chatID.data })
            
        case .roomNumber(let roomNumber):
            return .roomNumber(roomNumber)
        }
    }
}

public typealias RoomNumber = UInt64

extension RoomNumber {
    public var roomString: String {
        "#\(self)"
    }
}

//// MARK: - Errors -

public enum ErrorStreamChatEvents: Int, Error {
    case ok
    case denied
    case unknown = -1
}

public enum ErrorStartChat: Int, Error {
    case ok
    
    /// DENIED indicates the caller is not allowed to start/join the chat
    case denied
    
    /// USER_NOT_FOUND indicates that (one of) the target user's was not found
    case userNotFound
    
    case unknown = -1
}

public enum ErrorJoinChat: Int, Error {
    case ok
    case denied
    case unknown = -1
}

public enum ErrorFetchChats: Int, Error {
    case ok
    case unknown = -1
}

public enum ErrorFetchChat: Int, Error {
    case ok
    case notFound
    case unknown = -1
}

// MARK: - Interceptors -

extension InterceptorFactory: Flipchat_Chat_V1_ChatClientInterceptorFactoryProtocol {
    func makeStreamChatEventsInterceptors() -> [GRPC.ClientInterceptor<FlipchatAPI.Flipchat_Chat_V1_StreamChatEventsRequest, FlipchatAPI.Flipchat_Chat_V1_StreamChatEventsResponse>] {
        makeInterceptors()
    }
    
    func makeGetChatsInterceptors() -> [GRPC.ClientInterceptor<FlipchatAPI.Flipchat_Chat_V1_GetChatsRequest, FlipchatAPI.Flipchat_Chat_V1_GetChatsResponse>] {
        makeInterceptors()
    }
    
    func makeGetChatInterceptors() -> [GRPC.ClientInterceptor<FlipchatAPI.Flipchat_Chat_V1_GetChatRequest, FlipchatAPI.Flipchat_Chat_V1_GetChatResponse>] {
        makeInterceptors()
    }
    
    func makeStartChatInterceptors() -> [GRPC.ClientInterceptor<FlipchatAPI.Flipchat_Chat_V1_StartChatRequest, FlipchatAPI.Flipchat_Chat_V1_StartChatResponse>] {
        makeInterceptors()
    }
    
    func makeJoinChatInterceptors() -> [GRPC.ClientInterceptor<FlipchatAPI.Flipchat_Chat_V1_JoinChatRequest, FlipchatAPI.Flipchat_Chat_V1_JoinChatResponse>] {
        makeInterceptors()
    }
    
    func makeLeaveChatInterceptors() -> [GRPC.ClientInterceptor<FlipchatAPI.Flipchat_Chat_V1_LeaveChatRequest, FlipchatAPI.Flipchat_Chat_V1_LeaveChatResponse>] {
        makeInterceptors()
    }
    
    func makeSetMuteStateInterceptors() -> [GRPC.ClientInterceptor<FlipchatAPI.Flipchat_Chat_V1_SetMuteStateRequest, FlipchatAPI.Flipchat_Chat_V1_SetMuteStateResponse>] {
        makeInterceptors()
    }
}

// MARK: - GRPCClientType -

extension Flipchat_Chat_V1_ChatNIOClient: GRPCClientType {
    init(channel: GRPCChannel) {
        self.init(channel: channel, defaultCallOptions: CallOptions(), interceptors: InterceptorFactory())
    }
}
