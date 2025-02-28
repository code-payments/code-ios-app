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
    
    func getMembers(roomID: ChatID) throws -> [MemberRow] {
        try database.getUsers(roomID: roomID.uuid)
    }
    
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
    
    func getTipUsers(messageID: MessageID) throws -> [TipUser] {
        try database.getTipUsers(messageID: messageID.uuid)
    }
    
    func getPointer(userID: UserID, chatID: ChatID) throws -> MessagePointer? {
        try database.getPointer(userID: userID.uuid, roomID: chatID.uuid)
    }
    
    func getUserProfile(userID: UserID) throws -> UserProfileRow? {
        try database.getUserProfile(userID: userID.uuid)
    }
    
    // MARK: - Sync -
    
    func startSync() {
        Task {
            try await sync(showProgress: true)
        }
    }
    
    @discardableResult
    func sync(showProgress: Bool = false) async throws -> Int {
        guard !isSyncInProgress else {
            print("Attempt to start sync when it's already in progress, ignoring.")
            return 0
        }
        
        trace(.send)
        
        if showProgress {
            isSyncInProgress = true
        }
        
        defer {
            isSyncInProgress = false
        }
        
        // 1. Fetch the chat list. For each of these chats
        // we'll need to fetch messages separately
        let chats = try await client.fetchChats(owner: owner)
        var totalSynced = 0

        try await withThrowingTaskGroup(of: Int.self) { group in
            for chat in chats {
                group.addTask { [weak self] in
                    guard let self else { return 0 }
                    
                    // 2. Sync the messages for each chat
                    let messages = try await syncChatAndMessages(for: chat.id)
                    
                    return messages.count
                }
            }
            
            for try await messageCount in group {
                totalSynced += messageCount
            }
        }
        
        // 3. Global pass to update isDeleted for all
        // messages that have been referenced in
        // 'delete message' message types
        try database.transaction {
            try $0.markMessagesDeletedIfNeeded()
        }

        return totalSynced
    }
    
    func syncChatAndMessages(for chatID: ChatID) async throws -> [Chat.Message] {
        let description = try await client.fetchChat(
            for: .chatID(chatID),
            owner: owner
        )
        
        let latestBatchMessageID = try latestMessageID(for: chatID, batchOnly: true)
        
        let messages: [Chat.Message]
        let isInitialSync: Bool
        if let latestBatchMessageID {
            messages = try await syncMessagesForward(for: chatID, from: latestBatchMessageID)
            isInitialSync = false
        } else {
            messages = try await syncMessagesBackwards(for: chatID)
            isInitialSync = true
        }
        
        let userID = userID.uuid
        try insert(chat: description, messages: messages, silent: true) { [database] in

            if isInitialSync {
                // Runs in the same transaction as the above insert
                if let mostRecentMessage = messages.first {
                    try database.insertPointer(
                        kind: .read,
                        userID: userID,
                        roomID: chatID.uuid,
                        messageID: mostRecentMessage.id.uuid
                    )
                    
                    print("[SYNC] Set pointer for room: \(mostRecentMessage.id.uuid)")
                }
            }
        }
        
        return messages
    }
    
    func syncChatAndMembers(for chatID: ChatID) async throws {
        let description = try await client.fetchChat(
            for: .chatID(chatID),
            owner: owner
        )
        
        try insert(chat: description)
    }
    
    private func syncMessagesBackwards(for chatID: ChatID, from messageID: UUID? = nil) async throws -> [Chat.Message] {
        var container: [Chat.Message] = []
        
        var fetchMore = false
        var earliestPointerID: MessageID?
        var earliestMessageID: UUID? = messageID
        
        repeat {
            let messages = try await client.fetchMessages(
                chatID: chatID,
                owner: owner,
                query: PageQuery(
                    order: .desc,
                    pagingToken: earliestMessageID,
                    pageSize: 1024
                )
            )
            
            container.append(contentsOf: messages)
            
            // Find the earliest message reference
            earliestPointerID = messages.findOldestReferenceID()
            
            // Check to see if the oldest message we fetched
            // is older than the reference, otherwise we have
            // to keep fetching messages.
            if
                let earliestPointerID,
                let lastMessage = messages.last,
                earliestPointerID < lastMessage.id
            {
                earliestMessageID = lastMessage.id.uuid
                fetchMore = true
            } else {
                fetchMore = false
            }
            
        } while fetchMore
        
        print("[SYNC] BACKWARD: \(container.count) messages from: \(messageID?.uuidString ?? "nil")")
        return container
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
        let chatID = batchUpdate.chatID.uuid
        
        // Update the database in a single transaction
        // to minimize any UI reloads and updates
        try database.transaction {
            
            // 1. Apply all room batch updates
            for chatUpdate in batchUpdate.chatUpdates {
                switch chatUpdate {
                case .fullRefresh(let metadata):
                    try $0.insertRooms(rooms: [metadata])
                    print("[STREAM] Room updated (full): \(metadata.id.uuid)")
                    
                case .unreadCount(let unreadCount, let hasMore):
                    try $0.updateUnreadCount(roomID: chatID, unreadCount: unreadCount, hasMore: hasMore)
                    print("[STREAM] Unread count updated: \(unreadCount)")
                    
                case .displayName(let displayName):
                    try $0.updateDisplayName(roomID: chatID, displayName: displayName)
                    print("[STREAM] Display name updated: \(displayName)")
                    
                case .coverCharge(let cover):
                    try $0.updateCoverCharge(roomID: chatID, cover: cover)
                    print("[STREAM] Cover updated: \(cover)")
                    
                case .openStateChanged(let isOpen):
                    try $0.updateOpenState(roomID: chatID, isOpen: isOpen)
                    print("[STREAM] Room open: \(isOpen)")
                    break
                    
                case .lastActivity:
                    // Ignore
                    break
                }
            }
            
            // 2. Apply all member batch updates
            for memberUpdate in batchUpdate.memberUpdates {
                switch memberUpdate {
                case .fullRefresh(let members):
                    try $0.insertMembers(members: members, roomID: chatID)
                    print("[STREAM] Members updated (full): \(members.count)")
                    
                case .invidualRefresh(let member), .joined(let member):
                    try $0.insertMembers(members: [member], roomID: chatID)
                    print("[STREAM] Member updated: \(member.identity.displayName ?? "<unknown>")")
                    
                case .left(let userID), .removed(let userID):
                    try $0.deleteMember(userID: userID.uuid, roomID: chatID)
                    print("[STREAM] Member deleted")
                    
                case .muted(let userID):
                    try $0.setMemberMuted(userID: userID.uuid, roomID: chatID, muted: true)
                    print("[STREAM] Member muted")
                    
                case .promoted(let userID):
                    try $0.setMemberCanSend(userID: userID.uuid, roomID: chatID, canSend: true)
                    print("[STREAM] Member \(userID.uuid) now speaker (promoted)")
                    
                case .demoted(let userID):
                    try $0.setMemberCanSend(userID: userID.uuid, roomID: chatID, canSend: false)
                    print("[STREAM] Member \(userID.uuid) now listener (demoted)")
                    
                case .identityChanged(let userID, let identity):
                    if let identity {
                        try $0.insertIdentity(identity: identity, userID: userID.uuid)
                        print("[STREAM] Member \(userID.uuid) identity added: \(identity.socialProfile?.kind.rawValue ?? -1)")
                    } else {
                        try $0.deleteProfile(userID: userID.uuid)
                        print("[STREAM] Member \(userID.uuid) identity removed.")
                    }
                }
            }
            
            // 3. Apply last message
            if let lastMessage = batchUpdate.lastMessage {
                try $0.insertMessages(messages: [lastMessage], roomID: chatID, isBatch: false, currentUserID: userID.uuid)
                print("[STREAM] Message: \(lastMessage.content)")
            }
        }
        
        // TODO: Add pointer and typing updates as needed
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
            try $0.insertMessages(messages: filteredMessages, roomID: chatID.uuid, isBatch: false, currentUserID: userID.uuid)
        }
    }
    
    func solicitMessage(text: String, chatID: ChatID, hostID: UserID, amount: Kin) async throws {
        let destination = try await client.fetchPaymentDestination(userID: hostID)
        
        let intentID = try await paymentClient.payForMessage(
            amount: amount,
            chatID: chatID,
            userID: userID,
            organizer: organizer,
            destination: destination
        )
        
        let deliveredMessage = try await client.solicitMessage(
            chatID: chatID,
            owner: owner,
            text: text,
            intentID: intentID
        )
        
        try insertDeliveredMessage(
            userID: userID,
            chatID: chatID,
            message: deliveredMessage
        )
    }
    
    func sendMessage(text: String, for chatID: ChatID, replyingTo: MessageID? = nil) async throws {
        let deliveredMessage = try await client.sendMessage(
            chatID: chatID,
            owner: owner,
            text: text,
            replyingTo: replyingTo
        )
        
        try insertDeliveredMessage(
            userID: userID,
            chatID: chatID,
            message: deliveredMessage
        )
    }
    
    func sendTip(amount: Kin, chatID: ChatID, messageID: MessageID, messageUserID: UserID) async throws {
        let destination = try await client.fetchPaymentDestination(userID: messageUserID)
        
        let intentID = try await paymentClient.sendTipForMessage(
            tipper: userID,
            amount: amount,
            chatID: chatID,
            messageID: messageID,
            organizer: organizer,
            destination: destination
        )
        
        let deliveredMessage = try await client.sendTip(
            chatID: chatID,
            messageID: messageID,
            owner: owner,
            amount: amount,
            intentID: intentID
        )
        
        try insertDeliveredMessage(
            userID: userID,
            chatID: chatID,
            message: deliveredMessage
        )
    }
    
    private func insertDeliveredMessage(userID: UserID, chatID: ChatID, message: Chat.Message) throws {
        try database.transaction {
            try $0.insertMessages(messages: [message], roomID: chatID.uuid, isBatch: false, currentUserID: userID.uuid)
            
            // TODO: This pointer update should probably be elsewhere
            try $0.insertPointer(
                kind: .read,
                userID: userID.uuid,
                roomID: chatID.uuid,
                messageID: message.id.uuid
            )
        }
    }
    
    func deleteMessage(messageID: MessageID, for chatID: ChatID) async throws {
        let deliveredMessage = try await client.deleteMessage(
            messageID: messageID,
            chatID: chatID,
            owner: owner
        )
        
        try database.transaction {
            try $0.insertMessages(messages: [deliveredMessage], roomID: chatID.uuid, isBatch: false, currentUserID: userID.uuid)
        }
    }
    
    func latestMessageID(for chatID: ChatID, batchOnly: Bool) throws -> UUID? {
        try database.getLatestMessageID(roomID: chatID.uuid, batchOnly: batchOnly)
    }
    
    func advanceReadPointerToLatest(for chatID: ChatID) async throws {
        guard let messageID = try latestMessageID(for: chatID, batchOnly: false) else {
            throw Error.failedToFetchLatestMessage
        }
        
        let userID = userID.uuid
        
        try await client.advanceReadPointer(
            chatID: chatID,
            to: MessageID(uuid: messageID),
            owner: owner
        )
        
        try database.transaction {
            try $0.clearUnread(roomID: chatID.uuid)
            try $0.insertPointer(
                kind: .read,
                userID: userID,
                roomID: chatID.uuid,
                messageID: messageID
            )
        }
    }
    
    // MARK: - Users -
    
    func muteUser(userID: UserID, chatID: ChatID) async throws {
        try await client.muteUser(userID: userID, chatID: chatID, owner: owner)
        try database.transaction {
            try $0.setMemberMuted(
                userID: userID.uuid,
                roomID: chatID.uuid,
                muted: true
            )
        }
    }
    
    func setUserBlocked(userID: UserID, blocked: Bool) async throws {
//        try await client.blockUser(userID: userID, chatID: chatID, owner: owner)
        try database.transaction {
            try $0.setUserBlocked( // Not member, user
                userID: userID.uuid,
                blocked: blocked
            )
        }
    }
    
    func reportMessage(userID: UserID, messageID: MessageID) async throws {
        try await client.reportMessage(userID: userID, messageID: messageID, owner: owner)
    }
    
    func promoteUser(userID: UserID, chatID: ID) async throws {
        try await client.promoteUser(chatID: chatID, userID: userID, owner: owner)
        try database.transaction {
            try $0.setMemberCanSend(
                userID: userID.uuid,
                roomID: chatID.uuid,
                canSend: true
            )
        }
    }
    
    func demoteUser(userID: UserID, chatID: ID) async throws {
        try await client.demoteUser(chatID: chatID, userID: userID, owner: owner)
        try database.transaction {
            try $0.setMemberCanSend(
                userID: userID.uuid,
                roomID: chatID.uuid,
                canSend: false
            )
        }
    }
    
    // MARK: - Chat -
    
    func localChatFor(roomNumber: RoomNumber) async throws -> ChatID? {
        if let id = try? database.getRoomID(roomNumber: roomNumber) {
            return ChatID(data: id.data)
        }
        return nil
    }
    
    func startGroupChat(name: String, amount: Kin, destination: PublicKey) async throws -> ChatID {
        let intentID = try await paymentClient.payForRoom(
            request: .create(userID, amount),
            organizer: organizer,
            destination: destination
        )
        
        let description = try await client.startGroupChat(
            name: name,
            users: [userID],
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
        
        let hostProfile = try await client.fetchProfile(userID: description.metadata.ownerUser)
        
        let host = Chat.Identity(
            displayName: hostProfile.displayName,
            avatarURL: nil,
            socialProfile: hostProfile.socialProfile
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
    
    func muteChat(chatID: ChatID, muted: Bool) async throws {
        try await client.muteChat(chatID: chatID, muted: muted, owner: owner)
        try database.transaction {
            try $0.muteRoom(
                roomID: chatID.uuid,
                muted: muted
            )
        }
    }
    
    func leaveChat(chatID: ChatID) async throws {
        try await client.leaveChat(chatID: chatID, owner: owner)
        
        try database.transaction {
            try $0.deleteRoom(roomID: chatID.uuid)
        }
    }
    
    func changeCover(chatID: ChatID, newCover: Kin) async throws {
        try await client.setMessageFee(chatID: chatID, newFee: newCover, owner: owner)
        let chat = try await client.fetchChat(for: .chatID(chatID), owner: owner)
        
        try insert(chat: chat)
    }
    
    func changeRoomName(chatID: ChatID, newName: String) async throws {
        try await client.changeRoomName(chatID: chatID, newName: newName, owner: owner)
        let chat = try await client.fetchChat(for: .chatID(chatID), owner: owner)
        
        try insert(chat: chat)
    }
    
    func changeRoomOpenState(chatID: ChatID, open: Bool) async throws {
        if open {
            try await client.openRoom(chatID: chatID, owner: owner)
        } else {
            try await client.closeRoom(chatID: chatID, owner: owner)
        }
        
        try database.transaction {
            try $0.updateOpenState(roomID: chatID.uuid, isOpen: open)
        }
    }
    
    // MARK: - Social -
    
    func linkSocialAccount(token: String) async throws {
        let profile = try await client.linkSocialAccount(token: token, owner: owner)
        try database.transaction {
            try $0.insertProfile(profile: profile, userID: userID.uuid)
        }
    }
    
    func unlinkSocialAccount(socialID: String) async throws {
        try await client.unlinkSocialAccount(socialID: socialID, owner: owner)
        try database.transaction {
            try $0.deleteProfile(userID: userID.uuid)
        }
    }
    
    // MARK: - Changes -
    
    private func insert(chat: ChatDescription, messages: [Chat.Message]? = nil, silent: Bool = false, withTransaction block: (() throws -> Void)? = nil) throws {
        try database.transaction(silent: silent) {
            try $0.insertRooms(rooms: [chat.metadata])
            try $0.insertMembers(members: chat.members, roomID: chat.metadata.id.uuid)
            if let messages {
                try $0.insertMessages(messages: messages, roomID: chat.metadata.id.uuid, isBatch: true, currentUserID: userID.uuid)
            }
            
            try block?()
        }
    }
}

// MARK: - Array -

extension Array where Element == Chat.Message {
    func findOldestReferenceID() -> MessageID? {
        var earliestPointerID: MessageID?
        forEach {
            if let ref = $0.referenceMessageID {
                guard earliestPointerID != nil else {
                    earliestPointerID = ref
                    return
                }
                
                // Only assign references that
                // are older to get the oldest
                // reference in this set.
                if ref < earliestPointerID! {
                    earliestPointerID = ref
                }
            }
        }
        return earliestPointerID
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
