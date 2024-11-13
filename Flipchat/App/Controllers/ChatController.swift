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
    private let organizer: Organizer
    
    private let pageSize: Int = 100
    
    private var fetchInflight: Bool = false
    
    private var latestPointers: [ChatID: MessageID] = [:]
    
    private var chatStream: StreamChatsReference?
    
    private let chatStore: ChatStore
    
    // MARK: - Init -
    
    init(userID: UserID, client: FlipchatClient, organizer: Organizer) {
        self.userID    = userID
        self.client    = client
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
    
    deinit {
        trace(.warning, components: "Deallocating ChatController")
    }
    
    func prepareForLogout() {
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
    
    // MARK: - Group Chat -
    
    func startGroupChat() async throws -> ChatID {
        try await chatStore.startGroupChat()
    }
    
    func fetchGroupChat(roomNumber: RoomNumber, hide: Bool) async throws -> ChatID {
        try await chatStore.fetchChat(identifier: .roomNumber(roomNumber), hide: hide)
    }
    
    func joinGroupChat(roomNumber: RoomNumber) async throws -> ChatID {
        try await chatStore.joinChat(roomNumber: roomNumber)
    }
}

// MARK: - Mock -

extension ChatController {
    static let mock = ChatController(
        userID: .mock,
        client: .mock,
        organizer: .mock2
    )
}
