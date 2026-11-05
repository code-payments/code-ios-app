//
//  MentionDestination.swift
//  Flipcash
//

import Foundation
import FlipcashCore

/// Where a tapped `@handle` or a followed `flipcash.com/<handle>` link lands, once the handle has
/// been looked up.
nonisolated enum MentionDestination: Equatable {
    /// The handle is the viewer's own. Matches a person card linking to the viewer.
    case ownTipCard
    case profile(UserID, origin: UserProfileOrigin)
    /// A group transcript's mention of someone else: the member sheet, without its group section
    /// when the person has left or been removed.
    case memberSheet(UserID, isFormerMember: Bool)
    /// Nobody has claimed the handle.
    case noSuchAccount
    /// The lookup never got an answer.
    case lookupFailed

    /// Where a handle lands, given its lookup, the person the open DM is with, if any, and the
    /// origin anyone else's profile opens with.
    ///
    /// The counterpart opens the way the DM's own title does, with Mute and without Message, since
    /// Message would lead straight back here. Anyone else gets Message and Send Cash.
    ///
    /// In a group (`inGroup`), anyone else opens the member sheet. `groupMembers` is the roster
    /// when it is known: someone it leaves out is a former member. `nil` means it can't be told,
    /// as in a public group, and the person is treated as a member.
    static func destination(
        for lookup: Result<UserLinkFacts, any Error>,
        counterpart: UserID?,
        origin: UserProfileOrigin = .mention,
        inGroup: Bool = false,
        groupMembers: Set<UserID>? = nil
    ) -> Self {
        switch lookup {
        case .success(let facts):
            if facts.isOwn { return .ownTipCard }
            if inGroup {
                return .memberSheet(facts.userID, isFormerMember: groupMembers.map { !$0.contains(facts.userID) } ?? false)
            }
            return .profile(facts.userID, origin: facts.userID == counterpart ? .directMessage : origin)
        case .failure(let error):
            return isUnclaimed(error) ? .noSuchAccount : .lookupFailed
        }
    }

    // The server answers an unclaimed handle with an id-less profile, which the lookup throws as
    // `NoSuchAccount`; `notFound` is the same answer if it ever comes back as an error instead.
    private static func isUnclaimed(_ error: any Error) -> Bool {
        switch error {
        case is NoSuchAccount:                 true
        case let error as ErrorFetchProfile:   error == .notFound
        default:                               false
        }
    }
}
