//
//  MessageReaction.swift
//  Code
//
//  Created by Dima Bart on 2025-03-26.
//

import Foundation
import FlipchatServices

struct MessageReaction {
    let emoji: String
    let count: Int
    let reactionID: UUID? // hasReacted, current user's reaction messageID
    
    var currentUserReacted: Bool {
        reactionID != nil
    }
}
