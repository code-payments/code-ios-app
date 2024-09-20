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
    
    @Published private(set) var chats: [Chat] = []
    
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
    
    func openChatStream(chatID: ChatID, memberID: MemberID, completion: @escaping (Result<[Chat.Event], ErrorOpenChatStream>) -> Void) -> ChatMessageStreamReference {
        client.openChatStream(chatID: chatID, memberID: memberID, owner: owner, completion: completion)
    }
    
    // MARK: - Messages -
    
    func send(content: Chat.Content, in chat: Chat, from member: Chat.Member) async throws -> Chat.Message {
        try await sendMessage(
            in: chat.id,
            from: member.id,
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
    
    // MARK: - Identity -
    
    func revealSelfIdentity(chat: Chat, username: String) async throws -> Chat.Message {
        guard let selfMemeber = chat.selfMember else {
            throw Error.selfMemberNotFound
        }
        
        return try await client.revealIdentity(
            chatID: chat.id,
            memberID: selfMemeber.id,
            twitterUsername: username,
            owner: owner
        )
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
    private func sendMessage(in chatID: ChatID, from memberID: MemberID, content: Chat.Content) async throws -> Chat.Message {
        try await client.sendMessage(
            chatID: chatID,
            memberID: memberID,
            owner: owner,
            content: content
        )
    }
    
    @CronActor
    private func fetchAllChatsAndMessages() async throws -> [Chat] {
        let chats = try await client.fetchChats(owner: owner)
        trace(.success, components: "Chats: \(chats.count)")
        return try await fetchAllMessages(chats: chats)
    }
    
    @CronActor
    private func fetchDeltaChatsAndMessages() async throws -> [Chat] {
        let chats = await updating(
            existing: await self.chats,
            with: try await client.fetchChats(owner: owner)
        )
        
        trace(.success, components: "Chats: \(chats.count)")
        return try await fetchLatestMessagesOnly(chats: chats)
    }
    
    @CronActor
    private func updating(existing existingChats: [Chat], with newChats: [Chat]) async -> [Chat] {
        let index = existingChats.elementsKeyed(by: \.id)
        var updatedChats = newChats
        for (i, updatedChat) in updatedChats.enumerated() {
            
            // If this chat exists, we'll reuse the same
            // object instance and update it's properties.
            // There could be existing binding to this
            // observable object that we don't want to break.
            if let existingChat = await index[updatedChat.id] {
                await update(chat: existingChat, from: updatedChat)
                updatedChats[i] = existingChat
            } else {
                // Do nothing, this is a new chat
            }
        }
        
        return updatedChats
    }
    
    private func update(chat: Chat, from newChat: Chat) {
        chat.update(from: newChat)
    }
    
    @CronActor
    private func fetchAllMessages(chats: [Chat]) async throws -> [Chat] {
        var chatContainer: [Chat] = []
        
        await withTaskGroup(of: (Chat, [Chat.Message]).self) { group in
            chats.forEach { chat in
                group.addTask {
                    let messages = await self.fetchAllMessages(chat: chat)
                    return (chat, messages)
                }
            }
            
            for await (chat, messages) in group {
                await chat.setMessages(messages)
                chatContainer.append(chat)
            }
        }
        
        return await chatContainer.sortedByMessageOrder()
    }
    
    @CronActor
    private func fetchAllMessages(chat: Chat) async -> [Chat.Message] {
        var container: [Chat.Message] = []
        
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
        
        trace(.success, components: "Chat ID: \(await chat.id)", "Messages: \(container.count)", "Pages: \(pages)")
        return container
    }
    
    @CronActor
    private func fetchLatestMessagesOnly(chats: [Chat]) async throws -> [Chat] {
        var chatContainer: [Chat] = []
        
        await withTaskGroup(of: (Chat, [Chat.Message]).self) { group in
            chats.forEach { chat in
                group.addTask {
                    let messages = await self.fetchLatestMessagesOnly(chat: chat)
                    return (chat, messages)
                }
            }
            
            for await (chat, messages) in group {
                await chat.insertMessages(messages)
                chatContainer.append(chat)
            }
        }
        
        return await chatContainer.sortedByMessageOrder()
    }
    
    @CronActor
    private func fetchLatestMessagesOnly(chat: Chat) async -> [Chat.Message] {
        var container: [Chat.Message] = []
        
        var pages = 1
        var lastID = await chat.latestMessage()?.id
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
        
        trace(.success, components: "Chat ID: \(await chat.id)", "Messages: \(container.count)", "Pages: \(pages)")
        return container
    }
    
    @CronActor
    private func fetchAndDecryptMessages(chat: Chat, direction: MessageDirection, pageSize: Int) async throws -> [Chat.Message] {
        guard let selfMember = await chat.selfMember else {
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

extension ChatController {
    enum Error: Swift.Error {
        case selfMemberNotFound
    }
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
        client: .mock,
        organizer: .mock2
    )
}