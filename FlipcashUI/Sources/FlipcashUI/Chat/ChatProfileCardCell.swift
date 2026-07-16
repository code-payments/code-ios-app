//
//  ChatProfileCardCell.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import SwiftUI
import FlipcashCore

/// The counterpart's profile card at the head of a short transcript: avatar, name, and a
/// call to action that opens their contact card — or adds them, when they're not a contact.
/// SwiftUI content hosted in the cell so the avatar is the same `ContactAvatarView` the
/// navigation title renders.
public final class ChatProfileCardCell: UICollectionViewCell {

    public static let reuseIdentifier = "ChatProfileCardCell"

    public func configure(with card: ChatProfileCard, onContactAction: @escaping () -> Void) {
        contentConfiguration = UIHostingConfiguration {
            ProfileCardView(card: card, onContactAction: onContactAction)
        }
        .margins(.all, 0)
    }
}

/// The card body. The pill leads to the same place the navigation title does, so the card is a
/// bigger door to an existing room.
private struct ProfileCardView: View {

    let card: ChatProfileCard
    let onContactAction: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ContactAvatarView(
                id: card.avatarID,
                displayName: card.name,
                imageData: card.imageData,
                size: 80
            )
            .accessibilityHidden(true)

            Text(card.name)
                .font(.appTextLarge)
                .foregroundStyle(Color.textMain)
                .lineLimit(1)
                .padding(.top, 12)

            ProfileCardSubtitle(counterpart: card.counterpart)
                .font(.appTextSmall)
                .padding(.top, 4)

            ContactActionPill(counterpart: card.counterpart, action: onContactAction)
                .padding(.top, 16)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 20)
        // Min, not fixed: the app fonts scale with Dynamic Type, so the card grows past its
        // design height at accessibility sizes instead of clipping.
        .frame(width: 230)
        .frame(minHeight: 250)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

}

/// The line under the name: the contact's number, or the "Unknown Contact" flag.
private struct ProfileCardSubtitle: View {

    let counterpart: ChatProfileCard.Counterpart

    var body: some View {
        switch counterpart {
        case .contact(let phone):
            Text(phone)
                .foregroundStyle(Color.textSecondary)
        case .unknown:
            Text("Unknown Contact")
                .foregroundStyle(Color.warning)
        }
    }
}

#Preview("Known / unknown") {
    VStack(spacing: 12) {
        ProfileCardView(
            card: ChatProfileCard(
                name: "Ted Livingston",
                avatarID: "ted",
                imageData: nil,
                counterpart: .contact(phone: "519 802-3885")
            ),
            onContactAction: {}
        )
        ProfileCardView(
            card: ChatProfileCard(
                name: "519 802-3885",
                avatarID: "unknown",
                imageData: nil,
                counterpart: .unknown
            ),
            onContactAction: {}
        )
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.backgroundMain)
}
#endif
