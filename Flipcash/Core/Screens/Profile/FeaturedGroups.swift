//
//  FeaturedGroups.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore

private let logger = Logger(label: "flipcash.featured-groups")

/// The public groups the signed-in user features on their profile, in the order they chose.
///
/// One list read by the You tab, Edit Profile and the picker, so a save shows everywhere at once.
/// Kept apart from `ConversationStore`: the server answers list-view metadata with no members or
/// viewer state, and featuring a group does not require being in it.
@MainActor
@Observable
final class FeaturedGroups {

    /// The most featured groups a profile can carry; the server rejects more.
    static let limit = 10

    private(set) var groups: [Conversation] = []

    @ObservationIgnored private let fetching: (Username) async throws -> [Conversation]

    /// - Parameter fetching: reads the groups a username features.
    init(fetching: @escaping (Username) async throws -> [Conversation]) {
        self.fetching = fetching
    }

    /// Re-reads the list for `username`, returning whether it did. A failure keeps the list already shown.
    @discardableResult
    func load(username: Username) async -> Bool {
        do {
            groups = try await fetching(username)
            return true
        } catch {
            guard !Task.isCancelled else { return false }
            logger.error("Failed to load featured groups", metadata: ["error": "\(error)"])
            ErrorReporting.captureError(error, reason: "Failed to load featured groups")
            return false
        }
    }

    /// Takes the list a save returned, which is the server's word on what is now featured.
    func replace(with groups: [Conversation]) {
        self.groups = groups
    }
}
