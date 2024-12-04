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
//                    trace(.receive, components: "Owner \(owner.publicKey.base58)", "Received \(updates.count) events.")
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
                queue.async {
                    let error = ErrorStreamChatEvents(rawValue: streamError.code.rawValue) ?? .unknown
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
    
    func startGroupChat(with users: [UserID], intentID: PublicKey, owner: KeyPair, completion: @escaping (Result<ChatDescription, ErrorStartChat>) -> Void) {
        trace(.send, components: "Users: \(users.map { "\($0.description)" }.joined(separator: ", "))")
        
        let request = Flipchat_Chat_V1_StartChatRequest.with {
            $0.groupChat = .with {
                $0.paymentIntent = .with { $0.value = intentID.data }
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
                let description = ChatDescription(
                    metadata: Chat.Metadata(response.chat),
                    members: response.members.map { Chat.Member($0) }
                )
                trace(.success, components: "Owner: \(owner.publicKey.base58)", "Chat: \(description.metadata.id.description)")
                completion(.success(description))
            } else {
                trace(.failure, components: "Error: \(error)")
                completion(.failure(error))
            }
            
        } failure: { error in
            completion(.failure(.unknown))
        }
    }
    
    func joinGroupChat(chatID: ChatID, intentID: PublicKey?, owner: KeyPair, completion: @escaping (Result<ChatDescription, ErrorJoinChat>) -> Void) {
        trace(.send, components: "Chat ID: \(chatID.description)", "Intent: \(intentID?.base58 ?? "nil")")
        
        let request = Flipchat_Chat_V1_JoinChatRequest.with {
            $0.chatID = .with { $0.value = chatID.data }
            if let intentID {
                $0.paymentIntent = .with { $0.value = intentID.data }
            }
            $0.auth = owner.authFor(message: $0)
        }
        
        let call = service.joinChat(request)
        
        call.handle(on: queue) { response in
            let error = ErrorJoinChat(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                let description = ChatDescription(
                    metadata: Chat.Metadata(response.metadata),
                    members: response.members.map { Chat.Member($0) }
                )
                trace(.success, components: "Owner: \(owner.publicKey.base58)", "Chat: \(description.metadata.id.description)")
                completion(.success(description))
            } else {
                trace(.failure, components: "Error: \(error)")
                completion(.failure(error))
            }
            
        } failure: { error in
            completion(.failure(.unknown))
        }
    }
    
    func leaveChat(chatID: ChatID, owner: KeyPair, completion: @escaping (Result<(), ErrorLeaveChat>) -> Void) {
        trace(.send, components: "Chat ID: \(chatID.description)")
        
        let request = Flipchat_Chat_V1_LeaveChatRequest.with {
            $0.chatID = .with { $0.value = chatID.data }
            $0.auth = owner.authFor(message: $0)
        }
        
        let call = service.leaveChat(request)
        
        call.handle(on: queue) { response in
            let error = ErrorLeaveChat(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                trace(.success)
                completion(.success(()))
            } else {
                trace(.failure, components: "Error: \(error)")
                completion(.failure(error))
            }
            
        } failure: { error in
            completion(.failure(.unknown))
        }
    }
    
    func removeUser(userID: UserID, chatID: ChatID, owner: KeyPair, completion: @escaping (Result<(), ErrorRemoveUser>) -> Void) {
        trace(.send, components: "User ID: \(userID.description)")
        
        let request = Flipchat_Chat_V1_RemoveUserRequest.with {
            $0.userID = .with { $0.value = userID.data }
            $0.chatID = .with { $0.value = chatID.data }
            $0.auth = owner.authFor(message: $0)
        }
        
        let call = service.removeUser(request)
        
        call.handle(on: queue) { response in
            let error = ErrorRemoveUser(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                trace(.success)
                completion(.success(()))
            } else {
                trace(.failure, components: "Error: \(error)")
                completion(.failure(error))
            }
            
        } failure: { error in
            completion(.failure(.unknown))
        }
    }
    
    func reportMessage(userID: UserID, messageID: MessageID, owner: KeyPair, completion: @escaping (Result<(), ErrorReportUser>) -> Void) {
        trace(.send, components: "User ID: \(userID.description)", "Message ID: \(messageID.description)")
        
        let request = Flipchat_Chat_V1_ReportUserRequest.with {
            $0.userID = .with { $0.value = userID.data }
            $0.messageID = .with { $0.value = messageID.data }
            $0.auth = owner.authFor(message: $0)
        }
        
        let call = service.reportUser(request)
        
        call.handle(on: queue) { response in
            let error = ErrorReportUser(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                trace(.success)
                completion(.success(()))
            } else {
                trace(.failure, components: "Error: \(error)")
                completion(.failure(error))
            }
            
        } failure: { error in
            completion(.failure(.unknown))
        }
    }
    
    func muteUser(userID: UserID, chatID: ChatID, owner: KeyPair, completion: @escaping (Result<(), ErrorMuteUser>) -> Void) {
        trace(.send, components: "User ID: \(userID.description)")
        
        let request = Flipchat_Chat_V1_MuteUserRequest.with {
            $0.userID = .with { $0.value = userID.data }
            $0.chatID = .with { $0.value = chatID.data }
            $0.auth = owner.authFor(message: $0)
        }
        
        let call = service.muteUser(request)
        
        call.handle(on: queue) { response in
            let error = ErrorMuteUser(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                trace(.success)
                completion(.success(()))
            } else {
                trace(.failure, components: "Error: \(error)")
                completion(.failure(error))
            }
            
        } failure: { error in
            completion(.failure(.unknown))
        }
    }
    
    func muteChat(chatID: ChatID, muted: Bool, owner: KeyPair, completion: @escaping (Result<(), ErrorMuteChat>) -> Void) {
        trace(.send, components: "Chat ID: \(chatID.uuid.uuidString)", "Muted: \(muted ? "yes" : "no")")
        
        if muted {
            let request = Flipchat_Chat_V1_MuteChatRequest.with {
                $0.chatID = .with { $0.value = chatID.data }
                $0.auth = owner.authFor(message: $0)
            }
            
            let call = service.muteChat(request)
            
            call.handle(on: queue) { response in
                let error = ErrorMuteChat(rawValue: response.result.rawValue) ?? .unknown
                if error == .ok {
                    trace(.success)
                    completion(.success(()))
                } else {
                    trace(.failure, components: "Error: \(error)")
                    completion(.failure(error))
                }
                
            } failure: { error in
                completion(.failure(.unknown))
            }
            
        } else {
            let request = Flipchat_Chat_V1_UnmuteChatRequest.with {
                $0.chatID = .with { $0.value = chatID.data }
                $0.auth = owner.authFor(message: $0)
            }
            
            let call = service.unmuteChat(request)
            
            call.handle(on: queue) { response in
                let error = ErrorMuteChat(rawValue: response.result.rawValue) ?? .unknown
                if error == .ok {
                    trace(.success)
                    completion(.success(()))
                } else {
                    trace(.failure, components: "Error: \(error)")
                    completion(.failure(error))
                }
                
            } failure: { error in
                completion(.failure(.unknown))
            }
        }
    }
    
    func fetchChats(owner: KeyPair, completion: @escaping (Result<[Chat.Metadata], ErrorFetchChats>) -> Void) {
        trace(.send, components: "Owner: \(owner.publicKey.base58)")
        
        let request = Flipchat_Chat_V1_GetChatsRequest.with {
            $0.queryOptions = PageQuery(
                order: .desc,
                pagingToken: nil,
                pageSize: 1024
            ).protoQueryOptions
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
    
    func fetchChat(for identifier: ChatIdentifier, owner: KeyPair, completion: @escaping (Result<ChatDescription, ErrorFetchChat>) -> Void) {
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
                let description = ChatDescription(
                    metadata: Chat.Metadata(response.metadata),
                    members: response.members.map { Chat.Member($0) }
                )
                completion(.success(description))
            } else {
                trace(.success, components: "Error: \(error)")
                completion(.failure(error))
            }
            
        } failure: { error in
            completion(.failure(.unknown))
        }
    }
    
    func changeCover(chatID: ChatID, newCover: Kin, owner: KeyPair, completion: @escaping (Result<(), ErrorChangeCover>) -> Void) {
        trace(.send, components: "Chat ID: \(chatID.description)", "Cover: \(newCover.description)")
        
        let request = Flipchat_Chat_V1_SetCoverChargeRequest.with {
            $0.chatID = .with { $0.value = chatID.data }
            $0.coverCharge = .with { $0.quarks = newCover.quarks }
            $0.auth = owner.authFor(message: $0)
        }
        
        let call = service.setCoverCharge(request)
        
        call.handle(on: queue) { response in
            let error = ErrorChangeCover(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                trace(.success)
                completion(.success(()))
            } else {
                trace(.failure, components: "Error: \(error)")
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

public struct ChatDescription: Sendable {
    public let metadata: Chat.Metadata
    public let members: [Chat.Member]
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

public enum ErrorLeaveChat: Int, Error {
    case ok
    case unknown = -1
}

public enum ErrorRemoveUser: Int, Error {
    case ok
    case denied
    case unknown = -1
}

public enum ErrorReportUser: Int, Error {
    case ok
    case unknown = -1
}

public enum ErrorMuteUser: Int, Error {
    case ok
    case denied
    case unknown = -1
}

public enum ErrorMuteChat: Int, Error {
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

public enum ErrorChangeCover: Int, Error {
    case ok
    case denied
    case cantSet
    case unknown = -1
}

// MARK: - Interceptors -

extension InterceptorFactory: Flipchat_Chat_V1_ChatClientInterceptorFactoryProtocol {
    func makeMuteChatInterceptors() -> [GRPC.ClientInterceptor<FlipchatAPI.Flipchat_Chat_V1_MuteChatRequest, FlipchatAPI.Flipchat_Chat_V1_MuteChatResponse>] {
        makeInterceptors()
    }
    
    func makeUnmuteChatInterceptors() -> [GRPC.ClientInterceptor<FlipchatAPI.Flipchat_Chat_V1_UnmuteChatRequest, FlipchatAPI.Flipchat_Chat_V1_UnmuteChatResponse>] {
        makeInterceptors()
    }
    
    func makeMuteUserInterceptors() -> [GRPC.ClientInterceptor<FlipchatAPI.Flipchat_Chat_V1_MuteUserRequest, FlipchatAPI.Flipchat_Chat_V1_MuteUserResponse>] {
        makeInterceptors()
    }
    
    func makeReportUserInterceptors() -> [GRPC.ClientInterceptor<FlipchatAPI.Flipchat_Chat_V1_ReportUserRequest, FlipchatAPI.Flipchat_Chat_V1_ReportUserResponse>] {
        makeInterceptors()
    }
    
    func makeRemoveUserInterceptors() -> [GRPC.ClientInterceptor<FlipchatAPI.Flipchat_Chat_V1_RemoveUserRequest, FlipchatAPI.Flipchat_Chat_V1_RemoveUserResponse>] {
        makeInterceptors()
    }
    
    func makeSetCoverChargeInterceptors() -> [GRPC.ClientInterceptor<FlipchatAPI.Flipchat_Chat_V1_SetCoverChargeRequest, FlipchatAPI.Flipchat_Chat_V1_SetCoverChargeResponse>] {
        makeInterceptors()
    }
    
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
}

// MARK: - GRPCClientType -

extension Flipchat_Chat_V1_ChatNIOClient: GRPCClientType {
    init(channel: GRPCChannel) {
        self.init(channel: channel, defaultCallOptions: CallOptions(), interceptors: InterceptorFactory())
    }
}
