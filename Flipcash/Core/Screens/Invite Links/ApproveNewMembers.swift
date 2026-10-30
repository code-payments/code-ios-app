//
//  ApproveNewMembers.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Observation
import FlipcashCore

nonisolated private let logger = Logger(label: "flipcash.approve-new-members")

/// Which hosted groups have Approve New Members on: the host's link card shows the plain
/// `/chat/{uuid}` link for those, and the current invite link for the rest.
///
/// Kept on this device only, never on the server, and owner-scoped in `UserDefaults` like
/// ``RecentReactionsStore``. Turning it on revokes nothing.
@MainActor
@Observable
final class ApproveNewMembers {

    private var groups: Set<ConversationID>

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let key: String

    /// Loads the owner's setting. Unreadable data is treated as off for every group, the default.
    init(defaults: UserDefaults = .standard, owner: PublicKey) {
        self.defaults = defaults
        self.key = "flipcash-\(owner.base58)-approve-new-members"
        if let data = defaults.data(forKey: key),
           let stored = try? JSONDecoder().decode([Data].self, from: data) {
            self.groups = Set(stored.map(ConversationID.init(data:)))
        } else {
            self.groups = []
        }
    }

    /// Whether the host approves each person who joins `conversationID`.
    func isOn(for conversationID: ConversationID) -> Bool {
        groups.contains(conversationID)
    }

    func set(_ isOn: Bool, for conversationID: ConversationID) {
        if isOn {
            groups.insert(conversationID)
        } else {
            groups.remove(conversationID)
        }
        do {
            defaults.set(try JSONEncoder().encode(groups.map(\.data)), forKey: key)
        } catch {
            logger.error("Failed to encode approve new members", metadata: ["error": "\(error)"])
        }
    }
}
