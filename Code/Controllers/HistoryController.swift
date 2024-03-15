//
//  HistoryController.swift
//  Code
//
//  Created by Dima Bart on 2021-07-13.
//

import Foundation
import CodeServices

@MainActor
class HistoryController: ObservableObject {
    
    @Published private(set) var hasFetchedChats: Bool = false
    
    @Published private(set) var chats: [Chat] = []
    
    @Published private(set) var unreadCount: Int = 0
    
    private let client: Client
    private let organizer: Organizer
    private let owner: KeyPair
    
    private let pageSize: Int = 100
    
    // MARK: - Init -
    
    init(client: Client, organizer: Organizer) {
        self.client = client
        self.organizer = organizer
        self.owner = organizer.ownerKeyPair
        
        NotificationCenter.default.addObserver(forName: .pushNotificationReceived, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            Task {
                await self.pushNotificationReceived()
            }
        }
    }
    
    deinit {
        trace(.warning, components: "Deallocating HistoryController")
    }
    
    // MARK: - Fetch -
    
    func fetchChats() {
        Task {
            try await fetchAllChats()
        }
    }
    
    func updateBadgeCount() {
        Task {
            try await updateChatsBadgeCount()
            computeUnreadCount()
        }
    }
    
//    func updateChats() {
//        Task {
//            try await updateAllChats()
//        }
//    }
    
    private func fetchAllChats() async throws {
        chats = try await fetchChatsAndInitialMessages()
        hasFetchedChats = true
        
        computeUnreadCount()
    }
    
//    private func updateAllChats() async throws {
//        chats = try await updatingChats(chats: chats)
//        
//        computeUnreadCount()
//    }
    
    private func computeUnreadCount() {
        unreadCount = computeUnreadCount(for: chats)
    }
    
    // MARK: - Chats -
    
    func advanceReadPointer(for chat: Chat) async throws {
        if let newestMessage = chat.newestMessage {
            try await client.advancePointer(
                chatID: chat.id,
                to: newestMessage.id,
                owner: owner
            )
            
            chat.resetUnreadCount()
            
            computeUnreadCount()
        }
    }
    
    func setMuted(_ muted: Bool, for chat: Chat) async throws {
        chat.setMuted(muted)
        
        computeUnreadCount()
        
        try await client.setMuteState(
            chatID: chat.id,
            muted: muted,
            owner: owner
        )
    }
    
    func setSubscribed(_ subscribed: Bool, for chat: Chat) async throws {
        chat.setSubscribed(subscribed)
        
        computeUnreadCount()
        
        try await client.setSubscriptionState(
            chatID: chat.id,
            subscribed: subscribed,
            owner: owner
        )
    }
    
    func chat(for chatID: ID) -> Chat? {
        chats.first { $0.id == chatID }
    }
    
    private func setMessages(messages: [Chat.Message], for chatID: ID) {
        chat(for: chatID)?.setMessages(messages)
    }
    
    private func computeUnreadCount(for chats: [Chat]) -> Int {
        chats.reduce(into: 0) { result, chat in
            if !chat.isMuted && chat.isSubscribed { // Ignore muted chats and unsubscribed chats
                result = result + chat.unreadCount
            }
        }
    }
    
    // MARK: - Fetching -
    
    @CronActor
    private func fetchChatsAndInitialMessages() async throws -> [Chat] {
        let chats = try await client.fetchChats(owner: owner)
        return try await fetchInitialMessages(for: chats)
    }
    
    @CronActor
    private func updateChatsBadgeCount() async throws {
        let existingChats = await chats.elementsKeyed(by: \.id)
        let newChats = try await client.fetchChats(owner: owner)
        
        for newChat in newChats {
            if let existingChat = existingChats[newChat.id] {
                existingChat.unreadCount = newChat.unreadCount
            }
        }
    }
    
    @CronActor
    private func fetchInitialMessages(for chats: [Chat]) async throws -> [Chat] {
        var chatContainer: [Chat] = []
        
        await withTaskGroup(of: (Chat, [Chat.Message]).self) { group in
            chats.forEach { chat in
                group.addTask {
                    
                    // Only fetch messages for chats that don't have any
                    // messages. All messages will be fetch on open anyway
                    guard chat.messages.isEmpty else {
                        return (chat, chat.messages)
                    }
                            
                    do {
                        let messages = try await self.fetchAndDecryptMessages(
                            for: chat,
                            upTo: chat.oldestMessage?.id
                        )
                        
                        return (chat, messages)
                    } catch {
                        return (chat, [])
                    }
                }
            }
            
            for await (chat, messages) in group {
                chat.setMessages(messages)
                chatContainer.append(chat)
            }
        }
        
        return chatContainer.sortedByMessageOrder()
    }
    
    @CronActor
    func fetchAllMessages(for chat: Chat) async throws {
        var container: [Chat.Message] = []
        
        let pageSize = 100
        
        var currentID: ID? = nil
        while true {
            let messages = try? await fetchAndDecryptMessages(
                for: chat,
                upTo: currentID,
                pageSize: 100
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
        }
        
        await setMessages(messages: container, for: chat.id)
    }
    
    @CronActor
    func fetchAndDecryptMessages(for chat: Chat, upTo id: ID?, pageSize: Int? = nil) async throws -> [Chat.Message] {
        var messages = try await self.client.fetchMessages(
            chatID: chat.id,
            owner: self.owner,
            direction: .descending(upTo: id),
            pageSize: pageSize ?? 20
        )
        
        // Decrypt message if domain found. If decryption fails for
        // what ever reason, we'll pass through the message array as is
        if case .domain(let domain) = chat.title {
            let hasEncryptedContent = messages.first { $0.hasEncryptedContent } != nil
            if hasEncryptedContent, let relationship = self.organizer.relationship(for: domain) {
                do {
                    messages = try messages.map { try $0.decrypting(using: relationship.cluster.authority.keyPair) }
                } catch {}
            }
        }
        
        return messages
    }
    
    // MARK: - Notifications -
    
    func pushNotificationReceived() {
        updateBadgeCount()
    }
    
    func appDidBecomeActive() {
        updateBadgeCount()
    }
}

extension Array where Element == Chat {
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

extension HistoryController {
    static let mock = HistoryController(
        client: .mock,
        organizer: .mock2
    )
}
