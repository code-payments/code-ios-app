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

/// Turns what a group link's lookup fetched into what its card shows, against the viewer as they
/// are right now. Main-actor because membership and holdings are.
@MainActor
protocol GroupLinkPresenting: AnyObject {

    /// The card for `facts`, read against current membership, holdings and avatar bytes. Reads
    /// observable state, so a caller wrapping it in `withObservationTracking` hears when the
    /// answer would change.
    func present(_ facts: GroupLinkFacts) -> LinkCard.Group.Resolved

    /// Fetches the chat's picture so a later ``present(_:)`` carries its bytes.
    func loadPicture(for facts: GroupLinkFacts) async
}

/// The app's ``GroupLinkPresenting``: the same gate, rules and membership the chat's own screen
/// evaluates, so a card and the screen it opens cannot disagree about what the viewer may do.
@MainActor
final class GroupLinkPresenter: GroupLinkPresenting {

    private let session: Session
    private let conversations: ConversationController
    private let rates: RatesController
    private let avatars: ProfileAvatarStore

    init(session: Session, conversations: ConversationController, rates: RatesController, avatars: ProfileAvatarStore) {
        self.session = session
        self.conversations = conversations
        self.rates = rates
        self.avatars = avatars
    }

    func present(_ facts: GroupLinkFacts) -> LinkCard.Group.Resolved {
        let conversation = facts.conversation
        return groupLinkCard(
            facts,
            gate: conversationGate(session: session, rules: conversation.rules, rates: rates.cachedRates),
            isMember: conversations.isMember(of: conversation),
            imageData: avatars.data(for: .chat(conversation.id))
        )
    }

    func loadPicture(for facts: GroupLinkFacts) async {
        await avatars.load(.chat(facts.conversation.id), picture: facts.conversation.picture)
    }
}

/// The card's contents for a group, given the viewer's gate and membership.
///
/// The action follows ``conversationGatePresentation(_:isMember:)`` — the same mapping the chat's
/// bottom panel draws from — rather than restating its rules: a member opens, an eligible
/// non-member joins, a blocked one is offered the token the rule names. A rule with nothing to buy
/// (staff only) offers nothing.
func groupLinkCard(
    _ facts: GroupLinkFacts,
    gate: ConversationGate,
    isMember: Bool,
    imageData: Data?
) -> LinkCard.Group.Resolved {
    let conversation = facts.conversation

    let action: LinkCard.Group.Action = switch conversationGatePresentation(gate, isMember: isMember) {
    case .open, .readOnly:
        .open
    case .join:
        .join
    case .undetermined:
        // Not produced for a chat whose rules are in hand, which a resolved lookup always has.
        .none
    case .blocked(.staff):
        .none
    case .blocked(.minimumBalance(_, let mint)) where mint == nil || mint == .usdf:
        .addCash
    case .blocked(.minimumBalance(_, let mint)):
        // The lookup names the headline rule's token only. A viewer short of some other token is
        // offered nothing rather than a button labelled with the wrong one.
        if mint == gate.headline?.mint, let name = facts.headlineMintName {
            .getToken(name: name)
        } else {
            .none
        }
    }

    return LinkCard.Group.Resolved(
        title: conversation.groupLinkTitle,
        memberCount: conversation.rosterSummary.peopleCount,
        avatarID: conversation.id.description,
        imageData: imageData,
        blurHash: conversation.picture?.thumbnailBlurhash,
        requirement: groupRequirementLine(gate.headline, mintName: facts.headlineMintName),
        action: action
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
