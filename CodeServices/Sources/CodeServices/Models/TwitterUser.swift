//
//  TwitterUser.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import CodeAPI

public struct TwitterUser: Equatable, Hashable {
    
    public let username: String
    public let avatarURL: URL
    public let followerCount: Int
    public let tipAddress: PublicKey
    
    public init(username: String, avatarURL: URL, followerCount: Int, tipAddress: PublicKey) {
        self.username = username
        self.avatarURL = avatarURL
        self.followerCount = followerCount
        self.tipAddress = tipAddress
    }
}

extension TwitterUser {
    init(_ proto: Code_User_V1_GetTwitterUserResponse) throws {
        guard 
            let avatarURL = URL(string: proto.profilePicURL),
            let tipAddress = PublicKey(proto.tipAddress.value)
        else {
            throw Error.parseFailed
        }
        
        self.init(
            username: proto.name,
            avatarURL: avatarURL,
            followerCount: Int(proto.followerCount),
            tipAddress:  tipAddress
        )
    }
}

extension TwitterUser {
    enum Error: Swift.Error {
        case parseFailed
    }
}
