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

    public func configure(with card: ChatGroupCard, onTap: (() -> Void)? = nil) {
        contentConfiguration = UIHostingConfiguration {
            GroupCardView(card: card, onTap: onTap)
        }
        .margins(.all, 0)
    }
}

/// The card body, per node 10125:19157.
private struct GroupCardView: View {

    let card: ChatGroupCard
    /// Opens the chat's own profile; nil leaves the card inert.
    var onTap: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            header

            if let requirement = card.requirement {
                Text(requirement)
                    .font(.default(size: 15, weight: .medium))
                    .foregroundStyle(Color.textMain.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.top, Layout.requirementGap)
            }
        }
        .padding(.horizontal, Layout.horizontalPadding)
        .padding(.top, Layout.topPadding)
        .padding(.bottom, Layout.bottomPadding)
        // Min, not fixed: the app fonts scale with Dynamic Type, so the card grows past its design
        // height at accessibility sizes instead of clipping.
        .frame(width: Layout.width)
        .frame(minHeight: Layout.minHeight)
        .background {
            RoundedRectangle(cornerRadius: Layout.radius, style: .continuous)
                .strokeBorder(Color.white.opacity(Layout.borderOpacity))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }

    /// The picture and the title, with the chevron that says the card opens something (node
    /// 10127:116723). The requirement line below stays outside the tap target — it states a rule,
    /// it does not lead anywhere.
    @ViewBuilder private var header: some View {
        let content = VStack(spacing: 0) {
            ContactAvatarView(
                id: card.avatarID,
                displayName: card.title,
                imageData: card.imageData,
                blurhash: card.blurhash,
                size: Layout.avatar
            )
            .overlay { Circle().strokeBorder(Color.white.opacity(Layout.borderOpacity)) }
            .accessibilityHidden(true)

            HStack(spacing: 6) {
                Text(card.title)
                    .font(.appTextLarge)
                    .foregroundStyle(Color.textMain)
                    .lineLimit(1)
                if onTap != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .padding(.top, Layout.titleGap)
        }
        if let onTap {
            Button(action: onTap) { content }.buttonStyle(.plain)
        } else {
            content
        }
    }

    /// Node 10125:19157 — a 210×228 card, its column starting 31pt down, 13pt under the 80pt
    /// picture and the requirement line centred at 177pt.
    private enum Layout {
        static let width: CGFloat = 210
        static let minHeight: CGFloat = 228
        static let radius: CGFloat = 12
        static let borderOpacity: Double = 0.1
        static let avatar: CGFloat = 80
        static let topPadding: CGFloat = 31
        static let bottomPadding: CGFloat = 24
        static let horizontalPadding: CGFloat = 12
        static let titleGap: CGFloat = 13
        static let requirementGap: CGFloat = 11
    }
}

#Preview("Gated / open") {
    VStack(spacing: 12) {
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
