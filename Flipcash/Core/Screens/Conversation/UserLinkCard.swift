//
//  UserLinkCard.swift
//  Flipcash
//

import Foundation
import FlipcashCore

/// What a person card's lookup fetched: the public profile a tip card link names, and whether it is
/// the viewer's own.
nonisolated struct UserLinkFacts: Sendable, Equatable {
    let profile: Profile
    /// The profile's `userID`, which a fetched profile always carries. Held unwrapped because an
    /// id-less profile is an unclaimed handle, and the lookup never gets this far with one.
    let userID: UserID
    let isOwn: Bool
}

/// Turns what a person link's lookup fetched into what its card shows. Main-actor because the
/// avatar store is.
@MainActor
protocol UserLinkPresenting: AnyObject {

    /// The card for `facts`, with whatever picture bytes have loaded. Reads observable state, so a
    /// caller wrapping it in `withObservationTracking` hears when the bytes land.
    func present(_ facts: UserLinkFacts) -> LinkCard.User.Resolved

    /// Fetches the profile picture so a later ``present(_:)`` carries its bytes.
    func loadPicture(for facts: UserLinkFacts) async
}

/// The app's ``UserLinkPresenting``, reading picture bytes from the shared avatar store.
@MainActor
final class UserLinkPresenter: UserLinkPresenting {

    private let avatars: ProfileAvatarStore

    init(avatars: ProfileAvatarStore) {
        self.avatars = avatars
    }

    func present(_ facts: UserLinkFacts) -> LinkCard.User.Resolved {
        userLinkCard(facts, imageData: avatars.data(for: facts.userID))
    }

    func loadPicture(for facts: UserLinkFacts) async {
        await avatars.load(userID: facts.userID, picture: facts.profile.profilePicture)
    }
}

/// The card's contents for a person, named the way their profile screen names them: the display
/// name, else the handle, else the generic fallback, with the handle line left out when it is
/// already the name.
///
/// Tip card colours (`tipCardCustomization`) are not read: the card has no design for them yet.
func userLinkCard(_ facts: UserLinkFacts, imageData: Data?) -> LinkCard.User.Resolved {
    let profile = facts.profile
    let name = profile.displayName.flatMap { $0.isEmpty ? nil : $0 }
    return LinkCard.User.Resolved(
        userID: facts.userID,
        isOwn: facts.isOwn,
        displayName: name ?? profile.username?.handle ?? ConversationController.fallbackCounterpartName,
        handle: name == nil ? nil : profile.username?.handle,
        joined: profile.joinedLine,
        fee: profile.minimumToChatLine,
        imageData: imageData,
        blurHash: profile.profilePicture?.thumbnailBlurhash
    )
}

extension Profile {

    /// "Joined March 2024", or nil when the server gave no join date. The profile screen and the
    /// person card both state it, so it is worded once, here.
    var joinedLine: String? {
        joinedAt.map { "Joined \($0.formatted(.dateTime.month(.wide).year()))" }
    }

    /// "Minimum To Chat: $1.00", or nil when starting a chat costs nothing. The amount is formatted
    /// as the chat's "Send $X to Start Chatting" button formats the same fee.
    var minimumToChatLine: String? {
        guard let fee = minDmChatInitFee, fee.isPositive else { return nil }
        return "Minimum To Chat: \(fee.formatted())"
    }
}
