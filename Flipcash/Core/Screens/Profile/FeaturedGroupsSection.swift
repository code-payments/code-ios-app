//
//  FeaturedGroupsSection.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// The "Favorite Public Groups" card on a profile, one row per group in the owner's order. Draws
/// nothing when the list is empty.
struct FeaturedGroupsSection: View {

    let groups: [Conversation]
    let onTap: (ConversationID) -> Void

    var body: some View {
        if !groups.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Color.rowSeparator
                    .frame(height: 1)

                Text("Favorite Public Groups")
                    .font(.appTextLarge)
                    .foregroundStyle(Color.textMain)
                    .padding(.top, 24)
                    .padding(.bottom, 12)
                    .accessibilityAddTraits(.isHeader)

                VStack(spacing: 2) {
                    ForEach(groups) { group in
                        Button { onTap(group.id) } label: {
                            FeaturedGroupRow(group: group) { EmptyView() }
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(group.featuredRowAccessibilityLabel))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityIdentifier("profile-featured-group")
                    }
                }
            }
            .padding(.horizontal, ProfileHeaderView<EmptyView, EmptyView, EmptyView>.inset)
            .accessibilityIdentifier("profile-featured-groups")
        }
    }
}

/// A public group as profiles and the picker show it: its picture, title, and its description or
/// head count. Never names members, which a viewer outside the group must not see.
struct FeaturedGroupRow<Trailing: View>: View {

    let group: Conversation
    @ViewBuilder let trailing: Trailing

    @Environment(SessionContainer.self) private var sessionContainer

    private var subtitle: String { group.featuredRowSubtitle }

    var body: some View {
        HStack(spacing: 14) {
            ContactAvatarView(
                id: group.id.description,
                displayName: group.groupLinkTitle,
                imageData: sessionContainer.profileAvatars.data(for: .chat(group.id)),
                blurhash: group.picture?.thumbnailBlurhash,
                size: 48,
                cornerRadius: 15
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(group.groupLinkTitle)
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textMain)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.appTextCaption)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            trailing
        }
        .frame(minHeight: 66)
        .task(id: group.picture?.thumbnailBlobID) {
            await sessionContainer.profileAvatars.load(.chat(group.id), picture: group.picture)
        }
    }
}

extension Conversation {
    /// The secondary line of a featured-group row: the group's description, or its member count when it has none.
    var featuredRowSubtitle: String {
        if let description = description?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
            return description
        }
        return rosterSummary.peopleCount
    }

    /// The single VoiceOver label for a featured-group row: title, then subtitle.
    var featuredRowAccessibilityLabel: String {
        "\(groupLinkTitle), \(featuredRowSubtitle)"
    }
}
