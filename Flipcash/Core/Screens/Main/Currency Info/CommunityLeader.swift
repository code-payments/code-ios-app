//
//  CommunityLeader.swift
//  Flipcash
//
//  Community Leader on Currency Info: the Flipcash user who launched the currency, one row that
//  opens their profile.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

/// The text and visibility rules for the community leader, apart from the views so Android's
/// matching ones can be checked against them.
nonisolated enum CommunityLeader {

    static let title = "Community Leader"

    /// The leader the section shows: none when the server named nobody or the profile has no
    /// display name.
    static func shown(_ leader: Profile?) -> Profile? {
        guard let leader, let name = leader.displayName, !name.isEmpty else { return nil }
        return leader
    }

    /// "@jeff", or nil when the leader has no username, which leaves the name on its own.
    static func subtitle(for leader: Profile) -> String? {
        leader.username?.handle
    }

    /// "Community Leader, Jeff Yanta, @jeff. Opens profile.", the last sentence only when the row
    /// opens the profile.
    static func accessibilityLabel(for leader: Profile, isTappable: Bool) -> String {
        let parts = [title, leader.displayName ?? "", subtitle(for: leader)].compactMap { $0 }
        let label = parts.joined(separator: ", ")
        return isTappable ? "\(label). Opens profile." : label
    }
}

/// The leader's card. Tappable, with a chevron, only when the profile carries a user id.
struct CommunityLeaderRow: View {

    @Environment(SessionContainer.self) private var sessionContainer

    let leader: Profile
    let onTap: (UserID) -> Void

    var body: some View {
        Group {
            if let userID = leader.userID {
                Button { onTap(userID) } label: { card(showsChevron: true) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(CommunityLeader.accessibilityLabel(for: leader, isTappable: true))
            } else {
                card(showsChevron: false)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(CommunityLeader.accessibilityLabel(for: leader, isTappable: false))
            }
        }
        .task(id: leader.userID) {
            await sessionContainer.profileAvatars.load(userID: leader.userID, picture: leader.profilePicture)
        }
    }

    private func card(showsChevron: Bool) -> some View {
        let name = leader.displayName ?? ""
        return CommunityRowCard(title: name, subtitle: CommunityLeader.subtitle(for: leader), showsChevron: showsChevron) {
            ContactAvatarView(
                id: leader.userID?.uuidString ?? name,
                displayName: name,
                imageData: leader.userID.flatMap { sessionContainer.profileAvatars.data(for: .user($0)) },
                blurhash: leader.profilePicture?.thumbnailBlurhash,
                size: 42
            )
        }
    }
}

/// "Community Leader" over the leader's row.
struct CommunityLeaderSection: View {

    let leader: Profile
    let onSelect: (UserID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Community Leader")
                .font(.default(size: 19, weight: .bold))
                .foregroundStyle(Color.textMain)
                .frame(minHeight: 28)
                .accessibilityAddTraits(.isHeader)
            CommunityLeaderRow(leader: leader, onTap: onSelect)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
