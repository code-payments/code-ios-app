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
    
    @Published private(set) var isSyncInProgress: Bool = false
    
    var isRegistered: Bool {
        session.isRegistered
    }
    
    let owner: KeyPair
    
    private let session: Session
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
    
    init(session: Session, client: FlipchatClient, paymentClient: Client, organizer: Organizer) {
        self.session   = session
        self.userID    = session.userID
        self.client    = client
        self.paymentClient = paymentClient
        self.organizer = organizer
        self.owner     = organizer.ownerKeyPair
        self.database  = try! Self.initializeDatabase(userID: userID)
        
        streamChatEvents()
        
        database.commit = { [weak self] in
            self?.chatsChanged()
        }
        
        startSync()
    }
    
    static func initializeDatabase(userID: UserID) throws -> Database {
        // Currently we don't do migrations so every time
        // the user version is outdated, we'll rebuild the
        // database during sync.
        let userVersion = (try? Database.userVersion(userID: userID)) ?? 0
        let currentVersion = try InfoPlist.value(for: "SQLiteVersion").integer()
        if currentVersion > userVersion {
            try Database.deleteStore(for: userID)
            trace(.failure, components: "Outdated user version, deleted database.")
            try Database.setUserVersion(version: currentVersion, userID: userID)
        }
        
        return try Database(url: .store(for: userID))
    }
    
    deinit {
        trace(.warning, components: "Deallocating ChatController.")
    }
    
    private func chatsChanged() {
        chatsDidChange += 1
        print("[CHATS CHANGED]")
    }
    
    func prepareForLogout() {
        destroyChatStream()
    }
    
    // MARK: - App Life Cycle -
    
    func sceneDidBecomeActive() {
        streamChatEvents()
        startSync()
    }
    
    func sceneDidEnterBackground() {
        destroyChatStream()
    }
    
    // MARK: - Database -
    
    func getMember(userID: UserID, roomID: ChatID) throws -> MemberRow? {
        try database.getUser(userID: userID.uuid, roomID: roomID.uuid)
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
    
    func getPointer(userID: UserID, chatID: ChatID) throws -> MessagePointer? {
        try database.getPointer(userID: userID.uuid, roomID: chatID.uuid)
    }
    
    // MARK: - Sync -
    
    func startSync() {
        Task {
            try await sync()
        }
    }
    
    private func sync() async throws {
        guard !isSyncInProgress else {
            print("Attempt to start sync when it's already in progress, ignoring.")
            return
        }
        
        trace(.send)
        
        isSyncInProgress = true
        
        let chats = try await client.fetchChats(owner: owner)
        
        await withThrowingTaskGroup(of: Void.self) { group in
            for chat in chats {
                group.addTask { [weak self] in
                    guard let self else { return }
                    let description = try await client.fetchChat(
                        for: .chatID(chat.id),
                        owner: owner
                    )
                    
                    let latestBatchMessageID = try await database.getLatestMessageID(roomID: chat.id.uuid, batchOnly: true)
                    
                    let messages: [Chat.Message]
                    if let latestBatchMessageID {
                        messages = try await syncMessagesForward(for: chat.id, from: latestBatchMessageID)
                    } else {
                        messages = try await syncMessagesBackwards(for: chat.id)
                    }
                    
                    try await insert(chat: description, messages: messages, silent: true)
                }
            }
        }
        
        isSyncInProgress = false
        
        // We silence all transactions and defer
        // the UI updates until all sync tasks
        // above are finished.
        chatsChanged()
    }
    
    func syncChatAndMembers(for chatID: ChatID) async throws {
        let description = try await client.fetchChat(
            for: .chatID(chatID),
            owner: owner
        )
        
        try insert(chat: description)
    }
    
    private func syncMessagesBackwards(for chatID: ChatID, from messageID: UUID? = nil) async throws -> [Chat.Message] {
        let messages = try await client.fetchMessages(
            chatID: chatID,
            owner: owner,
            query: PageQuery(
                order: .desc,
                pagingToken: messageID,
                pageSize: 512
            )
        )
        
        print("[SYNC] BACKWARD: \(messages.count) messages from: \(messageID?.uuidString ?? "nil")")
        return messages
    }
    
    private func syncMessagesForward(for chatID: ChatID, from messageID: UUID) async throws -> [Chat.Message] {
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
        
        print("[SYNC] FORWARD: \(container.count) messages from: \(messageID.uuidString)")
        return container
    }
    
    // MARK: - Chat Stream -
    
    private func streamChatEvents() {
        guard chatStream == nil else {
            // Stream already open
            return
        }
        
        destroyChatStream()
        
        chatStream = client.streamChatEvents(owner: owner) { [weak self] result in
            switch result {
            case .success(let updates):
                self?.receive(updates: updates)
                
            case .failure:
                self?.reconnectChatStream(after: 500)
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
        chatStream = nil
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
        try database.transaction {
            try $0.insertRooms(rooms: [metadata])
            print("[STREAM] Metadata: \(metadata.id.uuid)")
        }
    }
    
    private func update(chatID: ChatID, withMembers members: [Chat.Member]) throws {
        guard !members.isEmpty else {
            return
        }
        
        try database.transaction {
            try $0.insertMembers(members: members, chatID: chatID)
            print("[STREAM] Members: \(members.count == 1 ? members[0].id.uuid.uuidString : members.count.description)")
        }
    }
    
    private func update(chatID: ChatID, withLastMessage message: Chat.Message) throws {
        
        try database.transaction {
            try $0.insertMessages(messages: [message], chatID: chatID, isBatch: false)
            print("[STREAM] Message: \(message.id.uuid) - \(message.content.prefix(50))")
        }
    }
    
    private func update(chatID: ChatID, withPointerUpdate update: Chat.BatchUpdate.PointerUpdate) throws {
//        trace(.success, components: "Pointer: \(update)")
    }
    
    private func update(chatID: ChatID, withTypingUpdate update: Chat.BatchUpdate.TypingUpdate) throws {
//        trace(.success, components: "Typing: \(update)")
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
            try $0.insertMessages(messages: filteredMessages, chatID: chatID, isBatch: false)
        }
    }
    
    func sendMessage(text: String, for chatID: ChatID) async throws {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let deliveredMessage = try await client.sendMessage(
            chatID: chatID,
            owner: owner,
            text: trimmedText
        )
        
        try database.transaction {
            try $0.insertMessages(messages: [deliveredMessage], chatID: chatID, isBatch: false)
        }
    }
    
    func advanceReadPointerToLatest(for chatID: ChatID) async throws {
        guard let messageID = try database.getLatestMessageID(roomID: chatID.uuid, batchOnly: false) else {
            throw Error.failedToFetchLatestMessage
        }
        
        let userID = userID.uuid
        
        try await client.advanceReadPointer(
            chatID: chatID,
            to: MessageID(uuid: messageID),
            owner: owner
        )
        
        try database.transaction {
            try $0.clearUnread(chatID: chatID)
            try $0.insertPointer(
                kind: .read,
                userID: userID,
                roomID: chatID.uuid,
                messageID: messageID
            )
        }
    }
    
    // MARK: - Group Chat -
    
    func localChatFor(roomNumber: RoomNumber) async throws -> ChatID? {
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
        
        let messages = try await syncMessagesBackwards(for: description.metadata.id)
        
        try insert(
            chat: description,
            messages: messages
        )
        
        return description.metadata.id
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
        
        try insert(
            chat: description,
            messages: messages
        )
        
        return chatID
    }
    
    func watchRoom(chatID: ChatID) async throws -> ChatID {
        let description = try await client.joinGroupChat(
            chatID: chatID,
            intentID: nil, // No payment to watch
            owner: owner
        )
        
        let messages = try await syncMessagesBackwards(for: chatID)
        
        try insert(
            chat: description,
            messages: messages
        )
        
        return chatID
    }
    
    func muteUser(userID: UserID, chatID: ChatID) async throws {
        try await client.muteUser(userID: userID, chatID: chatID, owner: owner)
        try database.transaction {
            try $0.muteMember(userID: userID.uuid, muted: true)
        }
    }
    
    func muteChat(chatID: ChatID, muted: Bool) async throws {
        try await client.muteChat(chatID: chatID, muted: muted, owner: owner)
        try database.transaction {
            try $0.muteChat(roomID: chatID.uuid, muted: muted)
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
    }
    
    func changeCover(chatID: ChatID, newCover: Kin) async throws {
        try await client.changeCover(chatID: chatID, newCover: newCover, owner: owner)
        let chat = try await client.fetchChat(for: .chatID(chatID), owner: owner)
        
        try insert(chat: chat)
    }
    
    // MARK: - Changes -
    
    private func insert(chat: ChatDescription, messages: [Chat.Message]? = nil, silent: Bool = false) throws {
        try database.transaction(silent: silent) {
            try $0.insertRooms(rooms: [chat.metadata])
            try $0.insertMembers(members: chat.members, chatID: chat.metadata.id)
            if let messages {
                try $0.insertMessages(messages: messages, chatID: chat.metadata.id, isBatch: true)
            }
        }
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
        session: .mock,
        client: .mock,
        paymentClient: .mock,
        organizer: .mock2
    )
}
