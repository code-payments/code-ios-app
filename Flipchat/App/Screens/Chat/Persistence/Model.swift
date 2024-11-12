//
//  Model.swift
//  FlipchatServices
//
//  Created by Dima Bart on 2024-11-06.
//

import SwiftUI
import SwiftData
import FlipchatServices

@Model
public class pChat: ObservableObject {
    
    @Attribute(.unique)
    public var id: Data
    
    public var kind: pChatKind
    
    public var title: String
    
    public var roomNumber: RoomNumber
    
    public var ownerUserID: Data
    
    public var isHidden: Bool
    
    public var isMuted: Bool
    
    public var isMutable: Bool
    
    public var unreadCount: Int
    
    // Relationships
    
    @Relationship(deleteRule: .cascade)
    public var messages: [pMessage] = []
    
    @Relationship(deleteRule: .cascade)
    public var members: [pMember] = []
    
    init(id: Data, kind: pChatKind, title: String, roomNumber: RoomNumber, ownerUserID: Data, isHidden: Bool, isMuted: Bool, isMutable: Bool, unreadCount: Int) {
        self.id = id
        self.kind = kind
        self.title = title
        self.roomNumber = roomNumber
        self.ownerUserID = ownerUserID
        self.isHidden = isHidden
        self.isMuted = isMuted
        self.isMutable = isMutable
        self.unreadCount = unreadCount
    }
    
    static func new(id: Data) -> pChat {
        pChat(
            id: id,
            kind: .unknown,
            title: "",
            roomNumber: 0,
            ownerUserID: Data(),
            isHidden: false,
            isMuted: false,
            isMutable: false,
            unreadCount: 0
        )
    }
    
    func update(from metadata: Chat.Metadata) {
        self.id          = metadata.id.data
        self.kind        = pChatKind(kind: metadata.kind)
        self.roomNumber  = metadata.roomNumber
        self.ownerUserID = metadata.ownerUser.data
        self.title       = metadata.title
        self.isMuted     = metadata.isMuted
        self.isMutable   = metadata.isMutable
        self.unreadCount = metadata.unreadCount
    }
    
    func insert(members: [pMember]) {
        var combined: Set<pMember> = []
        
        var m = self.members
        m.append(contentsOf: members)
        m.forEach { member in
            combined.remove(member)
            combined.insert(member)
        }
        
        self.members = combined.sorted { $0.displayName.lexicographicallyPrecedes($1.displayName) }
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
        
        return newestMessage.contents
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Message -

@Model
public class pMessage {
    
    @Attribute(.unique)
    public var id: Data
    
    public var date: Date
    
    public var state: pMessageState
    
    public var senderID: Data?
    
    public var isDeleted: Bool
    
    public var contents: [String]
    
    // Relationships
    
    @Relationship(deleteRule: .nullify)
    public var sender: pMember?
    
    @Relationship(deleteRule: .nullify)
    public var chat: pChat?
    
    @Relationship(deleteRule: .nullify)
    public var pointers: [pPointer] = []
    
    init(id: Data, date: Date, state: pMessageState, senderID: Data?, isDeleted: Bool, contents: [String]) {
        self.id = id
        self.date = date
        self.state = state
        self.senderID = senderID
        self.isDeleted = isDeleted
        self.contents = contents
    }
    
    static func new(id: Data?, senderID: Data, date: Date = .now, text: String? = nil) -> pMessage {
        pMessage(
            id: id ?? .tempID,
            date: date,
            state: .sent,
            senderID: senderID,
            isDeleted: false,
            contents: text == nil ? [] : [text!]
        )
    }
    
    func update(from message: Chat.Message) {
        self.id = message.id.data
        self.date = message.date
        self.state = .delivered
        self.isDeleted = false
        self.senderID = message.senderID?.data
        self.contents = message.contents.compactMap { $0.text }
    }
}

extension pMessage {
    convenience init(message: Chat.Message) {
        self.init(
            id: message.id.data,
            date: message.date,
            state: .delivered,
            senderID: message.senderID?.data,
            isDeleted: false,
            contents: message.contents.compactMap { $0.text }
        )
    }
}

extension pMessage {
    var userDisplayName: String {
        sender?.displayName ?? "Anonymous"
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

// MARK: - Member -

@Model
public class pMember {
    
    @Attribute(.unique)
    public var id: Data
    
    public var displayName: String
    
    public var avatarURL: URL?
    
    // Relationships
    
    @Relationship(deleteRule: .nullify)
    public var messages: [pMessage] = []
    
    @Relationship(deleteRule: .nullify)
    public var chats: [pChat] = []
    
    @Relationship(deleteRule: .cascade)
    public var pointers: [pPointer] = []
    
    init(id: Data, displayName: String, avatarURL: URL?) {
        self.id = id
        self.displayName = displayName
        self.avatarURL = avatarURL
    }
    
    static func new(id: Data) -> pMember {
        pMember(
            id: id,
            displayName: "",
            avatarURL: nil
        )
    }
    
    func update(from member: Chat.Member) {
        self.id = member.id.data
        self.displayName = member.identity.displayName ?? "Anonymous"
        self.avatarURL = nil
    }
}

// MARK: - Pointer -

@Model
public class pPointer {
    
    // Relationships
    
    @Relationship(deleteRule: .nullify)
    public var member: pMember?
    
    @Relationship(deleteRule: .nullify)
    public var message: pMessage?
    
    init() {}
}

extension Data {
    static var tempID: Data {
        var d = Data()
        d.append(Data("temp:".utf8))
        d.append(UUID().data)
        return d
    }
}
