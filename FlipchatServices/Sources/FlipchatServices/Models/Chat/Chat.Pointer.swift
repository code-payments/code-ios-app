//
//  Chat.Pointer.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipchatAPI
import CodeServices

extension Chat {
    public struct Pointer: Equatable, Hashable, Sendable {
        
        public let kind: Kind
        public let messageID: MessageID
        
        init(kind: Kind, messageID: MessageID) {
            self.kind = kind
            self.messageID = messageID
        }
    }
}

extension Chat.Pointer {
    public enum Kind: Int, Sendable {
        case unknown
        case sent
        case delivered
        case read
    }
}

// MARK: - Proto -

extension Chat.Pointer {
    init(_ proto: Flipchat_Messaging_V1_Pointer) {
        self = .init(
            kind: .init(rawValue: proto.type.rawValue) ?? .unknown,
            messageID: .init(data: proto.value.value)
        )
    }
}
