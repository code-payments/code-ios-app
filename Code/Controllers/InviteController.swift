//
//  InviteController.swift
//  Code
//
//  Created by Dima Bart on 2021-03-23.
//

import Foundation
import Combine
import CodeServices

@MainActor
class InviteController: ObservableObject {
    
    @Published var inviteCount: Int = 0
    @Published var hasBadge: Bool = false
    
    private let client: Client
    private let user: User
    
    @Defaults(.inviteCount) private var storedInviteCount: Int?
    @Defaults(.lastSeenInviteCount) private var lastSeenInviteCount: Int?
    
    // MARK: - Init -
    
    init(client: Client, user: User) {
        self.client = client
        self.user = user
        
        pullStoredInvites()
        fetchInvites()
    }
    
    deinit {
        trace(.warning, components: "Deallocating InviteController")
    }
    
    // MARK: - Invites -
    
    private func pullStoredInvites() {
        inviteCount = storedInviteCount ?? 0
        hasBadge = inviteCount > (lastSeenInviteCount ?? 0)
    }
    
    private func fetchInvites(for user: User) {
        Task {
            let inviteCount = try await client.fetchInviteCount(userID: user.id)
            storedInviteCount = inviteCount
            pullStoredInvites()
        }
    }
    
    func fetchInvites() {
        fetchInvites(for: user)
    }
    
    func markSeen() {
        lastSeenInviteCount = inviteCount
        pullStoredInvites()
    }
    
    func whitelist(phone: Phone) async throws {
        try await client.whitelist(phoneNumber: phone, userID: user.id)
    }
}

// MARK: - Mock -

extension InviteController {
    static let mock = InviteController(
        client: .mock,
        user: .mock
    )
}
