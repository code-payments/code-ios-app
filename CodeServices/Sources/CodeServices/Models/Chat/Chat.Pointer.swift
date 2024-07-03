//
//  Chat.Pointer.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import CodeAPI

extension Chat {
    public struct Pointer: Equatable, Hashable {
        
        public let kind: Kind
        public let memberID: MemberID
        public let messageID: MessageID
        
        init(kind: Kind, memberID: MemberID, messageID: MessageID) {
            self.kind = kind
            self.memberID = memberID
            self.messageID = messageID
        }
    }
}

extension Chat.Pointer {
    public enum Kind: Int {
        case unknown
        case sent
        case delivered
        case read
    }
}

// MARK: - Proto -

extension Chat.Pointer {
    init(_ proto: Code_Chat_V2_Pointer) {
        self = .init(
            kind: .init(rawValue: proto.type.rawValue) ?? .unknown,
            memberID: .init(data: proto.memberID.value),
            messageID: .init(data: proto.value.value)
        )
    }
}
