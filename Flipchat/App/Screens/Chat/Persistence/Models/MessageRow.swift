//
//  MessageRow.swift
//  Code
//
//  Created by Dima Bart on 2025-03-13.
//

import Foundation
import FlipchatServices

struct MessageRow: Hashable {
    
    let message: Message
    let member: Member
    let referenceID: UUID?
    let reference: Reference?
    
    struct Message: Hashable {
        let serverID: UUID
        let roomID: UUID
        let date: Date
        let state: Chat.Message.State
        let senderID: UUID?
        let contentType: ContentType
        let content: String
        let isDeleted: Bool
        let kin: Kin
        let hasTipFromSelf: Bool
        let offStage: Bool
    }
    
    struct Member: Hashable {
        let userID: UUID?
        let displayName: String?
        let isMuted: Bool?
        let isBlocked: Bool?
        let canSend: Bool?
        let profile: SocialProfile?
        
        var resolvedDisplayName: String {
            (profile?.displayName ?? displayName) ?? defaultMemberName
        }
    }
    
    struct Reference: Hashable {
        let displayName: String?
        let content: String
        let profile: SocialProfile?
        
        var resolvedDisplayName: String {
            (profile?.displayName ?? displayName) ?? defaultMemberName
        }
    }
}

let defaultMemberName = "Member"
