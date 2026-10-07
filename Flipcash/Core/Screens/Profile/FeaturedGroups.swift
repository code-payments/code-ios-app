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
    @ObservationIgnored private let fillingCovers: ([Conversation]) async -> [ConversationID: Conversation]

    /// - Parameters:
    ///   - fetching: reads the groups a username features.
    ///   - fillingCovers: reads groups in full, keyed by id, for the cover the list leaves out.
    init(
        fetching: @escaping (Username) async throws -> [Conversation],
        fillingCovers: @escaping ([Conversation]) async -> [ConversationID: Conversation] = { _ in [:] }
    ) {
        self.fetching = fetching
        self.fillingCovers = fillingCovers
    }

    /// The group as last read, for handing to the profile a tap opens.
    func group(withID id: ConversationID) -> Conversation? {
        groups.first { $0.id == id }
    }

    /// Re-reads the list for `username`, then each group in full so a profile opened from it shows
    /// the cover on its first frame. Returns whether the list read. A failure keeps the list shown.
    @discardableResult
    func load(username: Username) async -> Bool {
        do {
            groups = try await fetching(username)
            let full = await fillingCovers(groups)
            // Keyed by id rather than replaced wholesale, so a save landing meanwhile stands.
            groups = groups.map { full[$0.id] ?? $0 }
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
