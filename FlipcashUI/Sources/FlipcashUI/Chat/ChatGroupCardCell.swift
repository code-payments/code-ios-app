//
//  ChatGroupCardCell.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import SwiftUI
import FlipcashCore

/// The group's card at the head of its transcript: the chat's picture, its title, and the rule it
/// runs on. SwiftUI content hosted in the cell so the picture is the same `ContactAvatarView` the
/// navigation title renders.
public final class ChatGroupCardCell: UICollectionViewCell {

    public static let reuseIdentifier = "ChatGroupCardCell"

    /// Fills the cell. `inviteCardWidth` is the width the transcript gives a link card, so the
    /// invite card here matches the same card sent in a chat.
    public func configure(
        with card: ChatGroupCard,
        inviteCardWidth: CGFloat,
        onTap: (() -> Void)? = nil,
        onInvite: (() -> Void)? = nil
    ) {
        contentConfiguration = UIHostingConfiguration {
            GroupCardView(card: card, inviteCardWidth: inviteCardWidth, onTap: onTap, onInvite: onInvite)
        }
        .margins(.all, 0)
    }
}

/// The card body: the same card a group's invite link renders as in a transcript (node
/// 10330:19164), with CTA "Invite People" for a member, opening the invite sheet, and no button for
/// anyone else.
struct GroupCardView: View {

    let card: ChatGroupCard
    /// The card's width: a link card's width in the transcript (node 10330:19164).
    var inviteCardWidth: CGFloat = 290
    /// Opens the chat's own profile; nil leaves the card inert.
    var onTap: (() -> Void)?
    /// Hands out the chat's invite link. The button is drawn only when the card asks for it.
    var onInvite: (() -> Void)?

    var body: some View {
        LinkGroupCardContent(
            state: .resolved(.init(
                title: card.title,
                memberCount: card.memberCount,
                avatarID: card.avatarID,
                imageData: card.imageData,
                blurHash: card.blurhash,
                requirement: card.requirement
            )),
            ctaTitle: showsInvite ? LinkGroupCardContent.Copy.invite : nil,
            onAction: onInvite ?? {},
            ctaAccessibilityIdentifier: "group-card-invite",
            onTapCard: onTap
        )
        .frame(width: inviteCardWidth)
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var showsInvite: Bool {
        card.showsInvite && onInvite != nil
    }

    /// Node 10125:19157's metrics, which the link card still sizes itself from.
    enum Layout {
        static let radius: CGFloat = 12
        static let borderOpacity: Double = 0.1
        static let horizontalPadding: CGFloat = 12
        static let titleGap: CGFloat = 13
        static let requirementGap: CGFloat = 11
    }
}

#Preview("Member / not a member") {
    VStack(spacing: 12) {
        GroupCardView(card: ChatGroupCard(
            title: "BadBoys",
            avatarID: "badboys",
            requirement: "Balance Requirement:\n$100.00 of $BadBoys",
            showsInvite: true
        ), onTap: {}, onInvite: {})
        GroupCardView(card: ChatGroupCard(
            title: "Ballers",
            avatarID: "ballers",
            requirement: "Balance Requirement:\n$100.00 of $BadBoys"
        ), onTap: {})
        GroupCardView(card: ChatGroupCard(title: "Flipcash Staff", avatarID: "staff"))
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.backgroundMain)
}
#endif
