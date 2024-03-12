//
//  Chat.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import CodeAPI
import Clibsodium

public class Chat: Identifiable, ObservableObject {
    
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
    
    @Published public private(set) var messages: [Message] = []
    
    public var oldestMessage: Message? {
        messages.first
    }
    
    public var newestMessage: Message? {
        messages.last
    }
    
    // MARK: - Init -
    
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
    
    public func resetUnreadCount() {
        unreadCount = 0
    }
    
    public func mute(_ muted: Bool) {
        isMuted = muted
    }
    
    // MARK: - Messages -
    
    public func setMessages(_ messages: [Message]) {
        self.messages = messages.sorted { lhs, rhs in
            lhs.date < rhs.date // Desc
        }
    }
}

extension Chat: CustomDebugStringConvertible, CustomStringConvertible {
    public var description: String {
        let messages = messages.map { message in
            "\(message.date) \(message.id.data.hexEncodedString())"
        }.joined(separator: "\n")
        
        return "\(id.data.hexEncodedString()) (\(String(describing: title))\n\(messages)"
    }
    
    public var debugDescription: String {
        description
    }
}

extension Chat {
    public enum Title: Equatable {
        case localized(String)
        case domain(Domain)
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
        
        public var hasEncryptedContent: Bool {
            contents.first {
                if case .sodiumBox = $0 {
                    return true
                } else {
                    return false
                }
            } != nil
        }
        
        public init(id: ID, date: Date, contents: [Content]) {
            self.id = id
            self.date = date
            self.contents = contents
        }
        
        public func decrypting(using keyPair: KeyPair) throws -> Message {
            .init(
                id: id,
                date: date,
                contents: contents.map { content in
                    switch content {
                    case .localized, .kin, .decrypted:
                        return content // Passthrough
                        
                    case .sodiumBox(let encryptedData):
                        do {
                            let decrypted = try encryptedData.decryptMessageUsingNaclBox(keyPair: keyPair)
                            return .decrypted(decrypted)
                        } catch {
                            return .sodiumBox(encryptedData) // Passthrough on failure
                        }
                    }
                }
            )
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
        case sodiumBox(EncryptedData)
        case decrypted(String)
    }
}

// MARK: - gRPC -

extension Chat.Message {
    public init(_ proto: Code_Chat_V1_ChatMessage) {
        self.init(
            id: .init(data: proto.messageID.value),
            date: proto.ts.date,
            contents: proto.content.compactMap { Chat.Content($0) }
        )
    }
}

extension Chat.Content {
    
    public init?(_ proto: Code_Chat_V1_Content) {
        switch proto.type {
        case .localized(let string):
            self = .localized(string.keyOrText)
            
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
            case .paid:
                verb = .paid
            case .purchased:
                verb = .purchased
            case .UNRECOGNIZED:
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
                
                self = .kin(.exact(amount), verb)
                
            case .partial(let partial):
                guard let currency = CurrencyCode(currencyCode: partial.currency) else {
                    return nil
                }
                
                let fiat = Fiat(
                    currency: currency,
                    amount: partial.nativeAmount
                )
                
                self = .kin(.partial(fiat), verb)
                
            case .none:
                return nil
            }
            
            
        case .naclBox(let encryptedContent):
            guard let peerPublicKey = PublicKey(encryptedContent.peerPublicKey.value) else {
                return nil
            }
            
            let data = EncryptedData(
                peerPublicKey: peerPublicKey,
                nonce: encryptedContent.nonce,
                encryptedData: encryptedContent.encryptedPayload
            )
            
            self = .sodiumBox(data)
            
        default:
            return nil
        }
    }
}

public struct EncryptedData: Equatable, Hashable, Codable {
    
    public var peerPublicKey: PublicKey
    public var nonce: Data
    public var encryptedData: Data
    
    public init(peerPublicKey: PublicKey, nonce: Data, encryptedData: Data) {
        self.peerPublicKey = peerPublicKey
        self.nonce = nonce
        self.encryptedData = encryptedData
    }
    
    public func decryptMessageUsingNaclBox(keyPair: KeyPair) throws -> String {
        guard let encryptionKey = keyPair.encryptionPrivateKey else {
            throw Error.invalidKeyPair
        }
        
        let data = try encryptedData.boxOpen(
            privateKey: encryptionKey,
            publicKey: peerPublicKey,
            nonce: nonce
        )
        
        return String(data: data, encoding: .utf8)!
    }
    
    enum Error: Swift.Error {
        case invalidKeyPair
    }
}

extension Chat {
    convenience init(_ proto: Code_Chat_V1_ChatMetadata) {
        
        let title: Title?
        
        switch proto.title {
        case .localized(let content):
            title = .localized(content.keyOrText)
        case .domain(let domain):
            if let validDomain = Domain(domain.value) {
                title = .domain(validDomain)
            } else {
                title = nil
            }
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
