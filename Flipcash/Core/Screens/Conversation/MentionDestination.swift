//
//  MentionDestination.swift
//  Flipcash
//

import Foundation
import FlipcashCore

/// Where a tapped `@handle` lands, once the handle has been looked up.
nonisolated enum MentionDestination: Equatable {
    /// The handle is the viewer's own. Matches a person card linking to the viewer.
    case ownTipCard
    case profile(UserID, origin: UserProfileOrigin)
    /// Nobody has claimed the handle.
    case noSuchAccount
    /// The lookup never got an answer.
    case lookupFailed

    /// Where a mention lands, given its lookup and the person the open DM is with, if any.
    ///
    /// The counterpart opens the way the DM's own title does, with Mute and without Message, since
    /// Message would lead straight back here. Anyone else gets Message and Send Cash.
    static func destination(for lookup: Result<UserLinkFacts, any Error>, counterpart: UserID?) -> Self {
        switch lookup {
        case .success(let facts):
            if facts.isOwn { return .ownTipCard }
            return .profile(facts.userID, origin: facts.userID == counterpart ? .directMessage : .mention)
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
