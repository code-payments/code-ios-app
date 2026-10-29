//
//  FeaturedGroupsSection.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// The "Favorite Community Chats" section on a profile, one row per group in the owner's order. With
/// no groups it draws nothing, or a "None yet" line when `showsEmptyState` is set.
struct FeaturedGroupsSection: View {

    /// The section heading, on every profile that shows it.
    static let title = "Favorite Community Chats"
    /// The line shown in place of the list when the owner has no groups.
    static let emptyText = "None yet"

    let groups: [Conversation]
    /// Whether an empty list still draws the section with the "None yet" line; own profile only.
    var showsEmptyState: Bool = false
    let onTap: (ConversationID) -> Void

    /// Whether the owner's own profile can say "None yet": only once their favorites are known to be
    /// empty, so an account that has favorites never flashes it while the read is in flight or failed.
    /// With no username there is nothing to read, so the list is known empty straight away.
    static func ownProfileShowsEmptyState(hasUsername: Bool, isLoaded: Bool) -> Bool {
        !hasUsername || isLoaded
    }

    /// Whether the section renders for `groupCount` groups.
    static func isVisible(groupCount: Int, showsEmptyState: Bool) -> Bool {
        groupCount > 0 || showsEmptyState
    }

    var body: some View {
        if Self.isVisible(groupCount: groups.count, showsEmptyState: showsEmptyState) {
            VStack(alignment: .leading, spacing: 0) {
                // The empty state sits straight under the details card, with no rule (node 12527:81838).
                if !groups.isEmpty {
                    Color.rowSeparator
                        .frame(height: 1)
                }

                Text(Self.title)
                    .font(.appTextLarge)
                    .foregroundStyle(Color.textMain)
                    .padding(.top, 24)
                    .padding(.bottom, groups.isEmpty ? 10 : 24)
                    .accessibilityAddTraits(.isHeader)

                if groups.isEmpty {
                    Text(Self.emptyText)
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                        .accessibilityIdentifier("profile-featured-groups-empty")
                }

                VStack(spacing: 16) {
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, ProfileHeaderMetrics.inset)
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
                size: 48
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(group.groupLinkTitle)
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textMain)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 12)
            trailing
        }
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
