//
//  GroupMembersScreen.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

/// Every member of a private group, the host first, then the most recently joined.
struct GroupMembersScreen: View {

    let conversationID: ConversationID

    @Environment(ConversationController.self) private var conversationController
    @Environment(SessionContainer.self) private var sessionContainer
    @Environment(AppRouter.self) private var router

    private var conversation: Conversation? {
        conversationController.conversation(withID: conversationID)
    }

    private var creator: UserID? {
        conversation?.creator
    }

    private var members: [(portrait: GroupPortrait, joinedAt: Date?)] {
        sessionContainer.groupRosters.members(for: conversationID, creator: creator).compactMap { member in
            GroupPortrait(member, creator: creator).map { ($0, member.joinedAt) }
        }
    }

    var body: some View {
        Background(color: .backgroundMain) {
            List {
                Text(PrivateGroupCopy.memberCount(conversation?.rosterSummary.memberCount ?? UInt64(members.count)))
                    .font(.appTextCaption)
                    .foregroundStyle(Color.textSecondary)
                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 4, trailing: 20))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                ForEach(members, id: \.portrait.userID) { entry in
                    row(entry.portrait, joinedAt: entry.joinedAt)
                        .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Members")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: conversationID) {
            await sessionContainer.groupRosters.refresh(conversationID)
        }
    }

    private func row(_ portrait: GroupPortrait, joinedAt: Date?) -> some View {
        Button {
            router.push(.userProfile(portrait.userID, origin: .groupMember))
        } label: {
            HStack(spacing: 12) {
                ContactAvatarView(
                    id: portrait.userID.uuidString,
                    displayName: portrait.name,
                    imageData: sessionContainer.profileAvatars.data(for: portrait.userID),
                    blurhash: portrait.picture?.thumbnailBlurhash,
                    size: 40
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(portrait.name)
                        .font(.appTextMedium)
                        .foregroundStyle(Color.textMain)
                    if portrait.isHost {
                        Text("Host")
                            .font(.appTextCaption)
                            .foregroundStyle(Color.textMain)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                    } else if let joinedAt {
                        TimelineView(.everyMinute) { context in
                            Text(PrivateGroupCopy.joinedAge(joinedAt: joinedAt, now: context.date))
                                .font(.appTextSmall)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("group-member-row")
        .task(id: portrait.userID) {
            await sessionContainer.profileAvatars.load(userID: portrait.userID, picture: portrait.picture)
        }
    }
}
