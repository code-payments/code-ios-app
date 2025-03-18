//
//  MessageListController+Keyboard.swift
//  Code
//
//  Created by Dima Bart on 2025-03-18.
//

import SwiftUI
import FlipchatServices

extension Array where Element == MessageRow {
    func messageDescriptions(userID: UserID, unread: UnreadDescription?) -> (descriptions: [MessageDescription], unreadIndex: Int?) {
        var container: [MessageDescription] = []
        var unreadIndex: Int?
        
        // 1. On first pass we index all deleted IDs
        var deletedIDs: [UUID: UserID?] = [:]
        for description in self {
            guard
                description.message.contentType == .deleteMessage,
                let referenceID = description.referenceID
            else {
                continue
            }
            
            deletedIDs[referenceID] = ID(uuid: description.message.senderID)
        }
        
        // 2. Second pass is to remove the meta messages
        // from the main list that will go into date groups
        let filteredMessages = filter {
            switch $0.message.contentType {
            case .text, .announcement, .reply, .announcementActionable:
                return true
            case .reaction, .tip, .deleteMessage, .unknown:
                return false
            }
        }
        
        // 3. Third pass is to group messages by date
        // and generate the descriptions we'll use for
        // rendering the list of messages
        for dateGroup in filteredMessages.groupByDay(userID: userID) {
            
            // Date
            container.append(
                .init(
                    kind: .date(dateGroup.date),
                    content: dateGroup.date.formattedRelatively()
                )
            )
            
            for messageContainer in dateGroup.messages {
                
                let message = messageContainer.row.message
                let referenceID = messageContainer.row.referenceID
                let isReceived = message.senderID != userID.uuid
                
                var deletionState: MessageDeletion?
                var referenceDeletionState: ReferenceDeletion?
                
                if let deletionUser = deletedIDs[message.serverID] {
                    deletionState = MessageDeletion(
                        senderID: deletionUser?.uuid,
                        senderName: messageContainer.row.member.resolvedDisplayName,
                        isSelf: deletionUser == userID,
                        isSender: deletionUser?.uuid == message.senderID
                    )
                }
                
                if let referenceID, let deletionUser = deletedIDs[referenceID] {
                    referenceDeletionState = ReferenceDeletion(
                        senderID: deletionUser?.uuid,
                        senderName: messageContainer.row.member.resolvedDisplayName,
                        isSelf: deletionUser == userID,
                        isSender: deletionUser?.uuid == message.senderID
                    )
                }
                
                switch message.contentType {
                case .text, .reply:
                    container.append(
                        .init(
                            kind: .message(
                                ID(uuid: message.serverID),
                                isReceived,
                                messageContainer.row,
                                messageContainer.location,
                                deletionState,
                                referenceDeletionState
                            ),
                            content: message.content
                        )
                    )
                    
                case .announcement:
                    container.append(
                        .init(
                            kind: .announcement(ID(uuid: message.serverID)),
                            content: message.content
                        )
                    )
                    
                case .announcementActionable:
                    container.append(
                        .init(
                            kind: .announcementActionable(ID(uuid: message.serverID)),
                            content: message.content
                        )
                    )
                    
                case .reaction, .tip, .deleteMessage, .unknown:
                    break
                }
            }
        }
        
        // 4. If unread description is present, we'll augment the list of
        // messages to include an unread banner as a 'message' row. The
        // pointer is to the last seen message so we have to insert the
        // banner after the message itself.
        if let unread, unread.unread > 0 {
            if let index = container.findLastReadMessageIndex(lastReadMessage: unread.messageID), index < container.count {
                let description = MessageDescription(
                    kind: .unread,
                    content: "\(unread.unread) Unread Message\(unread.unread == 1 ? "" : "s")"
                )
                
                container.insert(description, at: index)
                unreadIndex = index
            }
        }
        
        return (container, unreadIndex)
    }
}

extension Array where Element == MessageDescription {
    func findLastReadMessageIndex(lastReadMessage: UUID) -> Int? {
        for (index, message) in reversed().enumerated() {
            guard let messageID = message.serverID else {
                continue
            }
            
            if lastReadMessage >= messageID, index != 0 {
                // Add 1 at the end to insert the banner
                // after this message, not before it
                return count - 1 - index + 1
            }
        }
        
        return nil
    }
}

extension NSLayoutConstraint {
    func setting(priority: UILayoutPriority) -> Self {
        self.priority = priority
        return self
    }
}
