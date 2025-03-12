//
//  TypingController.swift
//  Code
//
//  Created by Dima Bart on 2025-03-12.
//

import SwiftUI

@Observable
class TypingController {
    
    var typingUsers: [IndexedTypingUser] = []
    
    init() {
        
    }
    
    func setProfiles(_ profiles: [TypingProfile]) {
        let count = profiles.count
        typingUsers = profiles.enumerated().map { index, profile in
            IndexedTypingUser(
                id: profile.serverID,
                index: count - index - 1,
                avatarURL: profile.socialProfile?.avatar?.bigger ?? profile.avatarURL
            )
        }
    }
}
