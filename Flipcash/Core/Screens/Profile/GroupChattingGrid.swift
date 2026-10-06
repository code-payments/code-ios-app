//
//  GroupChattingGrid.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// The people chatting in a public group, as `SampleChatters` returns them: portraits in four
/// columns with a name under each, the host marked with a wave.
///
/// Draws only what the sample carries. Tapping a portrait opens that person's profile, which
/// fetches the rest.
struct GroupChattingGrid: View {

    let chatters: [SampledChatter]
    let onSelect: (UserID) -> Void

    @Environment(SessionContainer.self) private var sessionContainer

    /// Whether the section is drawn: never for a private group, where the sample is denied, and not
    /// for an empty sample.
    nonisolated static func isVisible(isPrivate: Bool, chatters: [SampledChatter]) -> Bool {
        !isPrivate && !chatters.isEmpty
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Chatting")
                .font(.appTextLarge)
                .foregroundStyle(Color.textMain)
                .accessibilityAddTraits(.isHeader)

            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(chatters, id: \.userID) { chatter in
                    portrait(chatter)
                }
            }
        }
        .padding(.horizontal, ProfileHeaderMetrics.inset)
        .accessibilityIdentifier("group-profile-chatting")
    }

    private func portrait(_ chatter: SampledChatter) -> some View {
        let name = chatter.profile.displayName ?? chatter.profile.username?.handle ?? ConversationController.fallbackCounterpartName
        return Button {
            onSelect(chatter.userID)
        } label: {
            VStack(spacing: 6) {
                ContactAvatarView(
                    id: chatter.userID.uuidString,
                    displayName: name,
                    imageData: sessionContainer.profileAvatars.data(for: chatter.userID),
                    blurhash: chatter.profile.profilePicture?.thumbnailBlurhash,
                    size: Self.portraitSize
                )
                .overlay(alignment: .bottomTrailing) {
                    if chatter.isCreator {
                        HostBadge()
                    }
                }

                Text(name)
                    .font(.appTextCaption)
                    .foregroundStyle(Color.textMain)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(chatter.isCreator ? "\(name), host" : name)
        .task(id: chatter.userID) {
            await sessionContainer.profileAvatars.load(userID: chatter.userID, picture: chatter.profile.profilePicture)
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
