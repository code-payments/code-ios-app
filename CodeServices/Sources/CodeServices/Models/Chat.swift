//
//  Chat.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import CodeAPI

public struct Chat: Equatable, Identifiable {
    
    /// Unique chat identifier
    public let id: ID
    
    /// Cursor value for this chat for reference in subsequent GetChatsRequest
    public let cursor: ID
    
    /// Recommended chat title inferred by the type of chat
    public let title: Title?
    
    /// Pointer in the chat indicating the most recently read message by the user
    public let pointer: Pointer?
    
    /// Estimated number of unread messages in this chat
    public var unreadCount: Int
    
    /// Can the user mute this chat?
    public let canMute: Bool
    
    /// Has the user muted this chat?
    public var isMuted: Bool
    
    /// Can the user unsubscribe from this chat?
    public let canUnsubscribe: Bool

    /// Is the user subscribed to this chat?
    public var isSubscribed: Bool

    /// Is this a verified chat?
    ///
    /// Note: It's possible to have two chats with the same title, but with
    /// different verification statuses. They should be treated separately.
    public let isVerified: Bool
    
    public var messages: [Message] = []
    
    public init(id: ID, cursor: ID, title: Title?, pointer: Pointer?, unreadCount: Int, canMute: Bool, isMuted: Bool, canUnsubscribe: Bool, isSubscribed: Bool, isVerified: Bool, messages: [Message]) {
        self.id = id
        self.cursor = cursor
        self.title = title
        self.pointer = pointer
        self.unreadCount = unreadCount
        self.canMute = canMute
        self.isMuted = isMuted
        self.canUnsubscribe = canUnsubscribe
        self.isSubscribed = isSubscribed
        self.isVerified = isVerified
        self.messages = messages
    }
    
    public func resettingUnreadCount() -> Chat {
        var chat = self
        chat.unreadCount = 0
        return chat
    }
    
    public func muted(_ muted: Bool) -> Chat {
        var chat = self
        chat.isMuted = muted
        return chat
    }
}

extension Chat {
    public enum Title: Equatable {
        case localized(String)
        case domain(String)
    }
}

extension Chat {
    public enum Pointer: Equatable {
        case unknown
        case read(ID)
    }
}

extension Chat {
    public struct Message: Equatable, Identifiable, Hashable {
        public let id: ID
        public let date: Date
        public let contents: [Content]
        
        public init(id: ID, date: Date, contents: [Content]) {
            self.id = id
            self.date = date
            self.contents = contents
        }
    }
}

extension Chat {
    public enum Verb: Equatable, Hashable {
        case unknown    // = 0
        case gave       // = 1
        case received   // = 2
        case withdrew   // = 3
        case deposited  // = 4
        case sent       // = 5
        case returned   // = 6
        case spent      // = 7
        case paid       // = 8
        case purchased  // = 9
    }
}

extension Chat {
    public enum Content: Equatable, Hashable {
        case localized(String)
        case kin(GenericAmount, Verb)
        case sodiumBox
    }
}

// MARK: - gRPC -

extension Chat.Message {
    init(_ proto: Code_Chat_V1_ChatMessage) {
        let contents: [Chat.Content?] = proto.content.map { content in
            switch content.type {
            case .localized(let string):
                return .localized(string.key)
                
            case .exchangeData(let exchange):
                
                let verb: Chat.Verb
                
                switch exchange.verb {
                case .unknown:
                    verb = .unknown
                case .gave:
                    verb = .gave
                case .received:
                    verb = .received
                case .withdrew:
                    verb = .withdrew
                case .deposited:
                    verb = .deposited
                case .sent:
                    verb = .sent
                case .returned:
                    verb = .returned
                case .spent:
                    verb = .spent
                default:
                    verb = .unknown
                }
                
                let amount: KinAmount
                
                switch exchange.exchangeData {
                case .exact(let exact):
                    guard let currency = CurrencyCode(currencyCode: exact.currency) else {
                        return nil
                    }
                    
                    amount = KinAmount(
                        kin: Kin(quarks: exact.quarks),
                        rate: Rate(
                            fx: Decimal(exact.exchangeRate),
                            currency: currency
                        )
                    )
                    
                    return .kin(.exact(amount), verb)
                    
                case .partial(let partial):
                    guard let currency = CurrencyCode(currencyCode: partial.currency) else {
                        return nil
                    }
                    
                    let fiat = Fiat(
                        currency: currency,
                        amount: partial.nativeAmount
                    )
                    
                    return .kin(.partial(fiat), verb)
                    
                case .none:
                    return nil
                }
                
                
            case .naclBox:
                return .sodiumBox
                
            default:
                return nil
            }
        }
        
        self.init(
            id: .init(data: proto.messageID.value),
            date: proto.ts.date,
            contents: contents.compactMap { $0 }
        )
    }
}

extension Chat {
    init(_ proto: Code_Chat_V1_ChatMetadata) {
        
        let title: Title?
        
        switch proto.title {
        case .localized(let content):
            title = .localized(content.key)
        case .domain(let domain):
            title = .domain(domain.value)
        default:
            title = nil
        }
        
        self.init(
            id: .init(data: proto.chatID.value),
            cursor: .init(data: proto.cursor.value),
            title: title,
            pointer: Pointer(proto.readPointer),
            unreadCount: Int(proto.numUnread),
            canMute: proto.canMute,
            isMuted: proto.isMuted,
            canUnsubscribe: proto.canUnsubscribe,
            isSubscribed: proto.isSubscribed,
            isVerified: proto.isVerified,
            messages: []
        )
    }
}

extension Chat.Pointer {
    init(_ proto: Code_Chat_V1_Pointer) {
        switch proto.kind {
        case .unknown:
            self = .unknown
        case .read:
            self = .read(.init(data: proto.value.value))
        default:
            self = .unknown
        }
    }
}
