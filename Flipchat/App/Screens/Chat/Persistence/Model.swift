//
//  Model.swift
//  FlipchatServices
//
//  Created by Dima Bart on 2024-11-06.
//

import SwiftUI
import SwiftData
import FlipchatServices

protocol ServerIdentifiable {
    var serverID: UUID { get }
}

@Model
public class pChat: ServerIdentifiable, ObservableObject {
    
    @Attribute(.unique)
    public var serverID: UUID
    
    public var kind: pChatKind
    
    public var title: String
    
    public var roomNumber: RoomNumber
    
    public var ownerUserID: UUID
    
    public var coverQuarks: UInt64
    
    public var unreadCount: Int
    
    public var deleted: Bool
    
    public var lastMessageDate: Date
    
    // Relationships
    
    @Relationship
    private(set) var previewMessage: pMessage?
    
    @Relationship(deleteRule: .cascade, inverse: \pMessage.chat)
    public var messages: [pMessage]?
    
    @Relationship(deleteRule: .cascade, inverse: \pMember.chat)
    public var members: [pMember]?
    
    init(serverID: UUID, kind: pChatKind, title: String, roomNumber: RoomNumber, ownerUserID: UUID, coverQuarks: UInt64, unreadCount: Int, deleted: Bool, lastMessageDate: Date) {
        self.serverID = serverID
        self.kind = kind
        self.title = title
        self.roomNumber = roomNumber
        self.ownerUserID = ownerUserID
        self.coverQuarks = coverQuarks
        self.unreadCount = unreadCount
        self.deleted     = deleted
        self.lastMessageDate = lastMessageDate
    }
    
    static func new(serverID: UUID, ownerID: UUID) -> pChat {
        pChat(
            serverID: serverID,
            kind: .unknown,
            title: "",
            roomNumber: 0,
            ownerUserID: ownerID,
            coverQuarks: 0,
            unreadCount: 0,
            deleted: false,
            lastMessageDate: Date(timeIntervalSince1970: 0)
        )
    }
    
    func update(from metadata: Chat.Metadata) {
        self.serverID    = metadata.id.uuid
        self.kind        = pChatKind(kind: metadata.kind)
        self.title       = metadata.title
        self.roomNumber  = metadata.roomNumber
        self.ownerUserID = metadata.ownerUser.uuid
        self.coverQuarks = metadata.coverAmount.quarks
        self.unreadCount = metadata.unreadCount
    }
    
    func update(previewMessage message: pMessage) {
        if let currentPreview = previewMessage {
            if message.date > currentPreview.date {
                previewMessage  = message
                lastMessageDate = message.date
            } else {
                // Ignore, message is older than current preview
            }
        } else {
            previewMessage  = message
            lastMessageDate = message.date
        }
    }
    
    func insert(members: [pMember]) {
        members.forEach {
            $0.chat = self
        }
    }
}

public enum pChatKind: Int, Codable {
    
    case unknown
    case twoWay
    case group
    
    init(kind: Chat.Kind) {
        switch kind {
        case .unknown: self = .unknown
        case .twoWay:  self = .twoWay
        case .group:   self = .group
        }
    }
}

extension pChat {
    
    public var coverCharge: Kin {
        Kin(quarks: coverQuarks)
    }
    
//    public var messagesByDate: [pMessage] {
//        messages?.sorted { lhs, rhs in
//            lhs.date < rhs.date
//        } ?? []
//    }
    
    public var formattedRoomNumber: String {
        "Room #\(roomNumber)"
    }
    
    public var isUnread: Bool {
        unreadCount > 0
    }
    
    public func fetchNewestMessage() -> pMessage? {
        guard let context = modelContext else {
            return nil
        }
        
        var query = FetchDescriptor<pMessage>()
        query.fetchLimit = 1
        query.sortBy = [.init(\.date, order: .reverse)]
        
        return try? context.fetch(query).first
    }
    
//    public var oldestMessage: pMessage? {
//        messagesByDate.first
//    }
//    
//    public var newestMessage: pMessage? {
//        messagesByDate.last
//    }
    
    public var newestMessagePreview: String {
        guard let previewMessage else {
            return "No content"
        }
        
        return previewMessage.contents.map { $0.text }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Message -

@Model
public class pMessage: ServerIdentifiable {
    
    @Attribute(.unique)
    public var serverID: UUID
    
    public var chatID: UUID
    
    public var date: Date
    
    public var state: pMessageState
    
    public var senderID: UUID?
    
    public var isDeleted: Bool
    
    public var contents: [pMessageContent]
    
    // Relationships
    
    public var sender: pMember?
    
    public var chat: pChat?
    
//    @Relationship(deleteRule: .cascade, inverse: \pPointer.message)
//    public var pointers: [pPointer]?
    
    init(serverID: UUID, chatID: UUID, date: Date, state: pMessageState, senderID: UUID?, isDeleted: Bool, contents: [pMessageContent]) {
        self.serverID = serverID
        self.chatID = chatID
        self.date = date
        self.state = state
        self.senderID = senderID
        self.isDeleted = isDeleted
        self.contents = contents
    }
    
    static func new(serverID: UUID, chatID: UUID, senderID: UUID, date: Date = .now, text: String? = nil) -> pMessage {
        pMessage(
            serverID: serverID,
            chatID: chatID,
            date: date,
            state: .sent,
            senderID: senderID,
            isDeleted: false,
            contents: text == nil ? [] : [.text(text!)]
        )
    }
    
    func update(from message: Chat.Message) {
        self.serverID = message.id.uuid
        self.date = message.date
        self.state = .delivered
        self.isDeleted = false
        self.senderID = message.senderID?.uuid
        self.contents = message.contents.compactMap { pMessageContent($0) }
    }
}

//extension pMessage {
//    convenience init(message: Chat.Message) {
//        self.init(
//            serverID: message.id.uuid,
//            chatID: <#T##UUID#>
//            date: message.date,
//            state: .delivered,
//            senderID: message.senderID?.uuid,
//            isDeleted: false,
//            contents: message.contents.compactMap { pMessageContent($0) }
//        )
//    }
//}

extension pMessage {
    var userDisplayName: String {
        sender?.displayName ?? pMember.defaultName
    }
}

public enum pMessageContent: Codable, Hashable, Equatable {
    
    case text(String)
    case announcement(String)
    
    var text: String {
        switch self {
        case .text(let text), .announcement(let text):
            return text
        }
    }
    
    init(_ content: Chat.Content) {
        switch content {
        case .text(let text):
            self = .text(text)
        case .announcement(let text):
            self = .announcement(text)
        case .sodiumBox:
            self = .text("<[Encrypted]>")
        }
    }
}

public enum pMessageState: Int, Codable {
    
    case sent
    case delivered
    case read
    
    var state: Chat.Message.State {
        switch self {
        case .sent:      return .sent
        case .delivered: return .delivered
        case .read:      return .read
        }
    }
}

// MARK: - Identity -

@Model
public class pIdentity: ServerIdentifiable {
    
    @Attribute(.unique)
    public var serverID: UUID // Same as pMemeber serverID
    
    public var displayName: String
    
    public var avatarURL: URL?
    
    @Relationship(deleteRule: .cascade, inverse: \pMember.identity)
    public var members: [pMember]?
    
    init(serverID: UUID, displayName: String, avatarURL: URL? = nil) {
        self.serverID = serverID
        self.displayName = displayName
        self.avatarURL = avatarURL
    }
    
    static func new(serverID: UUID, displayName: String, avatarURL: URL?) -> pIdentity {
        pIdentity(
            serverID: serverID,
            displayName: displayName,
            avatarURL: avatarURL
        )
    }
}

// MARK: - Member -

@Model
public class pMember: ServerIdentifiable {
    
    public var serverID: UUID
    
    public var chatID: UUID
    
    public var isMuted: Bool
    
    // Relationships
    
    public var identity: pIdentity?
    
    public var chat: pChat?
    
    @Relationship(deleteRule: .nullify, inverse: \pMessage.sender)
    public var messages: [pMessage]?
    
//    @Relationship(deleteRule: .cascade)
//    public var pointers: [pPointer]?
    
    init(serverID: UUID, chatID: UUID, isMuted: Bool) {
        self.serverID = serverID
        self.chatID = chatID
        self.isMuted = isMuted
    }
    
    static func new(serverID: UUID, chatID: UUID) -> pMember {
        pMember(
            serverID: serverID,
            chatID: chatID,
            isMuted: false
        )
    }
    
    func update(from member: Chat.Member) {
        self.serverID = member.id.uuid
        self.isMuted = member.isMuted
        
        identity?.displayName = member.identity.displayName
        identity?.avatarURL   = member.identity.avatarURL
    }
}

extension pMember {
    
    static var defaultName: String {
        "Member"
    }
    
    var displayName: String {
        identity?.displayName ?? Self.defaultName
    }
}

// MARK: - Pointer -

//@Model
//public class pPointer {
//    
//    // Relationships
//    
//    @Relationship(deleteRule: .nullify)
//    public var member: pMember?
//    
//    @Relationship(deleteRule: .nullify)
//    public var message: pMessage?
//    
//    init() {}
//}

extension Data {
    static var tempID: Data {
        var d = Data()
        d.append(Data("temp:".utf8))
        d.append(UUID().data)
        return d
    }
    
    func uuidRepresentation() -> UUID? {
        withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return nil
            }
            
            return UUID(uuid: baseAddress.assumingMemoryBound(to: uuid_t.self).pointee)
        }
    }
}
