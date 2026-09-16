//
//  ChatProfileScreen.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// A group chat's own profile — its picture, title, size and entry rule — reached by tapping the
/// chat's head card or its navigation title, the way a DM's title opens the counterpart's profile.
///
/// Read-only. Every action the design hangs here (node 10127:116723's invite link, and leave/mute)
/// needs a membership RPC the contract does not carry yet, so the screen states what the chat is
/// rather than offering buttons that cannot do anything.
struct ChatProfileScreen: View {

    let conversationID: ConversationID

    @Environment(ConversationController.self) private var conversationController
    @Environment(SessionContainer.self) private var sessionContainer

    private var conversation: Conversation? {
        conversationController.conversation(withID: conversationID)
    }

    /// "12 people", from ``ConversationRosterSummary/memberCount`` rather than `members.count` — a
    /// large group embeds only a subset of its roster, so counting it would under-report the chat.
    private var memberCount: String? {
        guard let count = conversation?.rosterSummary.memberCount else { return nil }
        return count == 1 ? "1 person" : "\(count) people"
    }

    private var title: String {
        conversation.map { conversationController.displayName(for: $0) } ?? ""
    }

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 16) {
                ContactAvatarView(
                    id: conversationID.description,
                    displayName: title,
                    imageData: sessionContainer.profileAvatars.data(for: .chat(conversationID)),
                    blurhash: conversation?.picture?.thumbnailBlurhash,
                    size: 88
                )
                .padding(.top, 40)

                // Title and size read as one block under the picture, the way the counterpart's
                // profile groups a name with its handle.
                VStack(spacing: 5) {
                    Text(title)
                        .font(.appDisplaySmall)
                        .foregroundStyle(.textMain)
                        .multilineTextAlignment(.center)

                    if let memberCount {
                        Text(memberCount)
                            .font(.appTextSmall)
                            .foregroundStyle(.textSecondary)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 20)
        }
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
        .task {
            await sessionContainer.profileAvatars.load(.chat(conversationID), picture: conversation?.picture)
        }
    }
}
