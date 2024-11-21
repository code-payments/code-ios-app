//
//  ChatController.swift
//  Code
//
//  Created by Dima Bart on 2021-07-13.
//

import Foundation
import FlipchatServices

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
    
    private let chatStore: ChatStore
    
    // MARK: - Init -
    
    init(userID: UserID, client: FlipchatClient, paymentClient: Client, organizer: Organizer) {
        self.userID    = userID
        self.client    = client
        self.paymentClient = paymentClient
        self.organizer = organizer
        self.owner     = organizer.ownerKeyPair
        self.chatStore = ChatStore(
            userID: userID,
            owner: owner,
            client: client
        )
        
        chatStore.sync()
        
        streamChatEvents()
    }
    
    func prepareForLogout() {
        destroyChatStream()
        try? chatStore.nuke()
    }
    
    // MARK: - Chat Stream -
    
    private func streamChatEvents() {
        destroyChatStream()
        
        chatStream = client.streamChatEvents(owner: owner) { [weak self] result in
            switch result {
            case .success(let updates):
                try? self?.chatStore.receive(updates: updates)
                
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
    
    private func destroyChatStream() {
        chatStream?.destroy()
    }
    
    // MARK: - Message Stream -
    
    func streamMessages(chatID: ChatID, messageID: MessageID?, completion: @escaping (Result<[Chat.Message], ErrorStreamMessages>) -> Void) -> StreamMessagesReference {
        client.streamMessages(chatID: chatID, from: messageID, owner: owner, completion: completion)
    }
    
    // MARK: - Messages -
    
    func receiveMessages(messages: [Chat.Message], for chatID: ChatID) throws {
        try chatStore.receive(messages: messages, for: chatID)
    }
    
    func sendMessage(text: String, for chatID: ChatID) async throws {
        try await chatStore.sendMessage(text: text, for: chatID)
    }
    
    func advanceReadPointerToLatest(for chatID: ChatID) async throws {
        try await chatStore.advanceReadPointerToLatest(for: chatID)
    }
    
    // MARK: - Group Chat -
    
    func chatFor(roomNumber: RoomNumber) throws -> ChatID? {
        guard let chat = try chatStore.fetchSingleChat(roomNumber: roomNumber) else {
            return nil
        }
        
        return ChatID(data: chat.serverID)
    }
    
    func startGroupChat(amount: Kin, destination: PublicKey) async throws -> ChatID {
        let intentID = try await paymentClient.payForRoom(
            request: .create(userID, amount),
            organizer: organizer,
            destination: destination
        )
        
        return try await chatStore.startGroupChat(intentID: intentID)
    }
    
    func fetchGroupChat(roomNumber: RoomNumber) async throws -> (Chat.Metadata, [Chat.Member]) {
        try await client.fetchChat(
            for: .roomNumber(roomNumber),
            owner: owner
        )
    }
    
    func joinGroupChat(chatID: ChatID, hostID: UserID, amount: Kin) async throws -> ChatID {
        let destination = try await client.fetchPaymentDestination(userID: hostID)
        
        var intentID: PublicKey?
        
        // Paying yourself is a no-op
        if hostID != userID {
            intentID = try await paymentClient.payForRoom(
                request: .join(userID, amount, chatID),
                organizer: organizer,
                destination: destination
            )
        }
        
        return try await chatStore.joinChat(
            chatID: chatID,
            intentID: intentID
        )
    }
    
    func removeUser(userID: UserID, chatID: ChatID) async throws {
        try await client.removeUser(userID: userID, chatID: chatID, owner: owner)
    }
    
    func reportMessage(userID: UserID, messageID: MessageID) async throws {
        try await client.reportMessage(userID: userID, messageID: messageID, owner: owner)
    }
    
    func leaveChat(chatID: ChatID) async throws {
        try await chatStore.leaveChat(chatID: chatID)
    }
    
    func changeCover(chatID: ChatID, newCover: Kin) async throws {
        try await chatStore.changeCover(chatID: chatID, newCover: newCover)
    }
}

// MARK: - Mock -

extension ChatController {
    static let mock = ChatController(
        userID: .mock,
        client: .mock,
        paymentClient: .mock,
        organizer: .mock2
    )
}
