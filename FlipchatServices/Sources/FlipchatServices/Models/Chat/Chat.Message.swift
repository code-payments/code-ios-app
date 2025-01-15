//
//  Chat.Message.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipchatAPI

extension Chat {
    public struct Message: Equatable, Identifiable, Hashable, Sendable {
        
        public let id: MessageID
        public let senderID: UserID?
        public let referenceMessageID: MessageID?
        public let date: Date
        public let contentType: ContentType
        public let content: String
        
        public init(id: MessageID, senderID: UserID?, referenceMessageID: MessageID?, date: Date, contentType: ContentType, content: String) {
            self.id = id
            self.senderID = senderID
            self.referenceMessageID = referenceMessageID
            self.date = date
            self.contentType = contentType
            self.content = content
        }
    }
}

extension Chat.Message {
    public enum ContentType: Int, Sendable {
        case text
        case announcement
        case reaction
        case reply
        case tip
        case deleteMessage
        case unknown = -1
    }
}

extension Chat.Message {
    public enum State: Int, Codable, Hashable {
        case sent
        case delivered
        case read
    }
}

// MARK: - Proto -

extension Chat.Message {
    public init(_ proto: Flipchat_Messaging_V1_Message) {
        let (contentType, content, referenceMessageID) = Self.parseContent(proto.content)
        self.init(
            id: .init(data: proto.messageID.value),
            senderID: !proto.senderID.value.isEmpty ? .init(data: proto.senderID.value) : nil,
            referenceMessageID: referenceMessageID,
            date: proto.ts.date,
            contentType: contentType,
            content: content
        )
    }
    
    private static func parseContent(_ contents: [Flipchat_Messaging_V1_Content]) -> (ContentType, String, MessageID?) {
        guard let type = contents[0].type else {
            return (.unknown, "", nil)
        }
        
        switch type {
        case .text(let c):
            return (.text, c.text, nil)
            
        case .localizedAnnouncement(let c):
            return (.announcement, c.keyOrText, nil)
            
        case .reaction(let reaction):
            return (.reaction, reaction.emoji, ID(data: reaction.originalMessageID.value))
            
        case .reply(let reply):
            return (.reply, reply.replyText, ID(data: reply.originalMessageID.value))
            
        case .tip(let content):
            return (.tip, "", ID(data: content.originalMessageID.value))
            
        case .deleted(let content):
            return (.deleteMessage, "", ID(data: content.originalMessageID.value))
            
        @unknown default:
            return (.unknown, "", nil)
        }
    }
}

private extension ID {
    init?(data: Data?) {
        guard let data else {
            return nil
        }
        self.init(data: data)
    }
}
