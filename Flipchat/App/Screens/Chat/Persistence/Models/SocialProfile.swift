//
//  SocialProfile.swift
//  Code
//
//  Created by Dima Bart on 2025-03-13.
//

import Foundation
import SQLite

struct SocialProfile: Hashable {
    let displayName: String
    let avatar: TwitterAvatar?
    let verificationType: VerificationType
    
    init(displayName: String, avatarURL: URL?, verificationType: VerificationType) {
        self.displayName = displayName
        self.verificationType = verificationType
        
        if let avatarURL {
            self.avatar = TwitterAvatar(url: avatarURL)
        } else {
            self.avatar = nil
        }
    }
}

struct SocialProfileFull: Hashable {
    let socialID: String
    let username: String
    let displayName: String
    let bio: String
    let followerCount: Int
    let avatar: TwitterAvatar?
    let verificationType: VerificationType
    
    init(socialID: String, username: String, displayName: String, bio: String, followerCount: Int, avatarURL: URL?, verificationType: VerificationType) {
        self.socialID = socialID
        self.username = username
        self.displayName = displayName
        self.bio = bio
        self.followerCount = followerCount
        self.verificationType = verificationType
        
        if let avatarURL {
            self.avatar = TwitterAvatar(url: avatarURL)
        } else {
            self.avatar = nil
        }
    }
}

// MARK: - Database -

extension SocialProfile {
    init?(row: RowIterator.Element) {
        let socialDisplayName = row[Expression<String?>("socialDisplayName")]
        let socialAvatarURL   = row[Expression<URL?>("socialAvatarURL")]
        let verificationType  = row[Expression<VerificationType?>("socialVerificationType")]
        
        if let socialDisplayName {
            self.init(
                displayName: socialDisplayName,
                avatarURL: socialAvatarURL,
                verificationType: verificationType ?? .none
            )
        } else {
            return nil
        }
    }
    
    init?(rowForReference: RowIterator.Element) {
        let socialDisplayName = rowForReference[Expression<String?>("rSocialDisplayName")]
        let socialAvatarURL   = rowForReference[Expression<URL?>("rSocialAvatarURL")]
        let verificationType  = rowForReference[Expression<VerificationType?>("rSocialVerificationType")]
        
        if let socialDisplayName {
            self.init(
                displayName: socialDisplayName,
                avatarURL: socialAvatarURL,
                verificationType: verificationType ?? .none
            )
        } else {
            return nil
        }
    }
}

extension SocialProfileFull {
    init?(row: RowIterator.Element) {
        let socialID            = row[Expression<String?>("socialID")]
        let socialUsername      = row[Expression<String?>("socialUsername")]
        let socialDisplayName   = row[Expression<String?>("socialDisplayName")]
        let socialBio           = row[Expression<String?>("socialBio")]
        let socialFollowerCount = row[Expression<Int?>("socialFollowerCount")]
        let socialAvatarURL     = row[Expression<URL?>("socialAvatarURL")]
        let verificationType    = row[Expression<VerificationType?>("socialVerificationType")]
        
        if
            let socialID,
            let socialDisplayName,
            let socialUsername,
            let socialBio,
            let socialFollowerCount
        {
            self.init(
                socialID: socialID,
                username: socialUsername,
                displayName: socialDisplayName,
                bio: socialBio,
                followerCount: socialFollowerCount,
                avatarURL: socialAvatarURL,
                verificationType: verificationType ?? .none
            )
        } else {
            return nil
        }
    }
}
