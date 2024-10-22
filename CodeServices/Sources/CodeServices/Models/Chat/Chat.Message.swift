//
//  ChatLegacy.Message.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import CodeAPI

extension ChatLegacy {
    public struct Message: Equatable, Identifiable, Hashable, Sendable {
        
        /// Globally unique ID for this message
        public let id: MessageID
        
        /// The chat member that sent the message. For NOTIFICATION chats, this field
        /// is omitted since the chat has exactly 1 member.
        public let senderID: MemberID?
        
        /// Timestamp this message was generated at. This value is also encoded in
        /// any time-based UUID message IDs.
        public let date: Date
        
        /// Cursor value for this message for reference in a paged GetMessagesRequest
        public let cursor: Cursor
        
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
        
        public init(id: MessageID, senderID: MemberID?, date: Date, cursor: Cursor, contents: [Content]) {
            self.id = id
            self.senderID = senderID
            self.date = date
            self.cursor = cursor
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
                cursor: cursor,
                contents: contents.map { content in
                    switch content {
                    case .localized, .kin, .text:
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
        
        public func isContentReceived() -> Bool {
            for content in contents {
                switch content {
                case .kin(_, let verb, _):
                    switch verb {
                    case .gave, .withdrew, .sent, .spent, .paid, .tipSent:
                        return false
                    case .received, .returned, .purchased, .deposited, .tipReceived, .unknown:
                        continue
                    }
                    
                case .text, .localized, .sodiumBox:
                    continue
                }
            }
            
            return true
        }
    }
}

extension ChatLegacy.Message {
    public enum State {
        case sent
        case delivered
        case read
    }
}

// MARK: - Proto -

extension ChatLegacy.Message {
    public init(_ proto: Code_Chat_V2_Message) {
        self.init(
            id: .init(data: proto.messageID.value),
            senderID: !proto.senderID.value.isEmpty ? .init(data: proto.senderID.value) : nil,
            date: proto.ts.date,
            cursor: .init(data: proto.cursor.value),
            contents: proto.content.compactMap { ChatLegacy.Content($0) }
        )
    }
}

// MARK: - Sorting -

extension Array where Element == ChatLegacy.Message {
    func sortedByDateDesc() -> [Element] {
        sorted { lhs, rhs in
            lhs.date < rhs.date // Desc
        }
    }
}
