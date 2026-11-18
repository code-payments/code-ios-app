//
//  JoinRequestsAnchor.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// The host's floating notice under a private group's navigation bar: who is waiting to join, and
/// the way to Join Requests. The whole surface is the tap target; Review is its visible affordance.
struct JoinRequestsAnchor: View {

    /// Pending requests, newest first.
    let requests: [LobbyMember]
    let avatarData: (UserID?) -> Data?
    let onReview: () -> Void

    private static let avatarSide: CGFloat = 30
    private static let avatarOverlap: CGFloat = 10
    private static let avatarRing: CGFloat = 2
    private static let maxAvatars = 3

    private var names: [String] {
        requests.map { $0.profile?.displayName ?? $0.profile?.username?.value ?? "" }
    }

    var body: some View {
        Button(action: onReview) {
            HStack(spacing: 12) {
                avatars
                VStack(alignment: .leading, spacing: 2) {
                    Text(PrivateGroupCopy.anchorTitle(names: names))
                        .font(.appTextMedium)
                        .foregroundStyle(Color.textMain)
                    subtitle
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                }
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("Review")
                    .modifier(ReviewCapsule())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: BarMetrics.contentHeight)
            .contentShape(.rect(cornerRadius: BarMetrics.cornerRadius))
        }
        .buttonStyle(.plain)
        .anchorGlass()
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("join-requests-anchor")
    }

    @ViewBuilder
    private var subtitle: some View {
        if requests.count == 1, let first = requests.first {
            TimelineView(.everyMinute) { context in
                Text(PrivateGroupCopy.requestAge(requestedAt: first.enteredAt ?? context.date, now: context.date))
            }
        } else {
            Text(PrivateGroupCopy.anchorNames(names))
        }
    }

    private var avatars: some View {
        HStack(spacing: -Self.avatarOverlap) {
            ForEach(Array(requests.prefix(Self.maxAvatars).enumerated()), id: \.offset) { index, member in
                ContactAvatarView(
                    id: member.userID?.uuidString ?? "",
                    displayName: names[index],
                    imageData: avatarData(member.userID),
                    size: Self.avatarSide
                )
                .padding(Self.avatarRing)
                .background(Color.backgroundMain, in: .circle)
                // Newest first, drawn on top of the ones after it.
                .zIndex(Double(Self.maxAvatars - index))
            }
        }
    }
}

/// Approve's white capsule from Join Requests, drawn as a label since the whole anchor is the button.
private struct ReviewCapsule: ViewModifier {
    func body(content: Content) -> some View {
        Button(action: {}) { content }
            .buttonStyle(JoinRequestCapsuleStyle(kind: .primary))
            .allowsHitTesting(false)
    }
}

extension View {

    /// The reply strip's ground: Liquid Glass at the bar's corner radius, or the field background
    /// before iOS 26.
    @ViewBuilder
    func anchorGlass() -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular.interactive(), in: .rect(cornerRadius: BarMetrics.cornerRadius))
        } else {
            glassFieldBackground(cornerRadius: BarMetrics.cornerRadius)
        }
    }
}
