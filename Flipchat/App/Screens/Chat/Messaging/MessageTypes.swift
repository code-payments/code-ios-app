//
//  MessageList.swift
//  Code
//
//  Created by Dima Bart on 2023-10-06.
//

import SwiftUI
import FlipchatServices
import CodeUI

enum MessageAction {
    case copy(String)
    case muteUser(String, UserID, ChatID)
    case reportMessage(UserID, MessageID)
    case reply(MessageRow)
}

struct MessageDescription: Identifiable, Hashable, Equatable {
    enum Kind: Hashable, Equatable {
        case date(Date)
        case message(MessageID, Bool, MessageRow, MessageSemanticLocation)
        case announcement(MessageID)
        case unread
        
        var messageRow: MessageRow? {
            switch self {
            case .message(_, _, let row, _):
                return row
            case .date, .announcement, .unread:
                return nil
            }
        }
    }
    
    var id: String {
        switch kind {
        case .date(let date):
            return "\(date.timeIntervalSince1970)"
        case .message(let messageID, _, _, _):
            return messageID.data.hexString()
        case .announcement(let messageID):
            return messageID.data.hexString()
        case .unread:
            return "com.flipchat.messageList.unread"
        }
    }
    
    let kind: Kind
    let content: String
    
    func messageWidth(in size: CGSize) -> (width: CGFloat, isReceived: Bool) {
        switch kind {
        case .date, .announcement, .unread:
            return (size.width * 1.0, false)
        case .message(_, let isReceived, _, _):
            return (size.width * 0.8, isReceived)
        }
    }
}

struct MessageDateGroup: Identifiable, Hashable {
    
    var id: Date {
        date
    }
    
    var date: Date
    var messages: [MessageContainer]
    
    init(userID: UserID, date: Date, messages: [MessageRow]) {
        self.date = date
        self.messages = messages.assigningSemanticLocation(selfUserID: userID)
    }
}

struct MessageContainer: Identifiable, Hashable {
    
    var id: UUID {
        row.message.roomID
    }
    
    var location: MessageSemanticLocation
    var row: MessageRow
}

extension Array where Element == MessageRow {
    func groupByDay(userID: UserID) -> [MessageDateGroup] {
        
        let calendar = Calendar.current
        var container: [Date: [MessageRow]] = [:]

        forEach { row in
            let components = calendar.dateComponents([.year, .month, .day], from: row.message.date)
            if let date = calendar.date(from: components) {
                if container[date] == nil {
                    container[date] = [row]
                } else {
                    container[date]?.append(row)
                }
            }
        }
        
        let sortedKeys = container.keys.sorted()
        let groupedMessages = sortedKeys.map {
            MessageDateGroup(userID: userID, date: $0, messages: container[$0] ?? [])
        }

        return groupedMessages
    }
    
    func assigningSemanticLocation(selfUserID: UserID) -> [MessageContainer] {
        var containers: [MessageContainer] = []
        let messages = self
        
        for (index, row) in messages.enumerated() {
            let message = row.message
            let previousSender = index > 0 ? messages[index - 1].message.senderID : nil
            let nextSender = index < messages.count - 1 ? messages[index + 1].message.senderID : nil
            
            let isReceived = message.senderID != selfUserID.uuid
            if let senderID = message.senderID {
                
                let location: MessageSemanticLocation
                
                if senderID != previousSender && senderID != nextSender {
                    location = .standalone(.init(received: isReceived))
                    
                } else if senderID != previousSender && senderID == nextSender {
                    location = .beginning(.init(received: isReceived))
                    
                } else if senderID == previousSender && senderID == nextSender {
                    location = .middle(.init(received: isReceived))
                    
                } else {
                    location = .end(.init(received: isReceived))
                }
                
                containers.append(
                    MessageContainer(
                        location: location,
                        row: row
                    )
                )
                
            } else {
                let location: MessageSemanticLocation = .standalone(.init(received: isReceived))
                containers.append(
                    MessageContainer(
                        location: location,
                        row: row
                    )
                )
            }
        }
        
        return containers
    }
}

extension View {
    func cornerClip(smaller: Bool = false, location: MessageSemanticLocation) -> some Shape {
        let m = (smaller ? 0.65 : 1.0)
        return UnevenRoundedCorners(
            tl: location.topLeftRadius     * m,
            bl: location.bottomLeftRadius  * m,
            br: location.bottomRightRadius * m,
            tr: location.topRightRadius    * m
        )
    }
}
