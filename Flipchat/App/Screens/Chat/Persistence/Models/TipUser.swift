//
//  TipUser.swift
//  Code
//
//  Created by Dima Bart on 2025-03-13.
//

import Foundation
import FlipchatServices

struct TipUser {
    let userID: UUID
    let displayName: String?
    let tip: Kin
    let profile: SocialProfile?
    
    var resolvedDisplayName: String {
        (profile?.displayName ?? displayName) ?? defaultMemberName
    }
}

struct ReactionUser {
    let userID: UUID
    let displayName: String?
    let reactions: [String]
    let profile: SocialProfile?
    
    var resolvedDisplayName: String {
        (profile?.displayName ?? displayName) ?? defaultMemberName
    }
    
    init(userID: UUID, displayName: String?, reactions: String, profile: SocialProfile?) {
        self.userID = userID
        self.displayName = displayName
        self.reactions = reactions.components(separatedBy: ",")
        self.profile = profile
    }
}

struct FrequentEmoji {
    let emoji: String
    let count: Int
}
