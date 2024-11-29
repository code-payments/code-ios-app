//
//  ChatStore.swift
//  Code
//
//  Created by Dima Bart on 2024-11-06.
//

import Foundation
import SwiftData
import FlipchatServices

actor ChatStore: ModelActor {
    
    let modelContainer: ModelContainer
    let modelExecutor: any ModelExecutor
    
    private let userID: UserID
    private let owner: KeyPair
    private let client: FlipchatClient
    
    private var modelContext: ModelContext {
        modelExecutor.modelContext
    }

    // MARK: - Init -
    
    init(container: ModelContainer, userID: UserID, owner: KeyPair, client: FlipchatClient) async {
        self.userID = userID
        self.owner = owner
        self.client = client
        self.modelContainer = container
        let context = ModelContext(container)
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: context)
    }
    
    func fetchAndInsertSelf() async throws {
        let name = try await client.fetchProfile(userID: userID)
        
        try modelContext.transaction {
            let identity = try fetchOrCreateIdentity(
                id: userID.uuid,
                name: name
            )
            
            trace(.success, components: "Created self identity: \(identity.displayName)")
        }
    }
    
//    private func mockupChats(owner: KeyPair, in chat: Chat) {
//        let messageCount = 225
//        let senteces = lorem.components(separatedBy: ".").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
//        let start = Int.random(in: 0..<senteces.count / 2)
//        let subset = senteces[start...]
//        
//        Task {
//            
//            var messages: [Chat.Message] = chat.messages
//            
//            for (index, text) in subset.enumerated() {
//                let isSelf = index % 2 == 0
//                let message = try await client.sendMessage(
//                    chatID: chat.id,
//                    owner: owner,
//                    content: .text(text)
//                )
//                messages.append(message)
//            }
//            
//            chat.messages
//        }
//        print(senteces)
//    }
    
    func nuke() throws {
//        do {
//            try FileManager.default.removeItem(at: Self.storeURL)
//        } catch {
//            trace(.failure, components: "Failed to delete persistence store.")
//        }
        do {
            let context = modelContext
            try context.delete(model: pIdentity.self)
            try context.delete(model: pChat.self)
            try context.delete(model: pMessage.self)
            try context.delete(model: pMember.self)
//            try context.delete(model: pPointer.self)
            try context.save()
            trace(.warning, components: "Persistence store nuked.")
        } catch {
            trace(.failure, components: "Failed to nuke persistence store.")
            throw error
        }
    }
    
    // MARK: - Stream Updates -
    
    func receive(updates: [Chat.BatchUpdate]) throws {
        try updates.forEach {
            try handleEvent($0)
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
        
        try upsert(chat: metadata, ownerID: metadata.ownerUser)
    }
    
    private func update(chatID: ChatID, withMembers members: [Chat.Member]) throws {
        guard !members.isEmpty else {
            return
        }
        
        trace(.success, components: "Members +\(members.count)")
        
        guard let chat = try fetchSingleChat(serverID: chatID.uuid) else {
            return
        }
        
        try upsert(members: members, in: chat)
    }
    
    private func update(chatID: ChatID, withLastMessage message: Chat.Message) throws {
        trace(.success, components: "Message: \(message.id.description)", "Content: \(message.contents)")
        
        guard let chat = try fetchSingleChat(serverID: chatID.uuid) else {
            return
        }
        
        try upsert(messages: [message], in: chat)
    }
    
    private func update(chatID: ChatID, withPointerUpdate update: Chat.BatchUpdate.PointerUpdate) throws {
        trace(.success, components: "Pointer: \(update)")
    }
    
    private func update(chatID: ChatID, withTypingUpdate update: Chat.BatchUpdate.TypingUpdate) throws {
        trace(.success, components: "Typing: \(update)")
    }
    
//    func streamMessages(chatID: ChatID, messageID: MessageID, owner: KeyPair, completion: @escaping (Result<[Chat.Message], ErrorStreamMessages>) -> Void) -> StreamMessagesReference {
//        client.streamMessages(
//            chatID: chatID,
//            from: messageID,
//            owner: owner,
//            completion: completion
//        )
//    }
    
    func receive(messages: [Chat.Message], for chatID: ChatID) throws {
        let filteredMessages = messages.filter {
            // Filter out any messages sent by self
            // because those are handled directly in
            // the call to `sendMessage(text:for:)`
            !($0.senderID == userID)
        }
        
        try modelContext.transaction {
            guard let chat = try fetchSingleChat(serverID: chatID.uuid) else {
                throw Error.failedToFetchChat
            }
            
            try upsert(messages: filteredMessages, in: chat)
        }
    }
    
    // MARK: - Actions -
    
    func sendMessage(text: String, for chatID: ChatID) async throws {
        guard let chat = try fetchSingleChat(serverID: chatID.uuid) else {
            throw Error.failedToFetchChat
        }
        
        let deliveredMessage = try await client.sendMessage(
            chatID: ID(uuid: chat.serverID),
            owner: owner,
            content: .text(text)
        )
        
        try modelContext.transaction {
            let localMessage = createMessage(
                id: deliveredMessage.id.uuid,
                chatID: chat.serverID,
                text: text
            )
            
            localMessage.update(from: deliveredMessage)
            localMessage.chat = chat
        }
    }
    
    func advanceReadPointerToLatest(for chatID: ChatID) async throws {
        guard let message = try fetchLatestMessage(for: chatID.uuid) else {
            throw Error.failedToFetchLatest
        }
        
        try await client.advanceReadPointer(
            chatID: chatID,
            to: MessageID(uuid: message.serverID),
            owner: owner
        )
        
        // Clear unread count
        
        try modelContext.transaction {
            if let chat = try fetchSingleChat(serverID: chatID.uuid) {
                chat.unreadCount = 0
            }
        }
    }
    
    func startGroupChat(intentID: PublicKey) async throws -> ChatID {
        let metadata = try await client.startGroupChat(
            with: [userID],
            intentID: intentID,
            owner: owner
        )
        
        try modelContext.transaction {
            let chat = try fetchOrCreateChat(for: metadata.id, ownerID: metadata.ownerUser)
            chat.update(from: metadata)
            
            // Shouldn't have any members
            // but remove all to ensure
            chat.members?.removeAll()
            
            if let identity = try fetchSingleIndentity(serverID: userID.uuid) {
                let selfMember = createMember(id: userID.uuid, chatID: chat.serverID)
                selfMember.chat = chat
                selfMember.identity = identity
            }
        }
        
        return metadata.id
    }
    
//    func fetchChat(identifier: ChatIdentifier, hide: Bool) async throws -> ChatID {
//        let (metadata, members) = try await client.fetchChat(
//            for: identifier,
//            owner: owner
//        )
//        
//        let chat = try upsert(chat: metadata) {
//            $0.isHidden = hide
//        }
//        
//        try upsert(members: members, in: chat)
//        
//        try save()
//        return metadata.id
//    }
    
    func joinChat(chatID: ChatID, intentID: PublicKey?) async throws -> ChatID {
        let description = try await client.joinGroupChat(
            chatID: chatID,
            intentID: intentID,
            owner: owner
        )
        
        // 1. Insert chat
        let chat = try upsert(chat: description.metadata, ownerID: description.metadata.ownerUser)
        // If the chat already exists,
        // it might've been deleted
        chat.deleted = false
        
        // 2. Insert chat members
        try upsert(members: description.members, in: chat)
        
        // 3. Insert messages
        try await syncMessages(for: chat)
        
        try save()
        return description.metadata.id
    }
    
    func leaveChat(chatID: ChatID) async throws {
        try await client.leaveChat(chatID: chatID, owner: owner)
        
        if let existingChat = try fetchSingleChat(serverID: chatID.uuid) {
            existingChat.deleted = true
        }
        
        try save()
    }
    
    func changeCover(chatID: ChatID, newCover: Kin) async throws {
        guard let chat = try fetchSingleChat(serverID: chatID.uuid) else {
            throw Error.failedToFetchChat
        }
        
        chat.coverQuarks = newCover.quarks
        
        try await client.changeCover(chatID: chatID, newCover: newCover, owner: owner)
        
        try save()
    }
    
    // MARK: - Sync -
    
    func sync() async throws {
        trace(.send)
        
        let chats = try await client.fetchChats(owner: owner)
        for chat in chats {
            Task {
                try await syncChat(chatID: chat.id)
            }
        }
        
        trace(.write, components: "Inserted \(chats.count) chats.")
        try save()
    }
    
    private func syncChat(chatID: ChatID) async throws {
        let description = try await client.fetchChat(
            for: .chatID(chatID),
            owner: owner
        )
        
        // 1. Insert chat
        let chat = try upsert(chat: description.metadata, ownerID: description.metadata.ownerUser)
        chat.deleted = false
        
        // 2. Insert chat members
        try upsert(members: description.members, in: chat)
        
        // 3. Sync messages
        try await syncMessages(for: chat)
    }
    
    private func syncMessages(for chat: pChat) async throws {
        var cursor: ChatID? = nil
        
        let pageSize = 1024
        
        var hasMoreChats = true
        while hasMoreChats {
            let messages = try await client.fetchMessages(
                chatID: ID(uuid: chat.serverID),
                owner: owner,
                query: PageQuery(
                    order: .desc,
                    pagingToken: cursor,
                    pageSize: pageSize
                )
            )
            
            // TODO: Insert Self member into message
            
            if !messages.isEmpty {
                try upsert(messages: messages, in: chat)
                try save()
                
                cursor = messages.last!.id
            }
            
            hasMoreChats = messages.count == pageSize
        }
    }
    
    // MARK: - Upsert -
    
    @discardableResult
    private func upsert(chat: Chat.Metadata, ownerID: UserID) throws -> pChat {
        let c = try fetchOrCreateChat(for: chat.id, ownerID: ownerID)

        c.update(from: chat)
        
        return c
    }
    
    private func fetchOrCreateChat(for chatID: ChatID, ownerID: UserID) throws -> pChat {
        if let existingChat = try fetchSingleChat(serverID: chatID.uuid) {
            return existingChat
        } else {
            return createChat(id: chatID.uuid, ownerID: ownerID.uuid)
        }
    }
    
    @discardableResult
    private func createChat(id: UUID, ownerID: UUID) -> pChat {
        let newChat = pChat.new(serverID: id, ownerID: ownerID)
        
        modelContext.insert(newChat)
        
        return newChat
    }
    
    private func upsert(messages: [Chat.Message], in chat: pChat) throws {
        let senderIDs  = Set(messages.compactMap { $0.senderID?.uuid })
        let messageIDs = Set(messages.map { $0.id.uuid })
        
        let membersMap  = try fetchMembers(in: senderIDs)
        let messagesMap = try fetchMessages(in: messageIDs)
        
        var messageToAdd: [UUID: pMessage] = [:]
        
        for message in messages {
            let uuid = message.id.uuid
            
            let sender: pMember?
            if let senderID = message.senderID, let member = membersMap[senderID.uuid] {
                sender = member
            } else {
                sender = nil
            }
            
            if let existingMessage = messagesMap[uuid] {
                existingMessage.update(from: message)
                existingMessage.sender = sender
            } else {
                let newMessage = createMessage(id: uuid, chatID: chat.serverID)
                newMessage.sender = sender
                newMessage.update(from: message)
                messageToAdd[uuid] = newMessage
            }
        }
        
        if !messageToAdd.isEmpty {
            chat.messages?.append(contentsOf: messageToAdd.values)
        }
        
        // Determine the most recent message and update
        // the chat preview message
        let mostRecentMessage = messages.sorted { $0.date < $1.date }.last
        if
            let recentMessage = mostRecentMessage,
            let previewMessage = messageToAdd[recentMessage.id.uuid] ?? messagesMap[recentMessage.id.uuid]
        {
            chat.previewMessage = previewMessage
        }
        
        trace(.write, components: "Inserted \(messages.count) messages.")
    }
    
    @discardableResult
    private func createMessage(id: UUID, chatID: UUID, text: String? = nil) -> pMessage {
        let newMessage = pMessage.new(
            serverID: id,
            chatID: chatID,
            senderID: userID.uuid,
            date: .now,
            text: text
        )
        
        modelContext.insert(newMessage)
        
        return newMessage
    }
    
    // MARK: - Members -
    
    @discardableResult
    private func upsert(members: [Chat.Member], in chat: pChat) throws -> [pMember] {
        let newIDs = Set(members.map { $0.id.uuid })
        let chatID = chat.serverID
        let identities = try fetchIdentities(in: newIDs)
        
        let oldMemberIndex = chat.members?.elementsKeyed(by: \.serverID) ?? [:]
        
        var container: [pMember] = []
        
        for member in members {
            
            // Fetch or create identity
            let existingIdentity = identities[member.id.uuid] ?? createIdentity(
                id: member.id.uuid,
                name: member.identity.displayName
            )
            
            // Create a new member, existing identity
            let m = oldMemberIndex[member.id.uuid] ?? createMember(id: userID.uuid, chatID: chatID)

            m.update(from: member)
            
            // Update relationships
            m.chat = chat
            m.identity = existingIdentity
            
            container.append(m)
        }
        
        chat.insert(members: container)
        
        trace(.write, components: "Inserted \(members.count) members.")
        return container
    }
    
    @discardableResult
    private func createMember(id: UUID, chatID: UUID) -> pMember {
        let newMember = pMember.new(
            serverID: id,
            chatID: chatID
        )
        
        modelContext.insert(newMember)
        
        return newMember
    }
    
    private func fetchOrCreateIdentity(id: UUID, name: String) throws -> pIdentity {
        if let existingIdentity = try fetchSingleIndentity(serverID: id) {
            return existingIdentity
        } else {
            return createIdentity(id: id, name: name)
        }
    }
    
    @discardableResult
    private func createIdentity(id: UUID, name: String) -> pIdentity {
        let identity = pIdentity.new(
            serverID: id,
            displayName: name,
            avatarURL: nil
        )
        
        modelContext.insert(identity)
        
        return identity
    }
    
    // MARK: - Context -
    
    func save() throws {
        try modelContext.save()
    }
}

// MARK: - Queries -

extension ChatStore {
    
    private func fetchCount<T>(for type: T.Type) throws -> Int where T: PersistentModel {
        var query = FetchDescriptor<T>()
        query.fetchLimit = 1
        do {
            return try modelContext.fetchCount(query)
        } catch {
            throw Error.failedToFetchCount
        }
    }
    
    func fetchSingleChatID(roomNumber: RoomNumber) throws -> UUID? {
        var query = FetchDescriptor<pChat>()
        query.predicate = #Predicate<pChat> { $0.roomNumber == roomNumber && $0.deleted == false }
        query.fetchLimit = 1
        do {
            return try modelContext.fetch(query).first?.serverID
        } catch {
            throw Error.failedToFetchSingle
        }
    }
    
    private func fetchSingleChat(serverID: UUID) throws -> pChat? {
        var query = FetchDescriptor<pChat>()
        query.predicate = #Predicate<pChat> { $0.serverID == serverID }
        query.fetchLimit = 1
        do {
            return try modelContext.fetch(query).first
        } catch {
            throw Error.failedToFetchSingle
        }
    }
    
    private func fetchSingleMessage(serverID: UUID) throws -> pMessage? {
        var query = FetchDescriptor<pMessage>()
        query.predicate = #Predicate<pMessage> { $0.serverID == serverID }
        query.fetchLimit = 1
        do {
            return try modelContext.fetch(query).first
        } catch {
            throw Error.failedToFetchSingle
        }
    }
    
    private func fetchSingleMember(serverID: UUID, chatID: UUID) throws -> pMember? {
        var query = FetchDescriptor<pMember>()
        query.predicate = #Predicate<pMember> { $0.serverID == serverID && $0.chatID == chatID }
        query.fetchLimit = 1
        do {
            return try modelContext.fetch(query).first
        } catch {
            throw Error.failedToFetchSingle
        }
    }
    
    private func fetchSingleIndentity(serverID: UUID) throws -> pIdentity? {
        var query = FetchDescriptor<pIdentity>()
        query.predicate = #Predicate<pIdentity> { $0.serverID == serverID }
        query.fetchLimit = 1
        do {
            return try modelContext.fetch(query).first
        } catch {
            throw Error.failedToFetchSingle
        }
    }
    
    private func fetchMembers(in serverIDs: Set<UUID>) throws -> [UUID: pMember] {
        var query = FetchDescriptor<pMember>()
        query.predicate = #Predicate<pMember> { serverIDs.contains($0.serverID) }
        do {
            let members = try modelContext.fetch(query)
            return members.elementsKeyed(by: \.serverID)
        } catch {
            throw Error.failedToFetch
        }
    }
    
    private func fetchMessages(in serverIDs: Set<UUID>) throws -> [UUID: pMessage] {
        var query = FetchDescriptor<pMessage>()
        query.predicate = #Predicate<pMessage> { serverIDs.contains($0.serverID) }
        do {
            let members = try modelContext.fetch(query)
            return members.elementsKeyed(by: \.serverID)
        } catch {
            throw Error.failedToFetch
        }
    }
    
    private func fetchIdentities(in serverIDs: Set<UUID>) throws -> [UUID: pIdentity] {
        var query = FetchDescriptor<pIdentity>()
        query.predicate = #Predicate<pIdentity> { serverIDs.contains($0.serverID) }
        do {
            let members = try modelContext.fetch(query)
            return members.elementsKeyed(by: \.serverID)
        } catch {
            throw Error.failedToFetch
        }
    }
    
    private func fetchLatestChat() throws -> pChat? {
        var query = FetchDescriptor<pChat>()
        query.fetchLimit = 1
        query.sortBy = [.init(\.roomNumber, order: .reverse)]
        do {
            return try modelContext.fetch(query).first
        } catch {
            throw Error.failedToFetchLatest
        }
    }
    
    // MARK: - Typed Fetch -
    
    private func fetchLatestMessage(for chatID: UUID) throws -> pMessage? {
        var query = FetchDescriptor<pMessage>()
        query.predicate = #Predicate<pMessage> { $0.chat?.serverID == chatID }
        query.fetchLimit = 1
        query.sortBy = [.init(\.date, order: .reverse)]
        do {
            return try modelContext.fetch(query).first
        } catch {
            throw Error.failedToFetchLatest
        }
    }
}

extension ChatStore {
    enum Error: Swift.Error {
        case failedToFetch
        case failedToFetchIdentities
        case failedToFetchChat
        case failedToFetchCount
        case failedToFetchLatest
        case failedToFetchSingle
    }
}

let lorem = """
Lorem ipsum dolor sit amet, consectetur adipiscing elit. Mauris ultrices nibh sit amet mi laoreet, vitae ornare lorem lacinia. Vivamus quis posuere velit. Cras cursus justo quis elementum aliquam. Nam metus lacus, condimentum ut luctus sed, auctor sit amet turpis. Vivamus in pharetra justo, quis aliquam nulla. Proin finibus dignissim malesuada. Donec sed hendrerit lacus. Donec in nisi maximus, fermentum dolor a, iaculis augue. Nulla leo turpis, viverra sit amet nibh eu, vehicula placerat ex. Donec et ligula fermentum, tempor odio et, luctus dolor. Donec aliquam eros ex, quis mattis nulla cursus in. Praesent pulvinar augue dictum pulvinar ornare.

Praesent felis ex, blandit vel venenatis sit amet, ultrices ut elit. Vestibulum auctor dolor dui, nec sodales nulla euismod eget. Donec vel efficitur lorem. Morbi facilisis sit amet lacus a vulputate. Fusce in orci eget nisl egestas dignissim vitae nec magna. Curabitur mauris dolor, porta quis malesuada at, mollis sed nulla. Mauris ipsum diam, congue ut mauris ac, dictum euismod ante.

Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia curae; In at ultrices ante. Morbi in tempor risus, sit amet posuere est. Nullam eget massa dignissim nisl blandit rhoncus. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Aenean commodo enim at ornare volutpat. Interdum et malesuada fames ac ante ipsum primis in faucibus. Vestibulum dictum sem sed efficitur volutpat. Donec ante urna, condimentum id congue convallis, ultrices blandit enim. Cras suscipit egestas ipsum, ut malesuada dui imperdiet et. Suspendisse potenti. Sed interdum sollicitudin neque, et auctor risus interdum vel. Phasellus nisi ipsum, sagittis ut ante id, egestas aliquet ipsum. Integer metus purus, dapibus sit amet nunc id, laoreet mattis ligula. Quisque faucibus at ipsum nec dignissim.

In hac habitasse platea dictumst. Etiam quis nibh iaculis nibh dignissim maximus id lacinia tortor. Maecenas hendrerit magna eros, eu commodo tellus facilisis sit amet. Sed magna arcu, porttitor at sapien quis, porttitor varius purus. Vivamus ut felis maximus, euismod odio at, dictum lectus. Vestibulum aliquet convallis mauris, at varius erat lacinia non. Donec id mattis massa, eu volutpat sem. Donec sollicitudin dolor nisi, ac lacinia lacus mattis in. Mauris maximus scelerisque dolor, in cursus mi sollicitudin ac.

Donec convallis elementum nunc, sed finibus ante accumsan in. Quisque sodales ultrices suscipit. Etiam sodales ligula erat, eu consequat turpis suscipit vitae. Integer cursus, felis ut tincidunt tristique, velit velit ornare diam, vel fermentum justo libero eu velit. Duis non sollicitudin ex, eu scelerisque tortor. Sed sodales interdum nisl, sit amet interdum dui dictum sed. In vestibulum commodo ligula, vel feugiat diam elementum quis. Nullam efficitur massa sed enim ornare, fringilla feugiat lectus tempus. Proin placerat neque justo, non ullamcorper arcu consequat et. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia curae; Nulla sit amet varius dui.

Praesent pellentesque gravida purus, at ullamcorper lorem gravida id. Vivamus iaculis felis tellus, eu luctus tortor pretium et. Ut sed scelerisque mauris. Curabitur congue rutrum turpis, id porttitor diam. Curabitur mauris orci, eleifend non gravida vel, tincidunt ac augue. Sed commodo turpis vitae magna hendrerit accumsan. Phasellus nec elit nibh. Suspendisse potenti.

Mauris sit amet tellus turpis. Quisque at imperdiet odio. Aenean ut ipsum a quam lacinia fermentum. In mattis felis placerat mauris convallis, ac porttitor lorem bibendum. Orci varius natoque penatibus et magnis dis parturient montes, nascetur ridiculus mus. Donec consectetur ante vestibulum metus pellentesque ultricies. Nunc vitae elit lacus. Donec vel varius lectus. In vehicula magna quis est faucibus blandit. Aenean in urna nunc. Sed imperdiet augue vel arcu semper, ac porta lacus congue. Donec et nulla at nulla ultrices maximus. Donec commodo consectetur dui. Aenean nunc ligula, pharetra id ullamcorper et, cursus ac sapien.

Quisque accumsan sapien leo, non aliquet lectus mollis eu. Maecenas consectetur lorem sed justo aliquam pulvinar. Nulla facilisi. Nulla placerat pretium metus a interdum. Class aptent taciti sociosqu ad litora torquent per conubia nostra, per inceptos himenaeos. Sed tortor risus, rutrum ut rhoncus id, tincidunt et ante. Proin at tristique nulla. Pellentesque laoreet dui leo, in hendrerit neque venenatis vitae. Nulla facilisi. Duis laoreet massa eu imperdiet laoreet.

Vivamus fringilla leo ac lectus aliquam, efficitur aliquam magna maximus. Donec non viverra ex, vel iaculis justo. Maecenas luctus sem ac sagittis consequat. Sed scelerisque congue dui et laoreet. Nullam eu dui vitae mauris suscipit porta. Morbi euismod ipsum at lobortis ullamcorper. Morbi facilisis ex facilisis est mattis laoreet. Phasellus sollicitudin nulla purus, vestibulum congue magna rutrum non. Fusce porttitor elit lacus, in iaculis risus fringilla id. Integer in sem lobortis, viverra enim non, efficitur ipsum. Nulla quis sapien libero. Proin auctor nunc a enim facilisis, a ullamcorper leo elementum. Etiam vulputate est metus, in ullamcorper odio auctor et. Donec malesuada iaculis leo vel rhoncus.

Vestibulum dapibus augue in magna iaculis placerat. Sed auctor velit sed faucibus molestie. Sed pulvinar neque sit amet lacus mollis feugiat. Quisque porta turpis nec ligula commodo blandit vitae in nisl. Ut bibendum tellus sed libero varius viverra. In erat sem, fermentum eget velit nec, ullamcorper viverra mi. Aliquam ultricies ante at lorem sollicitudin, eu elementum nisl aliquam.

Etiam euismod nec ex a laoreet. Mauris lobortis dolor id varius facilisis. Sed elit ex, vehicula ut auctor non, dapibus quis lectus. Aenean sollicitudin, justo ac interdum pretium, neque mi ultricies neque, eget vehicula urna mauris id ex. Nullam interdum imperdiet tellus quis accumsan. Nunc eu nulla mollis, aliquam turpis elementum, efficitur sem. Integer at urna lectus. Suspendisse nec iaculis turpis. Quisque elit metus, ornare porttitor enim at, bibendum dignissim libero. Suspendisse vel aliquam tortor. Maecenas at dictum nisl. Aenean cursus ex at massa imperdiet aliquam. Suspendisse porta risus a nunc pretium, vel porta neque dictum. Donec posuere nec erat ut tincidunt.

Vestibulum id ante eu nulla dictum egestas. Nam porta blandit nisi eget feugiat. Praesent porttitor porttitor elementum. Donec viverra varius vulputate. Suspendisse potenti. Maecenas ac eros sem. Pellentesque habitant morbi tristique senectus et netus et malesuada fames ac turpis egestas. Aliquam semper vehicula rhoncus. Nullam bibendum, velit et condimentum gravida, eros eros blandit ex, id laoreet est nisl sed risus. Cras sed dolor eros. Proin vestibulum purus eu accumsan iaculis. Maecenas pharetra libero ut est ultrices ornare.

Quisque tincidunt sem nunc. Nunc bibendum placerat lacus, et eleifend elit. Proin sed dui rutrum, pretium felis a, aliquet nisl. Mauris sagittis felis tellus, quis tempor nisl maximus vitae. Curabitur ultricies convallis tempus. Fusce cursus semper euismod. Orci varius natoque penatibus et magnis dis parturient montes, nascetur ridiculus mus. Duis tempus lacus eros, ut tristique sapien luctus a. Ut finibus, ex non iaculis dignissim, magna ex gravida neque, luctus laoreet orci diam sed turpis. Proin molestie imperdiet justo non porta. Praesent auctor elementum commodo. Nulla odio felis, efficitur semper ultrices sed, luctus ut leo.

Duis in urna orci. Suspendisse eget est a sapien euismod pharetra. Phasellus finibus augue ac massa commodo aliquet. Aenean interdum mi sit amet dui viverra pellentesque. Morbi maximus pulvinar placerat. Nulla ac ante vestibulum, lacinia sem vitae, dignissim diam. Nunc elit tortor, lobortis ut pharetra ut, feugiat nec urna. Nulla tortor dolor, vestibulum quis sem vel, hendrerit hendrerit quam. Pellentesque rutrum justo eu elit hendrerit, maximus semper dui venenatis. Nam rutrum vulputate enim sit amet dignissim. Nunc lorem erat, luctus sit amet justo at, consectetur molestie nulla. Sed quis massa ut diam pellentesque pharetra.

Vivamus tincidunt sem sed enim elementum, et luctus est interdum. Aenean aliquet nibh arcu. Aliquam tempus magna velit, nec pharetra dolor suscipit eu. Nulla vehicula ut neque id luctus. In id ipsum eget nulla dapibus facilisis at placerat nisi. Morbi a metus massa. Pellentesque egestas metus sed orci tempor porttitor. Integer at nulla risus. Orci varius natoque penatibus et magnis dis parturient montes, nascetur ridiculus mus. Aenean malesuada nec enim in ultrices. Nam ornare ipsum euismod dapibus dapibus. Proin dictum orci risus. Ut eros erat, vehicula imperdiet eros sed, aliquam porttitor neque. Praesent sit amet dui condimentum, consequat sem eu, vestibulum elit.

Curabitur ut felis neque. Nullam tempus, erat quis viverra laoreet, odio lorem pulvinar leo, non tincidunt nibh tellus vel tellus. Proin velit nisl, aliquet ut porta eu, venenatis et justo. Quisque malesuada at lacus sed scelerisque. Cras fringilla felis enim, et interdum nibh placerat ac. Donec consequat tortor est, ut vestibulum risus molestie eget. Ut felis leo, fringilla sit amet interdum eget, ultrices non ipsum. Maecenas vulputate mattis nunc, vitae pellentesque lacus condimentum ac. Praesent a felis augue. Sed mattis dapibus malesuada. Cras vitae lectus blandit, luctus turpis eu, dapibus metus. Maecenas ultrices risus vitae est ultricies fermentum. Class aptent taciti sociosqu ad litora torquent per conubia nostra, per inceptos himenaeos. Pellentesque id velit nec nibh vestibulum faucibus commodo non metus. Duis tincidunt mauris et aliquam tempus. Maecenas et laoreet dolor, eu finibus ligula.

Donec non sem vitae erat cursus egestas sit amet sed ante. Ut at dolor ac ipsum euismod aliquet. Nam finibus quam quis libero pretium ullamcorper. Pellentesque porttitor, dolor nec laoreet porta, leo orci lacinia sapien, in sagittis nisl magna nec eros. Donec semper faucibus erat. Ut scelerisque, mi non fermentum fringilla, sapien tellus dictum ex, nec feugiat dui velit id ipsum. Aenean luctus eu arcu sed porta. Mauris pulvinar condimentum arcu eget mattis. Cras molestie rutrum urna a ultrices.

Curabitur vel sollicitudin tellus. Aenean finibus commodo lorem, pretium interdum nisi auctor sed. Pellentesque accumsan nisl in orci tempus suscipit. Cras feugiat tristique malesuada. Proin cursus diam id gravida semper. Fusce blandit molestie risus, at convallis massa commodo at. Maecenas aliquam nisl non mauris bibendum facilisis. Nulla facilisi.

Nam malesuada finibus odio aliquet auctor. Sed ullamcorper porttitor nunc, quis volutpat orci volutpat id. Pellentesque vitae nisl vitae neque convallis luctus. Donec hendrerit magna enim. Sed nec accumsan risus. Proin ut felis id ante maximus auctor sed non leo. Pellentesque ullamcorper lectus arcu, id lacinia dolor congue vestibulum. Integer finibus nec felis id semper. Etiam vitae metus et enim sodales auctor. Suspendisse et consequat lacus. Mauris dictum congue risus eu congue. Sed at rutrum arcu. Maecenas pulvinar nulla eu tempus ultricies. Cras tristique at nisl eleifend fermentum.

Nullam scelerisque rutrum tincidunt. Proin sit amet vehicula diam. Orci varius natoque penatibus et magnis dis parturient montes, nascetur ridiculus mus. Sed sit amet tellus at justo sodales auctor eget ac nibh. Quisque malesuada sapien nec elit faucibus sagittis. Ut condimentum commodo diam. Pellentesque vitae euismod mauris.

Quisque metus dui, vestibulum nec ullamcorper et, pellentesque vel dolor. Nullam convallis ut ligula eu aliquam. Sed tristique lobortis molestie. Aenean hendrerit ornare tortor a consequat. Praesent condimentum lectus a mi viverra, nec pulvinar ipsum auctor. Cras vel dolor pharetra, tincidunt diam at, posuere ipsum. Etiam blandit congue diam non consequat. In rhoncus nisl at neque pretium tristique. Proin dictum eu arcu eu semper. Vivamus varius vitae massa quis fringilla. In eget sollicitudin est, in sagittis dolor. Cras nec orci sollicitudin, tristique nisi a, ullamcorper sem. Phasellus aliquam mollis ullamcorper.

Vivamus ut eros vitae metus pellentesque dignissim. Morbi posuere purus ac iaculis consectetur. Fusce aliquet dui et vulputate aliquam. Mauris dictum vehicula erat in sodales. Aenean ut risus dolor. Maecenas vitae nulla ac purus pharetra vehicula eget non diam. Mauris euismod, libero sed vehicula bibendum, magna ante tristique odio, at eleifend dui quam ut justo. Praesent a libero lectus. Pellentesque viverra velit sed urna sagittis, a tincidunt mauris porta. Fusce posuere pretium elit et consectetur. Donec vel finibus urna. In commodo faucibus nunc, et placerat odio interdum at.

Maecenas egestas congue ligula, ut congue lorem fringilla non. Maecenas sit amet dui pretium, convallis elit id, posuere ex. In hac habitasse platea dictumst. Quisque tincidunt rhoncus lectus vitae convallis. Sed arcu quam, cursus eget aliquet sed, convallis vel felis. Aliquam vitae felis vitae magna tincidunt posuere. Nunc ornare orci ut nulla euismod, eget gravida metus semper. Pellentesque convallis dignissim felis sed fermentum. Aliquam massa mauris, tincidunt sit amet tellus id, lobortis porta arcu. Mauris in tincidunt ante. Nunc luctus congue porttitor. Duis sit amet pulvinar neque, vel aliquam elit. Nulla tempor nunc interdum, posuere purus vel, pellentesque elit. Nam ultricies quam eget odio vestibulum, at convallis neque varius.

Sed vel arcu quis turpis interdum aliquet. Aliquam in felis purus. Pellentesque suscipit pellentesque neque, sit amet lobortis odio rutrum a. Morbi lobortis lectus non lorem cursus, id dignissim arcu efficitur. Nullam faucibus eget elit in dignissim. Etiam pulvinar libero a ipsum rhoncus, rhoncus pulvinar lorem luctus. Pellentesque ornare condimentum eros. Fusce quis quam cursus, dapibus ligula eu, laoreet est. Maecenas efficitur aliquet nisi, eget iaculis nibh cursus et. Suspendisse maximus faucibus diam sit amet maximus. Etiam ultrices, neque sit amet vehicula fermentum, libero ligula rhoncus erat, a vehicula mi metus eget neque. Cras varius dui nibh, ut condimentum lorem gravida egestas. Mauris ultrices ex vel diam porta ullamcorper.

Nulla nec ultrices dui. Ut et diam orci. Integer sit amet tincidunt lorem. Fusce aliquam congue justo at consequat. Maecenas sit amet diam nisl. Praesent pharetra condimentum condimentum. Duis venenatis, turpis nec eleifend convallis, ante lectus tempor libero, consectetur fringilla orci velit id elit. Nullam ante nisi, egestas vulputate orci ac, congue elementum nulla.

Nunc non risus sit amet ex finibus pellentesque eu nec risus. Aliquam condimentum iaculis quam id hendrerit. Cras in fermentum nisi. Vivamus pharetra urna ligula, vitae dapibus risus tincidunt vel. Integer augue elit, dignissim eu gravida id, mollis ac eros. Integer pharetra ligula a posuere faucibus. Integer volutpat porttitor viverra. Nam facilisis, erat laoreet malesuada tempor, ligula sem dignissim dui, id gravida enim nunc a quam. Cras non mauris at justo ultrices mattis. Sed quis odio sagittis, pretium purus sed, egestas diam. In lobortis purus et ipsum placerat, a sagittis nibh ullamcorper. Suspendisse sagittis, neque non bibendum tristique, dolor tortor feugiat lacus, sit amet dapibus eros erat in risus.

Curabitur in felis erat. Sed accumsan ipsum at nisl semper, a porta nisl vulputate. Nunc id felis commodo, placerat sem consectetur, feugiat odio. Mauris accumsan ex non mauris feugiat, a faucibus quam vehicula. Vivamus non auctor nisl, at pretium arcu. Aliquam sollicitudin finibus sapien. Vestibulum a ex aliquet nunc dapibus vehicula congue at sem. Nullam sem mi, facilisis sed rutrum quis, sodales eu diam. Suspendisse rutrum felis in sem tincidunt aliquet. Vivamus tincidunt non arcu quis finibus. Pellentesque non elementum elit. Aenean ante ex, facilisis non vulputate vehicula, pharetra nec quam. Praesent egestas vestibulum mattis.

In diam urna, consectetur accumsan tempus id, ullamcorper vel nulla. Suspendisse ut rutrum tortor. Etiam convallis semper nunc eget semper. In nisl massa, euismod eget scelerisque nec, convallis vitae velit. Phasellus ut enim quis felis viverra malesuada. Ut gravida, quam non sodales dignissim, tortor mauris tempor lorem, non lacinia orci orci non ipsum. Nunc a diam quis nibh pharetra congue.

Maecenas pulvinar turpis iaculis sapien venenatis, ac congue nulla lacinia. Maecenas interdum lectus diam, et molestie ligula gravida nec. Ut rhoncus dignissim tortor id mattis. Ut varius ullamcorper augue, quis convallis tortor rhoncus sit amet. Aliquam sit amet facilisis tortor. Nullam suscipit hendrerit elementum. Nam elementum porta felis, ac aliquet elit fermentum sed. Pellentesque consequat lacus id augue blandit facilisis.

Maecenas porttitor laoreet magna. Cras iaculis purus accumsan mattis egestas. Mauris ut elit volutpat nisi varius scelerisque. Phasellus nec efficitur nibh, id tincidunt enim. Morbi dictum bibendum nulla ac euismod. Maecenas nec dapibus odio, a volutpat tortor. Curabitur et sapien sit amet nisl euismod dapibus. Aliquam ac volutpat odio. Etiam laoreet mollis sem lobortis dictum. Maecenas venenatis lacus felis, a dapibus sapien ullamcorper id. Aliquam et augue interdum, finibus ante vel, accumsan enim. In ullamcorper ut sem tempus faucibus. Nullam vel ultricies metus, vel semper dui. Donec ac aliquet sapien. Donec placerat et lacus vitae porttitor. Donec mollis lectus sit amet pellentesque ultrices.

Aenean risus purus, finibus dictum metus eu, gravida gravida nisi. Mauris at felis nulla. Duis congue enim in nulla vehicula tempus. In at metus ut lectus tempus fringilla. Sed suscipit viverra magna, eu volutpat est convallis tempus. In euismod pulvinar euismod. Donec quis nisi ut tellus tristique lacinia eu id mi. Curabitur venenatis, lorem in consectetur faucibus, felis magna tincidunt lacus, non molestie nunc erat sit amet lorem.

Morbi sed nibh eros. Nulla risus metus, aliquet ac leo ut, viverra ultricies sem. Phasellus varius felis a egestas fermentum. Mauris ac turpis neque. Nullam suscipit rutrum metus, vestibulum condimentum urna iaculis vel. Quisque ut congue ipsum, eget pellentesque ipsum. Interdum et malesuada fames ac ante ipsum primis in faucibus. Ut at velit sodales, ornare metus vitae, lobortis lorem. Mauris eget risus sed odio bibendum tincidunt. Nunc egestas magna euismod porta dictum. Fusce id ornare tortor, eu faucibus ligula.

Aenean ultricies odio id augue elementum faucibus. Donec volutpat sem arcu, vitae convallis lacus aliquam ac. Morbi ut tincidunt risus, et porttitor enim. Fusce sed porta nunc, in gravida nisi. Ut at tempus sem. Sed at justo nec ligula semper feugiat. Quisque quis euismod tortor. Fusce eu tortor fermentum, finibus metus ut, interdum massa. Fusce egestas ipsum a nulla auctor, a dictum tellus euismod.

Orci varius natoque penatibus et magnis dis parturient montes, nascetur ridiculus mus. Etiam egestas nec quam et mattis. Curabitur lorem purus, gravida semper mattis vel, venenatis nec nulla. Nam porttitor consectetur odio, nec rutrum ligula semper bibendum. Etiam quis ligula a diam imperdiet pellentesque eu vel ipsum. Aliquam eget lacus sit amet ligula maximus mollis eget a turpis. Suspendisse potenti. Cras mollis ligula et leo mattis, ac faucibus nulla gravida. Curabitur ullamcorper consectetur erat rhoncus mattis. Suspendisse potenti. In placerat justo eget sapien varius finibus. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia curae; Donec vitae odio tempor nulla consectetur imperdiet sed eget nisl. Integer euismod velit a enim cursus lobortis.

Lorem ipsum dolor sit amet, consectetur adipiscing elit. In id volutpat tellus. Vivamus felis tortor, dignissim pharetra lectus at, viverra faucibus libero. In hac habitasse platea dictumst. Sed in tellus semper dui rhoncus volutpat. Curabitur mollis lectus eu orci venenatis, vel sagittis nisi malesuada. Nullam est quam, elementum ac tempus in, venenatis a lacus. Phasellus eget ipsum eu augue suscipit ultrices nec sit amet turpis. Vestibulum sed nisl et massa consequat pulvinar in ac nibh. Donec sit amet pellentesque nulla. Nunc semper orci eget dignissim blandit. Sed rutrum suscipit semper. Morbi at elit nec eros posuere venenatis. Mauris dignissim lorem facilisis mi porta, vitae blandit ipsum laoreet. Morbi consequat augue at purus malesuada viverra. Praesent ut nulla a ex sagittis luctus.

Aliquam vel finibus arcu, eget faucibus massa. Nullam in purus ullamcorper, dapibus mi non, consequat ipsum. Nulla viverra nunc mattis odio dictum sodales. Integer ultricies magna a efficitur aliquet. Pellentesque facilisis nunc in ornare tincidunt. Interdum et malesuada fames ac ante ipsum primis in faucibus. Aenean volutpat sollicitudin iaculis. Vivamus interdum augue vitae tortor maximus luctus. Morbi tristique odio eget nisi pulvinar bibendum. Pellentesque at tincidunt tellus, eu sagittis mauris. Curabitur faucibus gravida facilisis. Morbi nec est vel erat elementum consequat. In metus metus, vestibulum ut interdum a, faucibus a tortor. Donec consequat quam vel gravida suscipit.

Donec dictum nec orci et egestas. Nunc ut tortor in nibh tempus posuere ut in lectus. Nulla tempor porta commodo. Nunc ac mattis quam. Quisque fringilla lacus ac nulla hendrerit, et ullamcorper nunc ultricies. Mauris urna orci, cursus a ante placerat, elementum dictum dui. Etiam imperdiet mattis neque, sit amet malesuada massa. Duis eget ex vulputate, sodales augue non, efficitur augue. Donec sagittis eget felis ac gravida.

Maecenas semper, diam vel suscipit blandit, ligula metus blandit ligula, vel lacinia nibh tellus eu sem. Morbi et sapien ac nisi dignissim convallis ac consectetur ante. Sed sed ullamcorper dolor. Nunc eget bibendum erat. Morbi vitae urna a purus scelerisque convallis id interdum leo. Maecenas urna lectus, ullamcorper sed augue sit amet, porttitor fringilla turpis. Donec interdum nisi ac neque bibendum fermentum. Vivamus et odio mollis, dictum arcu ut, dictum lectus. Aenean lacus metus, suscipit non congue ut, auctor eu sapien. In eget sem non nibh ullamcorper eleifend vel commodo massa. Vivamus vulputate, mauris eu interdum aliquam, ex urna venenatis leo, sed eleifend velit nunc id leo. Lorem ipsum dolor sit amet, consectetur adipiscing elit.

Pellentesque ornare mi non imperdiet viverra. Duis quis iaculis magna. Aliquam felis nisi, posuere sed ullamcorper eget, auctor in felis. Cras mollis, turpis at condimentum elementum, nisi elit laoreet risus, a elementum purus dui et lectus. Morbi sed urna cursus, lobortis nunc at, dapibus augue. Quisque mollis, nisi in gravida congue, leo felis dictum lacus, id elementum sapien libero eu est. Sed interdum tortor in est gravida, at interdum lorem pellentesque. Vivamus quis eleifend sapien. Morbi tincidunt mattis odio, et blandit eros vehicula et. Aenean efficitur elit ut nisi lobortis, eget mollis ipsum interdum. Sed egestas egestas enim et consectetur. Vivamus lobortis orci ut fringilla porta. Aliquam fermentum lectus purus, sed aliquet sapien tempus et. Fusce nec ex id sem aliquam vehicula eu quis justo. Duis condimentum enim eget semper posuere. Suspendisse potenti.

Phasellus vitae lorem eget leo ultrices tempor. Suspendisse malesuada turpis vitae est posuere iaculis. Cras neque felis, egestas nec ante nec, placerat tempus magna. Nullam id scelerisque justo. Donec feugiat rutrum turpis quis scelerisque. Aenean sed sem libero. Vivamus interdum nec erat nec aliquam. Suspendisse dapibus aliquet risus vel vulputate. Etiam mattis, magna nec tempus porta, felis enim laoreet arcu, non porta nisi ligula eget magna. Nam sit amet urna semper, accumsan lorem vitae, sodales quam. Fusce non lacus et nibh lacinia varius. Nullam semper ultrices iaculis. Vestibulum convallis vulputate dolor gravida dapibus. Duis eu nisi libero.

Maecenas viverra, ex at sagittis finibus, magna neque iaculis metus, quis sagittis nibh mauris ut eros. Nam tempor convallis bibendum. Donec purus mi, placerat at sagittis vel, accumsan nec sem. Proin sit amet mattis metus, eu fermentum lectus. Proin ultrices ante vel maximus pellentesque. Aenean ante orci, sollicitudin ac ligula nec, consequat egestas odio. Vestibulum non orci eget augue ultricies malesuada et eget nulla. Nunc ac tristique lorem. Curabitur quis auctor neque, ac dignissim metus. Vestibulum pretium justo sit amet dui vulputate dapibus.

Pellentesque sit amet placerat lorem. Suspendisse potenti. Ut vitae urna a nisi eleifend pellentesque in vel tellus. Fusce tincidunt risus turpis, ac auctor magna dapibus vel. Donec dapibus magna id ipsum cursus, finibus pulvinar urna mattis. Duis pharetra, mi at varius fermentum, nulla metus tristique odio, quis maximus risus enim malesuada nisl. Proin a luctus turpis, quis tempus nisl. Nunc sed sodales dui. Sed at sapien enim. Nullam quis gravida arcu. Nullam blandit malesuada urna a venenatis. Sed urna diam, viverra vitae sem at, cursus tempus lectus. Suspendisse sed arcu sed lectus consequat lacinia. Lorem ipsum dolor sit amet, consectetur adipiscing elit.

Morbi pretium dictum neque sed rhoncus. Aliquam in maximus massa, vitae malesuada felis. Aenean non aliquam lectus, ut varius metus. Praesent quis dui sit amet est luctus posuere fringilla sit amet metus. Nullam blandit a orci vitae eleifend. Vestibulum sapien odio, venenatis id neque et, fermentum lobortis eros. Curabitur porttitor ipsum sed commodo lacinia. Mauris pharetra mattis est, nec vehicula massa sodales eget. Morbi porttitor erat vel ligula vestibulum dapibus. Aenean sit amet varius purus, vel lobortis dui. Pellentesque feugiat quam eu turpis elementum interdum. Quisque at dui mollis, gravida sapien sed, ultrices mauris. Maecenas vehicula aliquam feugiat. Donec elit mi, finibus ac mattis blandit, aliquam eget neque. Aenean eleifend augue sit amet neque mattis, et porta magna imperdiet.

Integer ac euismod sapien. Duis scelerisque ante ante, id imperdiet augue varius nec. Vivamus rhoncus neque aliquam lacinia condimentum. Ut malesuada hendrerit dolor sed lacinia. Cras sit amet dolor sed velit consequat sagittis. Pellentesque rutrum consectetur tincidunt. Quisque lectus lorem, egestas eget rhoncus volutpat, sagittis suscipit ante. Vestibulum blandit pretium sapien eu varius. Praesent eleifend quis metus ut eleifend. Donec hendrerit urna tempus odio scelerisque ullamcorper.

Donec enim orci, congue at rutrum id, blandit ut turpis. Vestibulum non maximus elit. Nulla imperdiet eros eros, sit amet congue justo rhoncus sit amet. Etiam vitae convallis risus. Vivamus varius volutpat nisi, non laoreet erat sollicitudin quis. Sed eleifend ipsum quis turpis fermentum, id accumsan nisi cursus. Praesent a posuere sem. Curabitur elementum faucibus leo, vitae fermentum nisl consequat eu. Fusce egestas tortor in mi egestas, eu tincidunt nibh laoreet. Pellentesque rhoncus cursus varius. Aliquam efficitur est sem, id fermentum lorem efficitur accumsan. Lorem ipsum dolor sit amet, consectetur adipiscing elit. In scelerisque lacus sit amet ante elementum fringilla. Fusce venenatis viverra eleifend. Nunc pellentesque porttitor euismod.

Duis non est diam. Donec consectetur velit sed laoreet accumsan. Fusce bibendum consequat eros, volutpat egestas mauris tincidunt eget. Nulla laoreet neque ac nibh convallis, vel dictum tellus eleifend. Nulla facilisi. In nec mi in sem suscipit dapibus vel ut turpis. Proin hendrerit, nunc a pharetra blandit, libero magna rhoncus tellus, non pretium sem nibh in ipsum. Nulla gravida turpis id accumsan finibus. Fusce porttitor elit eros, ac blandit erat egestas nec. Nam lobortis sodales magna sed lobortis. Cras laoreet augue ut dui semper iaculis. Nunc vel risus et quam rhoncus fermentum.

Suspendisse ut diam tempus odio gravida tristique. Cras sed pellentesque tellus. Maecenas quis lectus nec tortor euismod consequat eget scelerisque nulla. Sed commodo velit orci, vel molestie metus sagittis sed. Mauris vestibulum risus turpis, non vulputate felis ultricies eu. Sed efficitur, libero sed condimentum dignissim, lectus nisl cursus purus, vel posuere tortor purus ut turpis. Fusce leo lorem, consectetur et vehicula a, elementum sit amet purus. Nunc justo magna, hendrerit sed tortor eget, tincidunt semper velit. Quisque tempus ante eu eleifend ullamcorper. Phasellus convallis lorem eu tellus auctor, ut pulvinar odio aliquet. Nam id purus ut risus ullamcorper mollis.

Cras commodo ornare mauris nec imperdiet. Nam lacinia nibh et hendrerit ullamcorper. Proin pulvinar libero quis lectus ornare, nec sollicitudin enim suscipit. Suspendisse elementum tellus sit amet augue maximus aliquet. In hac habitasse platea dictumst. Donec egestas, eros sed maximus ornare, est tortor varius augue, ut efficitur eros lectus nec ex. Nam tempus purus sed purus placerat dignissim. Maecenas accumsan luctus ipsum non lacinia. In hac habitasse platea dictumst. Suspendisse viverra, ligula non malesuada finibus, enim nisi tempus ipsum, auctor suscipit ante tortor in libero. Proin nec dapibus tellus, vel sagittis leo.

Praesent cursus, sapien vitae rhoncus fermentum, velit diam porttitor nunc, mollis venenatis purus nunc id sapien. Nullam semper elementum magna ut ultricies. Praesent eget facilisis risus, vitae lacinia risus. Suspendisse potenti. Aliquam tempus libero massa, id facilisis nisi dictum nec. Aenean vel risus magna. Aenean suscipit sit amet lacus id sollicitudin. Aliquam eget posuere magna, non tincidunt nunc. Curabitur odio diam, suscipit vel tempus ac, venenatis at elit. Nullam consequat, diam at molestie tristique, felis odio euismod tortor, a blandit mi felis ut quam. Cras semper placerat nunc a ullamcorper. Pellentesque porttitor efficitur lacus, ut varius nulla mattis id. Sed dui quam, vestibulum in augue nec, aliquet rhoncus turpis. Interdum et malesuada fames ac ante ipsum primis in faucibus. Pellentesque feugiat mauris libero, ut varius quam bibendum eget. Nulla enim ex, efficitur at efficitur vitae, euismod vitae dolor.

Vestibulum placerat justo vitae justo interdum iaculis. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Proin in odio sollicitudin magna tincidunt pulvinar accumsan at magna. Class aptent taciti sociosqu ad litora torquent per conubia nostra, per inceptos himenaeos. Duis faucibus consequat dolor, et auctor ante ullamcorper at. Ut vitae molestie ipsum. Vivamus aliquam nulla id lectus ultrices vehicula id at turpis. Cras sodales ligula vitae dignissim dictum. Praesent suscipit erat nisl, id accumsan ex feugiat ac. Orci varius natoque penatibus et magnis dis parturient montes, nascetur ridiculus mus.
"""
