//
//  ChatController.swift
//  Code
//
//  Created by Dima Bart on 2021-07-13.
//

import Foundation
import FlipchatServices
import SwiftData

@MainActor
class ChatController: ObservableObject {
    
    let owner: KeyPair
    
    private let userID: UserID
    private let client: FlipchatClient
    private let paymentClient: Client
    private let organizer: Organizer
    
    private let pageSize: Int = 100
    
    private var fetchInflight: Bool = false
    
    private var latestPointers: [ChatID: MessageID] = [:]
    
    private var chatStream: StreamChatsReference?
    
    private let modelContainer: ModelContainer
    
    // MARK: - Init -
    
    init(userID: UserID, client: FlipchatClient, paymentClient: Client, organizer: Organizer, modelContainer: ModelContainer) {
        self.userID    = userID
        self.client    = client
        self.paymentClient = paymentClient
        self.organizer = organizer
        self.owner     = organizer.ownerKeyPair
        self.modelContainer = modelContainer
        
        sync()
        fetchAndInsertSelf()
        streamChatEvents()
    }
    
    deinit {
        trace(.warning, components: "Deallocating ChatController.")
    }
    
    func prepareForLogout() {
        destroyChatStream()
        Task {
            try await withStore {
                try await $0.nuke()
            }
        }
    }
    
    private func withStore<T>(action: @escaping @Sendable (ChatStore) async throws -> T) async throws -> T where T: Sendable  {
        try await Task.detached { [modelContainer, userID, owner, client] in
            let store = await ChatStore(
                container: modelContainer,
                userID: userID,
                owner: owner,
                client: client
            )
            
            return try await action(store)
        }.value
    }
    
    // MARK: - Startup -
    
    private func sync() {
        Task {
            try await withStore {
                try await $0.sync()
            }
        }
    }
    
    private func fetchAndInsertSelf() {
        Task {
            try await withStore {
                try await $0.fetchAndInsertSelf()
            }
        }
    }
    
    // MARK: - Chat Stream -
    
    func streamChatEvents() {
        destroyChatStream()
        
        chatStream = client.streamChatEvents(owner: owner) { [weak self] result in
            switch result {
            case .success(let updates):
                Task {
                    try await self?.withStore {
                        try await $0.receive(updates: updates)
                    }
                }
                
            case .failure:
                self?.reconnectChatStream(after: 250)
            }
        }
    }
    
    private func reconnectChatStream(after milliseconds: Int) {
        Task {
            try await Task.delay(milliseconds: milliseconds)
            streamChatEvents()
        }
    }
    
    func destroyChatStream() {
        chatStream?.destroy()
    }
    
    // MARK: - Message Stream -
    
    func streamMessages(chatID: ChatID, messageID: MessageID?, completion: @escaping (Result<[Chat.Message], ErrorStreamMessages>) -> Void) -> StreamMessagesReference {
        client.streamMessages(chatID: chatID, from: messageID, owner: owner, completion: completion)
    }
    
    // MARK: - Messages -
    
    func receiveMessages(messages: [Chat.Message], for chatID: ChatID) async throws {
        try await withStore {
            try await $0.receive(messages: messages, for: chatID)
        }
    }
    
    func sendMessage(text: String, for chatID: ChatID) async throws {
        try await withStore {
            try await $0.sendMessage(text: text, for: chatID)
        }
    }
    
    func advanceReadPointerToLatest(for chatID: ChatID) async throws {
        try await withStore {
            try await $0.advanceReadPointerToLatest(for: chatID)
        }
    }
    
    // MARK: - Group Chat -
    
    func chatFor(roomNumber: RoomNumber) async throws -> ChatID? {
        try await withStore {
            guard let chatID = try await $0.fetchSingleChatID(roomNumber: roomNumber) else {
                return nil
            }
            
            return ChatID(uuid: chatID)
        }
    }
    
    func startGroupChat(amount: Kin, destination: PublicKey) async throws -> ChatID {
        let intentID = try await paymentClient.payForRoom(
            request: .create(userID, amount),
            organizer: organizer,
            destination: destination
        )
        
        return try await withStore {
            return try await $0.startGroupChat(intentID: intentID)
        }
    }
    
    func fetchGroupChat(roomNumber: RoomNumber) async throws -> (Chat.Metadata, [Chat.Member], Chat.Identity) {
        let description = try await client.fetchChat(
            for: .roomNumber(roomNumber),
            owner: owner
        )
        
        let host = Chat.Identity(
            displayName: (try? await client.fetchProfile(userID: description.metadata.ownerUser)) ?? "nobody",
            avatarURL: nil
        )        
        
        return (description.metadata, description.members, host)
    }
    
    func joinGroupChat(chatID: ChatID, hostID: UserID, amount: Kin) async throws -> ChatID {
        let destination = try await client.fetchPaymentDestination(userID: hostID)
        
        let intentID: PublicKey?
        
        // Paying yourself is a no-op
        if hostID != userID {
            intentID = try await paymentClient.payForRoom(
                request: .join(userID, amount, chatID),
                organizer: organizer,
                destination: destination
            )
        } else {
            intentID = nil
        }
        
        return try await withStore {
            try await $0.joinChat(chatID: chatID, intentID: intentID)
        }
    }
    
    func muteUser(userID: UserID, chatID: ChatID) async throws {
        try await client.muteUser(userID: userID, chatID: chatID, owner: owner)
    }
    
    func reportMessage(userID: UserID, messageID: MessageID) async throws {
        try await client.reportMessage(userID: userID, messageID: messageID, owner: owner)
    }
    
    func leaveChat(chatID: ChatID) async throws {
        try await withStore {
            try await $0.leaveChat(chatID: chatID)
        }
    }
    
    func changeCover(chatID: ChatID, newCover: Kin) async throws {
        try await withStore {
            try await $0.changeCover(chatID: chatID, newCover: newCover)
        }
    }
}

// MARK: - Mock -

extension ChatController {
    static let mock = ChatController(
        userID: .mock,
        client: .mock,
        paymentClient: .mock,
        organizer: .mock2,
        modelContainer: try! ModelContainer(for: pIdentity.self)
    )
}
