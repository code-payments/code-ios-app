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
    
    @Published private(set) var chatsDidChange: Int = 0
    
    let owner: KeyPair
    
    private let userID: UserID
    private let client: FlipchatClient
    private let paymentClient: Client
    private let organizer: Organizer
    
    private let pageSize: Int = 100
    
    private var fetchInflight: Bool = false
    
    private var latestPointers: [ChatID: MessageID] = [:]
    
    private var chatStream: StreamChatsReference?
    
    private let database: Database
    
    // MARK: - Init -
    
    init(userID: UserID, client: FlipchatClient, paymentClient: Client, organizer: Organizer) {
        self.userID    = userID
        self.client    = client
        self.paymentClient = paymentClient
        self.organizer = organizer
        self.owner     = organizer.ownerKeyPair
        
        let storeURL = URL.applicationSupportDirectory.appendingPathComponent("\(userID.uuid.uuidString).sqlite")
        self.database = try! Database(url: storeURL)
        
//        fetchAndInsertSelf()
        streamChatEvents()
        
        Task {
            try await sync()
        }
        
        database.commit = { [weak self] in
            self?.chatsDidChange += 1
            trace(.warning, components: "COMMIT")
        }
    }
    
    deinit {
        trace(.warning, components: "Deallocating ChatController.")
    }
    
    func prepareForLogout() {
        destroyChatStream()
    }
    
    // MARK: - Database -
    
    func getUser(userID: UserID) throws -> MemberRow? {
        try database.getUser(userID: userID.uuid)
    }
    
    func getRooms() throws -> [RoomRow] {
        try database.getRooms()
    }
    
    func getRoom(chatID: ChatID) throws -> RoomDescription? {
        try database.getRoom(roomID: chatID.uuid)
    }
    
    func getMessages(chatID: ChatID, pageSize: Int = 1024) throws -> [MessageRow] {
        try database.getMessages(roomID: chatID.uuid, pageSize: pageSize, offset: 0)
    }
    
    // MARK: - Sync -
    
    func sync() async throws {
        trace(.send)
        
        let chats = try await client.fetchChats(owner: owner)
        try database.transaction {
            try $0.insertRooms(rooms: chats)
        }
        
        for chat in chats {
            Task {
                let description = try await client.fetchChat(
                    for: .chatID(chat.id),
                    owner: owner
                )
                
                // If there's a latest message for the chat, we'll fetch all
                // messages since that message going forward, otherwise we'll
                // fetch all messages backwards starting from now.
                let messages: [Chat.Message]
//                if let latestMessageID = try database.getLatestMessageID(roomID: chat.id.uuid) {
//                    messages = try await syncMessagesForward(for: chat.id, from: latestMessageID)
//                    trace(.warning, components: "[FORWARD] Messages \(messages.count)")
//                } else {
                    messages = try await syncMessagesBackwards(for: chat.id)
//                    trace(.warning, components: "[BACKWARD] Messages \(messages.count)")
//                }
                
                try database.transaction {
                    try $0.insertMembers(members: description.members, chatID: chat.id)
                    try $0.insertMessages(messages: messages, chatID: chat.id)
                }
                
                trace(.warning, components: "Chat synced [\(chat.id)]", "Members: \(description.members.count)", "Messages: \(messages.count)")
            }
        }
    }
    
    func syncMessagesBackwards(for chatID: ChatID, from messageID: UUID? = nil) async throws -> [Chat.Message] {
        try await client.fetchMessages(
            chatID: chatID,
            owner: owner,
            query: PageQuery(
                order: .desc,
                pagingToken: messageID,
                pageSize: 500
            )
        )
    }
    
    func syncMessagesForward(for chatID: ChatID, from messageID: UUID) async throws -> [Chat.Message] {
        var cursor = messageID
        
        let pageSize = 1024
        
        var container: [Chat.Message] = []
        
        var hasMoreChats = true
        while hasMoreChats {
            let messages = try await client.fetchMessages(
                chatID: chatID,
                owner: owner,
                query: PageQuery(
                    order: .asc,
                    pagingToken: cursor,
                    pageSize: pageSize
                )
            )
            
            if !messages.isEmpty {
                container.append(contentsOf: messages)
                cursor = messages.last!.id.uuid
            }
            
            hasMoreChats = messages.count == pageSize
        }
        
        return container
    }
    
    // MARK: - Chat Stream -
    
    func streamChatEvents() {
        destroyChatStream()
        
        chatStream = client.streamChatEvents(owner: owner) { [weak self] result in
            switch result {
            case .success(let updates):
                self?.receive(updates: updates)
                
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
    
    private func receive(updates: [Chat.BatchUpdate]) {
        updates.forEach {
            try? handleEvent($0)
        }
    }
    
    private func handleEvent(_ batchUpdate: Chat.BatchUpdate) throws {
        if let metadata = batchUpdate.chatMetadata {
            try update(chatID: batchUpdate.chatID, withMetadata: metadata)
        }
        
        if let lastMessage = batchUpdate.lastMessage {
            try update(chatID: batchUpdate.chatID, withLastMessage: lastMessage)
        }
        
        if let members = batchUpdate.memberUpdate {
            try update(chatID: batchUpdate.chatID, withMembers: members)
        }
        
        if let pointer = batchUpdate.pointerUpdate {
            try update(chatID: batchUpdate.chatID, withPointerUpdate: pointer)
        }
        
        if let typing = batchUpdate.typingUpdate {
            try update(chatID: batchUpdate.chatID, withTypingUpdate: typing)
        }
    }
    
    private func update(chatID: ChatID, withMetadata metadata: Chat.Metadata) throws {
        trace(.success, components: "Metadata: \(metadata)")
        
        try database.transaction {
            try $0.insertRooms(rooms: [metadata])
            trace(.success, components: "Chat updated: \(chatID.uuid.uuidString)")
        }
    }
    
    private func update(chatID: ChatID, withMembers members: [Chat.Member]) throws {
        guard !members.isEmpty else {
            return
        }
        
        try database.transaction {
            try $0.insertMembers(members: members, chatID: chatID)
            trace(.success, components: "Members +\(members.count)")
        }
    }
    
    private func update(chatID: ChatID, withLastMessage message: Chat.Message) throws {
        trace(.success, components: "Message: \(message.id.description)", "Content: \(message.contents)")
        
        try database.transaction {
            try $0.insertMessages(messages: [message], chatID: chatID)
            trace(.success, components: "Message: \(message.contents.first?.text.prefix(100) ?? "nil")")
        }
    }
    
    private func update(chatID: ChatID, withPointerUpdate update: Chat.BatchUpdate.PointerUpdate) throws {
        trace(.success, components: "Pointer: \(update)")
    }
    
    private func update(chatID: ChatID, withTypingUpdate update: Chat.BatchUpdate.TypingUpdate) throws {
        trace(.success, components: "Typing: \(update)")
    }
    
    // MARK: - Message Stream -
    
    func streamMessages(chatID: ChatID, messageID: MessageID?, completion: @escaping (Result<[Chat.Message], ErrorStreamMessages>) -> Void) -> StreamMessagesReference {
        client.streamMessages(chatID: chatID, from: messageID, owner: owner, completion: completion)
    }
    
    // MARK: - Messages -
    
    func receiveMessages(messages: [Chat.Message], for chatID: ChatID) async throws {
        let filteredMessages = messages.filter {
            // Filter out any messages sent by self
            // because those are handled directly in
            // the call to `sendMessage(text:for:)`
            !($0.senderID == userID)
        }
        
        try database.transaction {
            try $0.insertMessages(messages: filteredMessages, chatID: chatID)
        }
        
        changedChats()
    }
    
    func sendMessage(text: String, for chatID: ChatID) async throws {
        let deliveredMessage = try await client.sendMessage(
            chatID: chatID,
            owner: owner,
            content: .text(text)
        )
        
        try database.transaction {
            try $0.insertMessages(messages: [deliveredMessage], chatID: chatID)
        }
        
        changedChats()
    }
    
    func advanceReadPointerToLatest(for chatID: ChatID) async throws {
        guard let messageID = try database.getLatestMessageID(roomID: chatID.uuid) else {
            throw Error.failedToFetchLatestMessage
        }
        
        try await client.advanceReadPointer(
            chatID: chatID,
            to: MessageID(uuid: messageID),
            owner: owner
        )
        
        try database.transaction {
            try $0.clearUnread(chatID: chatID)
        }
        
        changedChats()
    }
    
    // MARK: - Group Chat -
    
    func chatFor(roomNumber: RoomNumber) async throws -> ChatID? {
        if let id = try? database.getRoomID(roomNumber: roomNumber) {
            return ChatID(data: id.data)
        }
        return nil
    }
    
    func startGroupChat(amount: Kin, destination: PublicKey) async throws -> ChatID {
        let intentID = try await paymentClient.payForRoom(
            request: .create(userID, amount),
            organizer: organizer,
            destination: destination
        )
        
        let description = try await client.startGroupChat(
            with: [userID],
            intentID: intentID,
            owner: owner
        )
        
        let roomID = description.metadata.id
        let messages = try await syncMessagesBackwards(for: roomID)
        
        try database.transaction {
            try $0.insertRooms(rooms: [description.metadata])
            try $0.insertMembers(members: description.members, chatID: roomID)
            try $0.insertMessages(messages: messages, chatID: roomID)
        }
        
        changedChats()
        
        return roomID
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
        
        let description = try await client.joinGroupChat(
            chatID: chatID,
            intentID: intentID,
            owner: owner
        )
        
        let messages = try await syncMessagesBackwards(for: chatID)
        
        try database.transaction {
            try $0.insertRooms(rooms: [description.metadata])
            try $0.insertMembers(members: description.members, chatID: chatID)
            try $0.insertMessages(messages: messages, chatID: chatID)
        }
        
        changedChats()
        
        return chatID
    }
    
    func muteUser(userID: UserID, chatID: ChatID) async throws {
        try await client.muteUser(userID: userID, chatID: chatID, owner: owner)
        try database.transaction {
            try $0.muteMember(userID: userID.uuid, muted: true)
        }
    }
    
    func reportMessage(userID: UserID, messageID: MessageID) async throws {
        try await client.reportMessage(userID: userID, messageID: messageID, owner: owner)
    }
    
    func leaveChat(chatID: ChatID) async throws {
        try await client.leaveChat(chatID: chatID, owner: owner)
        
        try database.transaction {
            try $0.deleteRoom(chatID: chatID)
        }
        
        changedChats()
    }
    
    func changeCover(chatID: ChatID, newCover: Kin) async throws {
        try await client.changeCover(chatID: chatID, newCover: newCover, owner: owner)
        let chat = try await client.fetchChat(for: .chatID(chatID), owner: owner)
        
        try database.transaction {
            try $0.insertRooms(rooms: [chat.metadata])
            try $0.insertMembers(members: chat.members, chatID: chatID)
        }
        
        changedChats()
    }
    
    // MARK: - Changes -
    
    private func changedChats() {
        chatsDidChange += 1
    }
}

// MARK: - Errors -

extension ChatController {
    enum Error: Swift.Error {
        case failedToFetchLatestMessage
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
