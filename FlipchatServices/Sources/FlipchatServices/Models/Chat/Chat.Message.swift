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
        
        /// Globally unique ID for this message
        public let id: MessageID
        
        /// The chat member that sent the message. For NOTIFICATION chats, this field
        /// is omitted since the chat has exactly 1 member.
        public let senderID: UserID?
        
        /// Timestamp this message was generated at. This value is also encoded in
        /// any time-based UUID message IDs.
        public let date: Date
        
        /// Ordered message content. A message may have more than one piece of content.
        public var contents: [Content]
        
        public var hasEncryptedContent: Bool {
            contents.first {
                if case .sodiumBox = $0 {
                    return true
                } else {
                    return false
                }
            } != nil
        }
        
        public init(id: MessageID, senderID: UserID?, date: Date, contents: [Content]) {
            self.id = id
            self.senderID = senderID
            self.date = date
            self.contents = contents
        }
        
        public func state(for pointers: [Pointer]) -> State {
            let read = pointers.first { $0.kind == .read }
            if let read, id <= read.messageID {
                return .read
            }
            
//            let delivered = pointers.first { $0.kind == .delivered }
//            if let delivered, id <= delivered.messageID {
//                return .delivered
//            }
            
            return .delivered
        }
        
        public func decrypting(using keyPair: KeyPair) throws -> Message {
            .init(
                id: id,
                senderID: senderID,
                date: date,
                contents: contents.map { content in
                    switch content {
                    case .announcement, .text:
                        return content // Passthrough
                        
                    case .sodiumBox(let encryptedData):
                        do {
                            let decrypted = try encryptedData.decryptMessageUsingNaclBox(keyPair: keyPair)
                            return .text(decrypted)
                        } catch {
                            return .sodiumBox(encryptedData) // Passthrough on failure
                        }
                    }
                }
            )
        }
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
        self.init(
            id: .init(data: proto.messageID.value),
            senderID: !proto.senderID.value.isEmpty ? .init(data: proto.senderID.value) : nil,
            date: proto.ts.date,
            contents: proto.content.compactMap { Chat.Content($0) }
        )
    }
}

// MARK: - Sorting -

extension Array where Element == Chat.Message {
    func sortedByDateDesc() -> [Element] {
        sorted { lhs, rhs in
            lhs.date < rhs.date // Desc
        }
    }
}
