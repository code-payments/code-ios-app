//
//  ChatController.swift
//  Code
//
//  Created by Dima Bart on 2021-07-13.
//

import Foundation
import CodeServices
import FlipchatServices

@MainActor
class ChatController: ObservableObject {
    
    let owner: KeyPair
    
    @Published private(set) var hasFetchedChats: Bool = false
    
    @Published private(set) var chats: [Chat] = []
    
    @Published private(set) var unreadCount: Int = 0
    
    private let userID: UserID
    private let client: FlipchatClient
    private let organizer: Organizer
    
    private let pageSize: Int = 100
    
    private var fetchInflight: Bool = false
    
    private var latestPointers: [FlipchatServices.ChatID: FlipchatServices.MessageID] = [:]
    
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
            case .success(let events):
                events.forEach {
                    self?.handleEvent($0)
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
    
    private func destroyChatStream() {
        chatStream?.destroy()
    }
    
    // MARK: - Events -
    
    private func handleEvent(_ event: Chat.BatchUpdate) {
        let chat = chats.first { $0.id == event.chatID }
        
        guard let chat else {
            trace(.warning, components: "Received update for a chat that isn't in the list. ID: \(event.chatID.description)")
            return
        }
        
        if let metadata = event.chatMetadata {
            update(chat: chat, withMetadata: metadata)
        }
        
        if let lastMessage = event.lastMessage {
            update(chat: chat, withLastMessage: lastMessage)
        }
        
        if let members = event.memberUpdate {
            update(chat: chat, withMembers: members)
        }
        
        if let pointer = event.pointerUpdate {
            update(chat: chat, withPointerUpdate: pointer)
        }
        
        if let typing = event.typingUpdate {
            update(chat: chat, withTypingUpdate: typing)
        }
    }
    
    private func update(chat: Chat, withMetadata metadata: Chat.Metadata) {
        trace(.success, components: "Metadata: \(metadata)")
//        chat.update(from: metadata)
    }
    
    private func update(chat: Chat, withLastMessage message: Chat.Message) {
        trace(.success, components: "Last Message: \(message)")
//        chat.setLastMessage(message)
    }
    
    private func update(chat: Chat, withMembers members: [Chat.Member]) {
        trace(.success, components: "Members: \(members)")
    }
    
    private func update(chat: Chat, withPointerUpdate update: Chat.BatchUpdate.PointerUpdate) {
        trace(.success, components: "Pointer: \(update)")
    }
    
    private func update(chat: Chat, withTypingUpdate update: Chat.BatchUpdate.TypingUpdate) {
        trace(.success, components: "Typing: \(update)")
    }
    
    // MARK: - Message Stream -
    
    func streamMessages(chatID: FlipchatServices.ChatID, completion: @escaping (Result<[Chat.Message], ErrorStreamMessages>) -> Void) -> StreamMessagesReference {
        client.streamMessages(chatID: chatID, owner: owner, completion: completion)
    }
    
    // MARK: - Messages -
    
    func receiveMessages(messages: [Chat.Message], for chatID: FlipchatServices.ChatID) throws {
        try chatStore.receive(messages: messages, for: chatID)
    }
    
    func sendMessage(text: String, for chatID: FlipchatServices.ChatID) async throws {
        try await chatStore.sendMessage(text: text, for: chatID)
    }
    
    // MARK: - Group Chat -
    
    func startGroupChat() async throws -> FlipchatServices.ChatID {
        try await chatStore.startGroupChat()
    }
    
    func fetchGroupChat(roomNumber: RoomNumber, hide: Bool) async throws -> FlipchatServices.ChatID {
        try await chatStore.fetchChat(roomNumber: roomNumber, hide: hide)
    }
    
    func joinGroupChat(roomNumber: RoomNumber) async throws -> FlipchatServices.ChatID {
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
