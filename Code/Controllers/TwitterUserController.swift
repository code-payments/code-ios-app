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
    
    private let owner: KeyPair
    private let client: Client
    
    // MARK: - Init -
    
    init(owner: KeyPair, client: Client) {
        self.owner = owner
        self.client = client
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
}

extension TwitterUserController {
    static let mock: TwitterUserController = .init(owner: .mock, client: .mock)
}
