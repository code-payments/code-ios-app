//
//  StreamEvent.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import CodeAPI

extension Chat {
    public enum Event {
        case message(Message)
        case pointer(Pointer)
        case isTyping(Bool, MemberID)
    }
}

extension Chat.Event {
    public init?(_ proto: Code_Chat_V2_ChatStreamEvent) {
        guard let type = proto.type else {
            return nil
        }
        
        switch type {
        case .message(let message):
            self = .message(.init(message))
            
        case .pointer(let pointer):
            self = .pointer(.init(pointer))
            
        case .isTyping(let state):
            self = .isTyping(state.isTyping, ID(data: state.memberID.value))
        }
    }
}
