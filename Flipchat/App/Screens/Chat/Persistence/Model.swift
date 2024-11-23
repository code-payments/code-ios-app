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
    var serverID: Data { get }
}

@Model
public class pChat: ServerIdentifiable, ObservableObject {
    
    @Attribute(.unique)
    public var serverID: Data
    
    public var kind: pChatKind
    
    public var title: String
    
    public var roomNumber: RoomNumber
    
    public var ownerUserID: Data
    
    public var coverQuarks: UInt64
    
    public var isHidden: Bool
    
    public var isMuted: Bool
    
    public var isMutable: Bool
    
    public var unreadCount: Int
    
    // Relationships
    
    @Relationship(deleteRule: .cascade)
    public var messages: [pMessage] = []
    
    @Relationship(deleteRule: .cascade)
    public var members: [pMember] = []
    
    init(serverID: Data, kind: pChatKind, title: String, roomNumber: RoomNumber, ownerUserID: Data, coverQuarks: UInt64, isHidden: Bool, isMuted: Bool, isMutable: Bool, unreadCount: Int) {
        self.serverID = serverID
        self.kind = kind
        self.title = title
        self.roomNumber = roomNumber
        self.ownerUserID = ownerUserID
        self.coverQuarks = coverQuarks
        self.isHidden = isHidden
        self.isMuted = isMuted
        self.isMutable = isMutable
        self.unreadCount = unreadCount
    }
    
    static func new(serverID: Data) -> pChat {
        pChat(
            serverID: serverID,
            kind: .unknown,
            title: "",
            roomNumber: 0,
            ownerUserID: Data(),
            coverQuarks: 0,
            isHidden: false,
            isMuted: false,
            isMutable: false,
            unreadCount: 0
        )
    }
    
    func update(from metadata: Chat.Metadata) {
        self.serverID    = metadata.id.data
        self.kind        = pChatKind(kind: metadata.kind)
        self.roomNumber  = metadata.roomNumber
        self.ownerUserID = metadata.ownerUser.data
        self.coverQuarks = metadata.coverAmount.quarks
        self.title       = metadata.title
        self.unreadCount = metadata.unreadCount
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
    
    public var messagesByDate: [pMessage] {
        messages.sorted { lhs, rhs in
            lhs.date < rhs.date
        }
    }
    
    public var formattedRoomNumber: String {
        "Room #\(roomNumber)"
    }
    
    public var isUnread: Bool {
        !isMuted && unreadCount > 0
    }
    
    public var oldestMessage: pMessage? {
        messagesByDate.first
    }
    
    public var newestMessage: pMessage? {
        messagesByDate.last
    }
    
    public var newestMessagePreview: String {
        guard let newestMessage else {
            return "No content"
        }
        
        return newestMessage.contents.map { $0.text }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Message -

@Model
public class pMessage: ServerIdentifiable {
    
    @Attribute(.unique)
    public var serverID: Data
    
    public var date: Date
    
    public var state: pMessageState
    
    public var senderID: Data?
    
    public var isDeleted: Bool
    
    public var contents: [pMessageContent]
    
    // Relationships
    
    @Relationship(deleteRule: .nullify)
    public var sender: pMember?
    
    @Relationship(deleteRule: .nullify, inverse: \pChat.messages)
    public var chat: pChat?
    
//    @Relationship(deleteRule: .cascade, inverse: \pPointer.message)
//    public var pointers: [pPointer] = []
    
    init(serverID: Data, date: Date, state: pMessageState, senderID: Data?, isDeleted: Bool, contents: [pMessageContent]) {
        self.serverID = serverID
        self.date = date
        self.state = state
        self.senderID = senderID
        self.isDeleted = isDeleted
        self.contents = contents
    }
    
    static func new(serverID: Data?, senderID: Data, date: Date = .now, text: String? = nil) -> pMessage {
        pMessage(
            serverID: serverID ?? .tempID,
            date: date,
            state: .sent,
            senderID: senderID,
            isDeleted: false,
            contents: text == nil ? [] : [.text(text!)]
        )
    }
    
    func update(from message: Chat.Message) {
        self.serverID = message.id.data
        self.date = message.date
        self.state = .delivered
        self.isDeleted = false
        self.senderID = message.senderID?.data
        self.contents = message.contents.compactMap { pMessageContent($0) }
    }
}

extension pMessage {
    convenience init(message: Chat.Message) {
        self.init(
            serverID: message.id.data,
            date: message.date,
            state: .delivered,
            senderID: message.senderID?.data,
            isDeleted: false,
            contents: message.contents.compactMap { pMessageContent($0) }
        )
    }
}

extension pMessage {
    var userDisplayName: String {
        sender?.identity.displayName ?? "Deleted"
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
    public var serverID: Data // Same as pMemeber serverID
    
    public var displayName: String
    
    public var avatarURL: URL?
    
    @Relationship(deleteRule: .cascade)
    public var members: [pMember] = []
    
    init(serverID: Data, displayName: String, avatarURL: URL? = nil) {
        self.serverID = serverID
        self.displayName = displayName
        self.avatarURL = avatarURL
    }
    
    static func new(serverID: Data, displayName: String, avatarURL: URL?) -> pIdentity {
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
    
    @Attribute(.unique)
    public var serverID: Data
    
    public var isMuted: Bool
    
    // Relationships
    
    @Relationship(deleteRule: .nullify, inverse: \pIdentity.members)
    public var identity: pIdentity
    
    @Relationship(deleteRule: .nullify, inverse: \pChat.members)
    public var chat: pChat
    
    @Relationship(deleteRule: .nullify, inverse: \pMessage.sender)
    public var messages: [pMessage] = []
    
//    @Relationship(deleteRule: .cascade)
//    public var pointers: [pPointer] = []
    
    init(serverID: Data, isMuted: Bool, identity: pIdentity, chat: pChat) {
        self.serverID = serverID
        self.isMuted = isMuted
        self.identity = identity
        self.chat = chat
    }
    
    static func new(serverID: Data, identity: pIdentity, chat: pChat) -> pMember {
        pMember(
            serverID: serverID,
            isMuted: false,
            identity: identity,
            chat: chat
        )
    }
    
    func update(from member: Chat.Member) {
        self.serverID = member.id.data
        self.isMuted = member.isMuted
        
        let identity         = self.identity
        identity.displayName = member.identity.displayName
        identity.avatarURL   = member.identity.avatarURL
    }
}

extension pMember {
    var displayName: String {
        identity.displayName
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
}
