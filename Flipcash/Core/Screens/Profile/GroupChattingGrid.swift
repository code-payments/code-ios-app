//
//  GroupChattingGrid.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// One portrait in a group's people grid.
nonisolated struct GroupPortrait: Sendable, Hashable {
    let userID: UserID
    let name: String
    let picture: ProfilePicture?
    let isHost: Bool

    init(userID: UserID, name: String, picture: ProfilePicture?, isHost: Bool) {
        self.userID = userID
        self.name = name
        self.picture = picture
        self.isHost = isHost
    }

    init(_ chatter: SampledChatter) {
        self.init(
            userID: chatter.userID,
            name: chatter.profile.displayName ?? chatter.profile.username?.handle ?? ConversationController.fallbackCounterpartName,
            picture: chatter.profile.profilePicture,
            isHost: chatter.isCreator
        )
    }

    /// A roster member's portrait, or `nil` for a member the server sent without a user id.
    init?(_ member: ConversationMember, creator: UserID?) {
        guard let userID = member.userID else { return nil }
        let name = member.displayName.isEmpty
            ? (member.username?.handle ?? ConversationController.fallbackCounterpartName)
            : member.displayName
        self.init(userID: userID, name: name, picture: member.profilePicture, isHost: userID == creator)
    }
}

/// The people in a group: portraits in four columns with a name under each, the host marked with a
/// wave. A public group shows the `SampleChatters` sample as "Chatting"; a private group shows its
/// roster as "Members", with a count that opens the full list.
///
/// Tapping a portrait opens that person's profile, which fetches the rest.
struct GroupChattingGrid: View {

    let title: String
    let portraits: [GroupPortrait]
    let count: UInt64?
    let onCount: (() -> Void)?
    let onSelect: (UserID) -> Void

    @Environment(SessionContainer.self) private var sessionContainer

    init(title: String, portraits: [GroupPortrait], count: UInt64? = nil, onCount: (() -> Void)? = nil, onSelect: @escaping (UserID) -> Void) {
        self.title = title
        self.portraits = portraits
        self.count = count
        self.onCount = onCount
        self.onSelect = onSelect
    }

    init(chatters: [SampledChatter], onSelect: @escaping (UserID) -> Void) {
        self.init(title: "Chatting", portraits: chatters.map(GroupPortrait.init), onSelect: onSelect)
    }

    /// Whether the Chatting section is drawn: never for a private group, where the sample is denied,
    /// and not for an empty sample.
    nonisolated static func isVisible(isPrivate: Bool, chatters: [SampledChatter]) -> Bool {
        !isPrivate && !chatters.isEmpty
    }

    /// The most portraits a private group's Members grid draws; the count opens the rest.
    nonisolated static let memberLimit = 16

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(title)
                    .font(.appTextLarge)
                    .foregroundStyle(Color.textMain)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if let count, let onCount {
                    Button(action: onCount) {
                        HStack(spacing: 4) {
                            Text("\(count)")
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("See all \(count) members")
                    .accessibilityIdentifier("group-profile-members-count")
                }
            }

            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(portraits, id: \.userID) { portrait in
                    cell(portrait)
                }
            }
        }
        .padding(.horizontal, ProfileHeaderMetrics.inset)
        .accessibilityIdentifier("group-profile-chatting")
    }

    private func cell(_ portrait: GroupPortrait) -> some View {
        Button {
            onSelect(portrait.userID)
        } label: {
            VStack(spacing: 6) {
                ContactAvatarView(
                    id: portrait.userID.uuidString,
                    displayName: portrait.name,
                    imageData: sessionContainer.profileAvatars.data(for: portrait.userID),
                    blurhash: portrait.picture?.thumbnailBlurhash,
                    size: Self.portraitSize
                )
                .overlay(alignment: .bottomTrailing) {
                    if portrait.isHost {
                        HostBadge()
                    }
                }

                Text(portrait.name)
                    .font(.appTextCaption)
                    .foregroundStyle(Color.textMain)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(portrait.isHost ? "\(portrait.name), host" : portrait.name)
        .task(id: portrait.userID) {
            await sessionContainer.profileAvatars.load(userID: portrait.userID, picture: portrait.picture)
        }
    }

    private static let portraitSize: CGFloat = 60
}

/// The wave on the host's portrait, bottom-trailing.
private struct HostBadge: View {
    var body: some View {
        Image(systemName: "hand.wave")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.backgroundMain)
            .frame(width: 22, height: 22)
            .background(Color.textMain, in: Circle())
            .overlay(Circle().stroke(Color.backgroundMain, lineWidth: 2))
            .offset(x: 2, y: 2)
            .accessibilityHidden(true)
    }
}
