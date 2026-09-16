//
//  Database+KnownMembers.swift
//  Flipcash
//

import Foundation
import FlipcashCore
import SQLite

/// Everyone this device can put a name and a face to, gathered across the whole
/// local cache rather than out of one chat.
nonisolated extension Database {

    /// Locally-cached identities for every user the store has ever seen, keyed by user id.
    ///
    /// A large group embeds only a subset of its roster — `chat.v1.Metadata.members` says so
    /// outright — and the contract has no roster RPC, so a sender outside that subset arrives with
    /// nothing but a user id. This is what the client already knows about them from every other
    /// chat it has cached and every profile it has fetched.
    ///
    /// A chat roster row wins over a cached profile: it is the identity a chat published for that
    /// user, which is what the transcript is attributing rows to.
    public func knownMembers() throws -> [UserID: ConversationMember] {
        let p = UserProfileTable()
        let m = ConversationMemberTable()

        var members: [UserID: ConversationMember] = [:]

        let profiles = try reader.prepareRowIterator(p.table).map { row -> (UserID, Profile)? in
            guard let profile = try? JSONDecoder().decode(Profile.self, from: row[p.data]) else { return nil }
            return (row[p.userID], profile)
        }

        for case let (userID, profile)? in profiles {
            members[userID] = ConversationMember(
                userID: userID,
                displayName: profile.displayName ?? "",
                phoneE164: profile.phone?.e164,
                profilePicture: profile.profilePicture,
                username: profile.username
            )
        }

        let roster = try reader.prepareRowIterator(m.table).map { row -> ConversationMember? in
            guard let userID = row[m.userId] else { return nil }
            return ConversationMember(
                userID: userID,
                displayName: row[m.displayName],
                phoneE164: row[m.phoneE164],
                profilePicture: memberProfilePicture(from: row),
                username: row[m.username].flatMap(Username.init)
            )
        }

        for case let member? in roster {
            guard let userID = member.userID else { continue }
            members[userID] = member
        }

        return members
    }
}
