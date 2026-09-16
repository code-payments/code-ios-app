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
/// It carries the two actions a member has over a group: handing out the invite link, and leaving.
/// The head card offers the invite as well, but only while the group is still empty (node
/// 10127:118280), so once anyone else has joined this is the only way to the link.
struct ChatProfileScreen: View {

    let conversationID: ConversationID

    @Environment(ConversationController.self) private var conversationController
    @Environment(SessionContainer.self) private var sessionContainer
    @Environment(\.dismiss) private var dismiss

    @State private var isInviting = false
    @State private var isLeaving = false
    @State private var dialogItem: DialogItem?

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

    /// Whether the viewer belongs to this group. Both actions are a member's: someone reading a
    /// gated preview through an invite link has nothing to hand out and nothing to leave. Read from
    /// the roster rather than the gate — satisfying the balance rule is not membership.
    private var isMember: Bool {
        guard let conversation, conversation.type == .group else { return false }
        return conversationController.isMember(of: conversation)
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

                if isMember {
                    VStack(spacing: 0) {
                        Row(insets: rowInsets, accessory: .chevron) {
                            Image(systemName: "person.badge.plus")
                                .frame(minWidth: 45)
                            Text("Invite People To Join")
                                .foregroundStyle(.textMain)
                        } action: {
                            isInviting = true
                        }
                        .accessibilityIdentifier("chat-profile-invite")

                        Row(
                            insets: rowInsets,
                            disabled: isLeaving,
                            accessory: isLeaving ? .loader(.textMain) : .chevron
                        ) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .frame(minWidth: 45)
                            Text("Leave Group")
                                .foregroundStyle(.textMain)
                        } action: {
                            dialogItem = leaveDialog()
                        }
                        .accessibilityIdentifier("chat-profile-leave")
                    }
                    .font(.appDisplayXS)
                    .padding(.top, 24)
                }

                Spacer()
            }
            .padding(.horizontal, 20)
        }
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
        .dialog(item: $dialogItem)
        .sheet(isPresented: $isInviting) {
            GroupInviteSheet(conversationID: conversationID, isPresented: $isInviting)
        }
        .task {
            await sessionContainer.profileAvatars.load(.chat(conversationID), picture: conversation?.picture)
        }
    }

    private var rowInsets: EdgeInsets {
        .init(top: 25, leading: 0, bottom: 25, trailing: 0)
    }

    private func leaveDialog() -> DialogItem {
        .alert(
            title: "Leave \(title)?",
            subtitle: "You won't receive messages from this group any more. You can join again with an invite link"
        ) {
            DialogAction.destructive("Leave") {
                Task { await leave() }
            }
            DialogAction.cancel()
        }
    }

    /// Leaves, then pops back to the chat the user left from. The conversation stays in the store,
    /// so what they land on is the same gated preview a non-member sees.
    private func leave() async {
        isLeaving = true
        defer { isLeaving = false }
        do {
            try await conversationController.leave(conversationID: conversationID)
            dismiss()
        } catch {
            sessionContainer.session.dialogItem = .error(
                title: "Something Went Wrong",
                subtitle: "We were unable to leave this group. Please try again"
            )
            ErrorReporting.captureError(error, reason: "Failed to leave group")
        }
    }
}
