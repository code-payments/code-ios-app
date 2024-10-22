//
//  ChatController.swift
//  Code
//
//  Created by Dima Bart on 2021-07-13.
//

import Foundation
import CodeServices

@MainActor
class ChatController: ObservableObject {
    
    let owner: KeyPair
    
    @Published private(set) var hasFetchedChats: Bool = false
    
    @Published private(set) var chats: [ChatLegacy] = []
    
    @Published private(set) var unreadCount: Int = 0
    
    private let client: Client
    private let organizer: Organizer
    
    private let pageSize: Int = 100
    
    private var fetchInflight: Bool = false
    
    private var latestPointers: [ChatID: MessageID] = [:]
    
    // MARK: - Init -
    
    init(client: Client, organizer: Organizer) {
        self.client = client
        self.organizer = organizer
        self.owner = organizer.ownerKeyPair
        
        NotificationCenter.default.addObserver(forName: .messageNotificationReceived, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            Task {
                await self.pushNotificationReceived()
            }
        }
    }
    
    deinit {
        trace(.warning, components: "Deallocating ChatController")
    }
    
    // MARK: - Stream -
    
    func openChatStream(chatID: ChatID, completion: @escaping (Result<[ChatLegacy.Event], ErrorOpenChatStream>) -> Void) -> ChatMessageStreamReference {
        client.openChatStream(chatID: chatID, owner: owner, completion: completion)
    }
    
    // MARK: - Messages -
    
    func sendMessage(content: ChatLegacy.Content, in chatID: ChatID) async throws -> ChatLegacy.Message {
        try await client.sendMessage(
            chatID: chatID,
            owner: owner,
            content: content
        )
    }
    
    // MARK: - Chats -
    
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
    
    private func setReadPointer(to message: ChatLegacy.Message, chat: ChatLegacy) {
        latestPointers[chat.id] = message.id
    }
    
    private func shouldAdvanceReadPointer(for message: ChatLegacy.Message, chat: ChatLegacy) -> Bool {
        if let latestMessageID = latestPointers[chat.id] {
            return message.id > latestMessageID
        }
        return true
    }
    
    // MARK: - Chats -
    
    func advanceReadPointer(for chat: ChatLegacy) async throws {
        guard let selfMember = chat.selfMember else {
            return
        }
        
        if let newestMessage = chat.newestMessage {
            guard shouldAdvanceReadPointer(for: newestMessage, chat: chat) else {
                return
            }
                
            try await client.advancePointer(
                chatID: chat.id,
                to: newestMessage.id,
                memberID: selfMember.id,
                owner: owner
            )
            
            setReadPointer(to: newestMessage, chat: chat)
            
            chat.resetUnreadCount()
            
            computeUnreadCount()
        }
    }
    
    func setMuted(_ muted: Bool, for chat: ChatLegacy) async throws {
        chat.setMuted(muted)
        
        computeUnreadCount()
        
        try await client.setMuteState(
            chatID: chat.id,
            muted: muted,
            owner: owner
        )
    }
    
    func chat(for chatID: ID) -> ChatLegacy? {
        chats.first { $0.id == chatID }
    }
    
    private func setMessages(messages: [ChatLegacy.Message], for chatID: ID) {
        chat(for: chatID)?.setMessages(messages)
    }
    
    private func computeUnreadCount(for chats: [ChatLegacy]) -> Int {
        chats.reduce(into: 0) { result, chat in
            if !chat.isMuted { // Ignore muted chats and unsubscribed chats
                result = result + chat.unreadCount
            }
        }
    }
    
    // MARK: - Fetching -
    
    private func fetchAllChatsAndMessages() async throws -> [ChatLegacy] {
        let chats = try await client.fetchChats(owner: owner)
        trace(.success, components: "Chats: \(chats.count)")
        return try await fetchAllMessages(chats: chats)
    }
    
    private func fetchDeltaChatsAndMessages() async throws -> [ChatLegacy] {
        let chats = await updating(
            existing: chats,
            with: try await client.fetchChats(owner: owner)
        )
        
        trace(.success, components: "Chats: \(chats.count)")
        return try await fetchLatestMessagesOnly(chats: chats)
    }
    
    private func updating(existing existingChats: [ChatLegacy], with newChats: [ChatLegacy]) async -> [ChatLegacy] {
        let index = existingChats.elementsKeyed(by: \.id)
        var updatedChats = newChats
        for (i, updatedChat) in updatedChats.enumerated() {
            
            // If this chat exists, we'll reuse the same
            // object instance and update it's properties.
            // There could be existing binding to this
            // observable object that we don't want to break.
            if let existingChat = index[updatedChat.id] {
                update(chat: existingChat, from: updatedChat)
                updatedChats[i] = existingChat
            } else {
                // Do nothing, this is a new chat
            }
        }
        
        return updatedChats
    }
    
    private func update(chat: ChatLegacy, from newChat: ChatLegacy) {
        chat.update(from: newChat)
    }
    
    private func fetchAllMessages(chats: [ChatLegacy]) async throws -> [ChatLegacy] {
        var chatContainer: [ChatLegacy] = []
        
        await withTaskGroup(of: (ChatLegacy, [ChatLegacy.Message]).self) { group in
            chats.forEach { chat in
                group.addTask {
                    let messages = await self.fetchAllMessages(chat: chat)
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
    
    private func fetchAllMessages(chat: ChatLegacy) async -> [ChatLegacy.Message] {
        var container: [ChatLegacy.Message] = []
        
        var pages = 1
        var currentID: ID? = nil
        while true {
            let messages = try? await fetchAndDecryptMessages(
                chat: chat,
                direction: .descending(upTo: currentID),
                pageSize: pageSize
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
            
            currentID = messages.last!.id
            pages += 1
        }
        
        trace(.success, components: "Chat ID: \(chat.id)", "Messages: \(container.count)", "Pages: \(pages)")
        return container
    }
    
    private func fetchLatestMessagesOnly(chats: [ChatLegacy]) async throws -> [ChatLegacy] {
        var chatContainer: [ChatLegacy] = []
        
        await withTaskGroup(of: (ChatLegacy, [ChatLegacy.Message]).self) { group in
            chats.forEach { chat in
                group.addTask {
                    let messages = await self.fetchLatestMessagesOnly(chat: chat)
                    return (chat, messages)
                }
            }
            
            for await (chat, messages) in group {
                chat.insertMessages(messages)
                chatContainer.append(chat)
            }
        }
        
        return chatContainer.sortedByMessageOrder()
    }
    
    private func fetchLatestMessagesOnly(chat: ChatLegacy) async -> [ChatLegacy.Message] {
        var container: [ChatLegacy.Message] = []
        
        var pages = 1
        var lastID = chat.latestMessage()?.id
        while true {
            let messages = try? await fetchAndDecryptMessages(
                chat: chat,
                direction: .ascending(from: lastID), // If nil, form the beginning
                pageSize: pageSize
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
            
            lastID = messages.last!.id
            pages += 1
        }
        
        trace(.success, components: "Chat ID: \(chat.id)", "Messages: \(container.count)", "Pages: \(pages)")
        return container
    }
    
    private func fetchAndDecryptMessages(chat: ChatLegacy, direction: MessageDirection, pageSize: Int) async throws -> [ChatLegacy.Message] {
        guard let selfMember = chat.selfMember else {
            return []
        }
        
        let messages = try await self.client.fetchMessages(
            chatID: chat.id,
            memberID: selfMember.id,
            owner: self.owner,
            direction: direction,
            pageSize: pageSize
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
    
    func pushNotificationReceived() {
        fetchChats()
    }
    
    func appDidBecomeActive() {
        fetchChats()
    }
}

private extension Array where Element == ChatLegacy {
    
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
        client: .mock,
        organizer: .mock2
    )
}
