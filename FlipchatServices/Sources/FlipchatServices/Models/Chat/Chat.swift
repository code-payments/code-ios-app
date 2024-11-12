//
//  ChatLegacy.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipchatAPI

public struct Chat {
    
    public private(set) var metadata: Metadata
        
    public let selfUserID: UserID
    
    public var id: ChatID {
        metadata.id
    }
    
    public var kind: Chat.Kind {
        metadata.kind
    }
    
    public var roomNumber: RoomNumber {
        metadata.roomNumber
    }
    
    public var isMuted: Bool {
        metadata.isMuted
    }
    
    public var isMutable: Bool {
        metadata.isMutable
    }
    
    public var unreadCount: Int {
        metadata.unreadCount
    }
    
    // MARK: - Init -
    
    public init(selfUserID: UserID, metadata: Metadata) {
        self.selfUserID = selfUserID
        self.metadata = metadata
    }
}
