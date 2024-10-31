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
    
    // MARK: - Init -
    
    init(userID: UserID, client: FlipchatClient, organizer: Organizer) {
        self.userID    = userID
        self.client    = client
        self.organizer = organizer
        self.owner     = organizer.ownerKeyPair
        
//        NotificationCenter.default.addObserver(forName: .messageNotificationReceived, object: nil, queue: .main) { [weak self] _ in
//            guard let self = self else { return }
//            Task {
//                await self.pushNotificationReceived()
//            }
//        }
        
        streamChatEvents()
    }
    
    deinit {
        trace(.warning, components: "Deallocating ChatController")
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
        chat.update(from: metadata)
    }
    
    private func update(chat: Chat, withLastMessage message: Chat.Message) {
        chat.setLastMessage(message)
    }
    
    private func update(chat: Chat, withMembers members: [Chat.Member]) {
        // TODO: Update
    }
    
    private func update(chat: Chat, withPointerUpdate: Chat.BatchUpdate.PointerUpdate) {
        // TODO: Update
    }
    
    private func update(chat: Chat, withTypingUpdate: Chat.BatchUpdate.TypingUpdate) {
        // TODO: Update
    }
    
    // MARK: - Message Stream -
    
    func streamMessages(chatID: FlipchatServices.ChatID, completion: @escaping (Result<[Chat.Message], ErrorStreamMessages>) -> Void) -> StreamMessagesReference {
        client.streamMessages(chatID: chatID, owner: owner, completion: completion)
    }
    
    // MARK: - Messages -
    
    func sendMessage(content: Chat.Content, in chatID: FlipchatServices.ChatID) async throws -> Chat.Message {
        try await client.sendMessage(
            chatID: chatID,
            owner: owner,
            content: content
        )
    }
    
    // MARK: - Group Chat -
    
    func startGroupChat() async throws -> Chat {
        let metadata = try await client.startGroupChat(with: [userID], owner: organizer.ownerKeyPair)
        
        return Chat(
            selfUserID: userID,
            metadata: metadata,
            messages: []
        )
    }
    
    func joinGroupChat(roomNumber: RoomNumber) async throws -> Chat {
        let metadata = try await client.joinGroupChat(
            roomNumber: roomNumber,
            owner: organizer.ownerKeyPair
        )
        
        return Chat(
            selfUserID: userID,
            metadata: metadata,
            messages: []
        )
    }
    
    // MARK: - Fetch -
    
    func fetchChats() {
        Task {
            try await fetchChats()
        }
    }
    
    private func fetchChats() async throws {
        guard !fetchInflight else {
            return
        }
        
        fetchInflight = true
        if !hasFetchedChats {
            trace(.warning, components: "Fetching ALL chats, ALL messages.")
            chats = try await fetchAllChatsAndMessages()
            hasFetchedChats = true
        } else {
            trace(.send, components: "Fetching delta chats and messages...")
            chats = try await fetchDeltaChatsAndMessages()
        }
        
        computeUnreadCount()
        fetchInflight = false
    }
    
    private func computeUnreadCount() {
        unreadCount = computeUnreadCount(for: chats)
    }
    
    // MARK: - Pointers -
    
    private func setReadPointer(to message: Chat.Message, chat: Chat) {
        latestPointers[chat.id] = message.id
    }
    
    private func shouldAdvanceReadPointer(for message: Chat.Message, chat: Chat) -> Bool {
        if let latestMessageID = latestPointers[chat.id] {
            return message.id > latestMessageID
        }
        return true
    }
    
    // MARK: - Chats -
    
    func advanceReadPointer(for chat: Chat) async throws {
        if let newestMessage = chat.newestMessage {
            guard shouldAdvanceReadPointer(for: newestMessage, chat: chat) else {
                return
            }
                
            try await client.advancePointer(
                chatID: chat.id,
                to: newestMessage.id,
                owner: owner
            )
            
            setReadPointer(to: newestMessage, chat: chat)
            
            chat.resetUnreadCount()
            
            computeUnreadCount()
        }
    }
    
    func chat(for chatID: FlipchatServices.ChatID) -> Chat? {
        chats.first { $0.id == chatID }
    }
    
    private func setMessages(messages: [Chat.Message], for chatID: FlipchatServices.ChatID) {
        chat(for: chatID)?.setMessages(messages)
    }
    
    private func computeUnreadCount(for chats: [Chat]) -> Int {
        chats.reduce(into: 0) { result, chat in
            if !chat.isMuted { // Ignore muted chats and unsubscribed chats
                result = result + chat.unreadCount
            }
        }
    }
    
    // MARK: - Fetching -
    
    private func fetchAllChatsAndMessages() async throws -> [Chat] {
        let chatsMetadata = try await client.fetchChats(owner: owner)
        
        let chats = chatsMetadata.map { Chat(selfUserID: userID, metadata: $0) }
        
        trace(.success, components: "Chats: \(chats.count)")
        return try await fetchAllMessages(for: chats)
    }
    
    private func fetchDeltaChatsAndMessages() async throws -> [Chat] {
        let chats = await updating(
            existing: chats,
            with: try await client.fetchChats(owner: owner)
        )
        
        trace(.success, components: "Chats: \(chats.count)")
        return try await fetchLatestMessagesOnly(chats: chats)
    }
    
    private func updating(existing existingChats: [Chat], with newChatsMetadata: [Chat.Metadata]) async -> [Chat] {
        let index = existingChats.elementsKeyed(by: \.id)
        
        var newChats = newChatsMetadata.map { Chat(selfUserID: userID, metadata: $0) }
        
        for (i, newChat) in newChats.enumerated() {
            
            // If this chat exists, we'll reuse the same
            // object instance and update it's properties.
            // There could be existing binding to this
            // observable object that we don't want to break.
            if let existingChat = index[newChat.id] {
                existingChat.update(from: newChat.metadata)
                newChats[i] = existingChat
            } else {
                // Do nothing, this is a new chat
            }
        }
        
        return newChats
    }
    
    private func update(chat: Chat, from newChat: Chat.Metadata) {
        chat.update(from: newChat)
    }
    
    private func fetchAllMessages(for chats: [Chat]) async throws -> [Chat] {
        var chatContainer: [Chat] = []
        
        await withTaskGroup(of: (Chat, [Chat.Message]).self) { group in
            chats.forEach { chat in
                group.addTask {
                    let messages = await self.fetchAllMessages(for: chat)
                    return (chat, messages)
                }
            }
            
            for await (chat, messages) in group {
                chat.setMessages(messages)
                chatContainer.append(chat)
            }
        }
        
        return chatContainer.sortedByMessageOrder()
    }
    
    private func fetchAllMessages(for chat: Chat) async -> [Chat.Message] {
        var container: [Chat.Message] = []
        
        var pages = 1
        var currentToken: FlipchatServices.ID? = nil
        while true {
            let messages = try? await fetchAndDecryptMessages(
                chatID: chat.id,
                query: .init(
                    order: .asc,
                    pagingToken: currentToken
                )
            )
            
            guard let messages else {
                break
            }
            
            container.append(contentsOf: messages)
            
            guard messages.count >= pageSize else {
                // If the number of messags fetched
                // is less than the page, it's the end
                break
            }
            
            currentToken = messages.last!.id
            pages += 1
        }
        
        trace(.success, components: "Chat ID: \(chat.id)", "Messages: \(container.count)", "Pages: \(pages)")
        return container
    }
    
    private func fetchLatestMessagesOnly(chats: [Chat]) async throws -> [Chat] {
        var chatContainer: [Chat] = []
        
        try await withThrowingTaskGroup(of: (Chat, [Chat.Message]).self) { group in
            chats.forEach { chat in
                group.addTask {
                    let messages = try await self.fetchLatestMessagesOnly(chat: chat)
                    return (chat, messages)
                }
            }
            
            for try await (chat, messages) in group {
                chat.insertMessages(messages)
                chatContainer.append(chat)
            }
        }
        
        return chatContainer.sortedByMessageOrder()
    }
    
    private func fetchLatestMessagesOnly(chat: Chat) async throws -> [Chat.Message] {
        var container: [Chat.Message] = []
        
        var pages = 1
        var lastID = chat.latestMessage()?.id
        while true {
            let messages = try await fetchAndDecryptMessages(
                chatID: chat.id,
                query: .init(
                    order: .desc,
                    pagingToken: lastID // If nil, form the beginning
                )
            )
            
            guard !messages.isEmpty else {
                break
            }
            
            container.append(contentsOf: messages)
            
            guard messages.count >= pageSize else {
                // If the number of messags fetched
                // is less than the page, it's the end
                break
            }
            
            lastID = messages.last!.id
            pages += 1
        }
        
        trace(.success, components: "Chat ID: \(chat.id)", "Messages: \(container.count)", "Pages: \(pages)")
        return container
    }
    
    private func fetchAndDecryptMessages(chatID: FlipchatServices.ChatID, query: PageQuery) async throws -> [Chat.Message] {
        let messages = try await self.client.fetchMessages(
            chatID: chatID,
            owner: self.owner,
            query: query
        )
        
        // TODO: Handle encryption
        
//        // Decrypt message if domain found. If decryption fails for
//        // what ever reason, we'll pass through the message array as is
//        if case .domain(let domain) = await chat.title {
//            let hasEncryptedContent = messages.first { $0.hasEncryptedContent } != nil
//            if hasEncryptedContent, let relationship = self.organizer.relationship(for: domain) {
//                do {
//                    messages = try messages.map { try $0.decrypting(using: relationship.cluster.authority.keyPair) }
//                } catch {}
//            }
//        }
        
        return messages
    }
    
    // MARK: - Notifications -
    
//    func pushNotificationReceived() {
//        fetchChats()
//    }
//    
//    func appDidBecomeActive() {
//        fetchChats()
//    }
}

private extension Array where Element == Chat {
    
    @MainActor
    func sortedByMessageOrder() -> [Element] {
        sorted { lhs, rhs in
            let leftDate  = lhs.messages.last?.date
            let rightDate = rhs.messages.last?.date
            
            if let leftDate, let rightDate {
                return leftDate > rightDate
            } else if leftDate != nil {
                return true
            } else if rightDate != nil {
                return false
            } else {
                return false
            }
        }
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
