//
//  GroupLinkCard.swift
//  Flipcash
//

import Foundation
import FlipcashCore

/// What a group invite card's lookup fetched: the chat's public record, and the name of the token
/// its entry rule is held in.
///
/// Only the part of `GetChat` a non-member is entitled to is read from here: title, picture, member
/// count and rules. The roster is private to members whatever the group's mode, so `members` is
/// never read, and the fetch asks for redacted content so no message body comes back either.
nonisolated struct GroupLinkFacts: Sendable, Equatable {
    let conversation: Conversation
    /// The name of the token ``headline(for:)`` names, or nil when the rule names none or names the
    /// dollar token, which the card states by amount alone.
    let headlineMintName: String?
}

/// Turns what a group link's lookup fetched into what its card shows. Main-actor because the
/// avatar store is.
@MainActor
protocol GroupLinkPresenting: AnyObject {

    /// The card for `facts`, with whatever picture bytes have loaded. Reads observable state, so a
    /// caller wrapping it in `withObservationTracking` hears when the bytes land.
    func present(_ facts: GroupLinkFacts) -> LinkCard.Group.Resolved

    /// Fetches the chat's picture so a later ``present(_:)`` carries its bytes.
    func loadPicture(for facts: GroupLinkFacts) async
}

/// The app's ``GroupLinkPresenting``, reading picture bytes from the shared avatar store.
@MainActor
final class GroupLinkPresenter: GroupLinkPresenting {

    private let avatars: ProfileAvatarStore

    init(avatars: ProfileAvatarStore) {
        self.avatars = avatars
    }

    func present(_ facts: GroupLinkFacts) -> LinkCard.Group.Resolved {
        groupLinkCard(facts, imageData: avatars.data(for: .chat(facts.conversation.id)))
    }

    func loadPicture(for facts: GroupLinkFacts) async {
        await avatars.load(.chat(facts.conversation.id), picture: facts.conversation.picture)
    }
}

/// The card's contents for a group.
///
/// The same for every viewer: the card states the chat's entry rule without judging the viewer
/// against it, and its one button opens the chat, whose own screen offers the join or the buy.
func groupLinkCard(_ facts: GroupLinkFacts, imageData: Data?) -> LinkCard.Group.Resolved {
    let conversation = facts.conversation
    return LinkCard.Group.Resolved(
        title: conversation.groupLinkTitle,
        memberCount: conversation.rosterSummary.peopleCount,
        avatarID: conversation.id.description,
        imageData: imageData,
        blurHash: conversation.picture?.thumbnailBlurhash,
        requirement: groupRequirementLine(
            headline(for: conversation.rules?.listener ?? []),
            mintName: facts.headlineMintName
        )
    )
}

extension Conversation {

    /// What an untitled group is called on its invite card. Provisional: no design names it yet.
    static let untitledGroupLinkTitle = "Group Chat"

    /// The group's own title, never one built from its roster — ``ConversationController``'s
    /// `displayName(for:)` falls back to member names, which a non-member must not see.
    var groupLinkTitle: String {
        guard let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return Self.untitledGroupLinkTitle
        }
        return title
    }
}

nonisolated extension ConversationGateRequirement {

    /// The token a requirement is held in, when it names one.
    var mint: PublicKey? {
        switch self {
        case .minimumBalance(_, let mint):  mint
        case .staff:                        nil
        }
    }
}
