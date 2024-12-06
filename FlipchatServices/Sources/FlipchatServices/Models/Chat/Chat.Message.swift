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
        public let date: Date
        public var contentType: ContentType
        public var content: String
        
        public init(id: MessageID, senderID: UserID?, date: Date, contentType: ContentType, content: String) {
            self.id = id
            self.senderID = senderID
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
        let (contentType, content) = Self.parseContent(proto.content)!
        self.init(
            id: .init(data: proto.messageID.value),
            senderID: !proto.senderID.value.isEmpty ? .init(data: proto.senderID.value) : nil,
            date: proto.ts.date,
            contentType: contentType,
            content: content
        )
    }
    
    private static func parseContent(_ contents: [Flipchat_Messaging_V1_Content]) -> (ContentType, String)? {
        guard let type = contents[0].type else {
            return nil
        }
        
        switch type {
        case .text(let c):
            return (.text, c.text)
        case .localizedAnnouncement(let c):
            return (.announcement, c.keyOrText)
        case .naclBox:
            return (.text, "<Encrypted>")
        }
    }
}
