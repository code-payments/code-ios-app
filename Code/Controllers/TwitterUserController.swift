//
//  TwitterUserController.swift
//  Code
//
//  Created by Dima Bart on 2024-09-11.
//


import SwiftUI
import CodeServices

@MainActor
class TwitterUserController: ObservableObject {
    
    private var cachedUsers: [String: TwitterUser] = [:]
    private var cachedAvatars: [String: Image] = [:]
    
    private let owner: KeyPair
    private let client: Client
    
    // MARK: - Init -
    
    init(owner: KeyPair, client: Client) {
        self.owner = owner
        self.client = client
    }
    
    func fetchCompleteUser(username: String) async throws -> (TwitterUser, Image?) {
        let user   = try  await fetchUser(username: username)
        let avatar = try? await fetchAvatar(username: username, url: user.avatarURL)
        return (user, avatar)
    }
    
    func fetchUser(username: String, ignoringCache: Bool = false) async throws -> TwitterUser {
        let key = username.lowercased()
        
        if !ignoringCache, let cachedUser = cachedUsers[key] {
            return cachedUser
        }
        
        let user = try await client.fetchTwitterUser(owner: owner, query: .username(username))
        
        if !ignoringCache {
            cachedUsers[key] = user
        } else {
            cachedUsers.removeValue(forKey: key)
        }
        
        return user
    }
    
    func fetchAvatar(username: String, url: URL) async throws -> Image {
        let key = username.lowercased()
        
        if let cachedAvatar = cachedAvatars[key] {
            return cachedAvatar
        }
        
        let avatarURL = AvatarURL(profileImageString: url.absoluteString)
        let avatar = try await ImageLoader.shared.load(avatarURL.original)
        
        cachedAvatars[key] = avatar
        
        return avatar
    }
}

extension TwitterUserController {
    static let mock: TwitterUserController = .init(owner: .mock, client: .mock)
}
