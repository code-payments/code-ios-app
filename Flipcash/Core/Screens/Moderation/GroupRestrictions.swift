//
//  GroupRestrictions.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Observation
import FlipcashCore

nonisolated private let logger = Logger(label: "flipcash.group-restrictions")

/// Who is restricted in each group the signed-in user moderates, for the Members swipe and the
/// member sheet.
///
/// Read with `GetRestrictedUsers`, which only a moderator may call. The server's index trails
/// writes, so a silence this device set or lifted wins over any page read afterward.
@MainActor
@Observable
final class GroupRestrictions {

    typealias GetRestrictedUsers = @MainActor @Sendable (ConversationID) async throws -> [ConversationRestrictedUser]

    private var silences: [ConversationID: [UserID: ConversationSilenceState]] = [:]
    /// Members whose silence this device changed, whose local state a page can't overwrite.
    @ObservationIgnored private var written: [ConversationID: Set<UserID>] = [:]

    @ObservationIgnored private let getRestrictedUsers: GetRestrictedUsers

    init(getRestrictedUsers: @escaping GetRestrictedUsers) {
        self.getRestrictedUsers = getRestrictedUsers
    }

    /// `userID`'s silence in `conversationID` while it is in force at `date`, or nil.
    func silence(of userID: UserID, in conversationID: ConversationID, at date: Date) -> ConversationSilenceState? {
        guard let silence = silences[conversationID]?[userID], silence.isActive(at: date) else { return nil }
        return silence
    }

    /// Reads who is restricted in `conversationID`. A removed member is left out, since a ban wins
    /// over a silence. A failed read keeps what was held.
    func refresh(_ conversationID: ConversationID) async {
        do {
            let users = try await getRestrictedUsers(conversationID)
            var fresh: [UserID: ConversationSilenceState] = [:]
            for user in users {
                guard let userID = user.userID, !user.isRemoved, let silence = user.silence else { continue }
                fresh[userID] = silence
            }
            let held = silences[conversationID] ?? [:]
            for userID in written[conversationID] ?? [] {
                fresh[userID] = held[userID]
            }
            silences[conversationID] = fresh
        } catch {
            logger.warning("Failed to read a group's restricted users", metadata: [
                "conversationID": "\(conversationID)",
                "error": "\(error)",
            ])
        }
    }

    /// Records a silence this device just set, or lifted when `silence` is nil.
    func record(_ silence: ConversationSilenceState?, for userID: UserID, in conversationID: ConversationID) {
        written[conversationID, default: []].insert(userID)
        silences[conversationID, default: [:]][userID] = silence
    }
}
