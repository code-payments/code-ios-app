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
/// It carries the actions a member has over a group: handing out the invite link, silencing its
/// notifications, and leaving. The head card offers the invite as well, but only while the group is
/// still empty (node 10127:118280), so once anyone else has joined this is the only way to the link.
struct ChatProfileScreen: View {

    let conversationID: ConversationID

    @Environment(ConversationController.self) private var conversationController
    @Environment(SessionContainer.self) private var sessionContainer
    @Environment(AppRouter.self) private var router

    @State private var isInviting = false
    @State private var isLeaving = false
    @State private var dialogItem: DialogItem?

    private var conversation: Conversation? {
        conversationController.conversation(withID: conversationID)
    }

    /// "12 people", from ``ConversationRosterSummary/memberCount`` rather than `members.count` — a
    /// large group embeds only a subset of its roster, so counting it would under-report the chat.
    private var memberCount: String? {
        conversation?.rosterSummary.peopleCount
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

    /// Whether to offer the overflow menu at all: it holds Edit and nothing else, so with the edit
    /// permission withheld there is no menu to draw.
    ///
    /// Reads ``Conversation/canEdit`` — the server's answer — and nothing beside it. Membership and
    /// creator identity are deliberately not consulted; see that property.
    private var canEdit: Bool {
        conversation?.canEdit ?? false
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

                    ChatMuteStatusLabel(conversationID: conversationID)
                }

                VStack(spacing: 0) {
                    if isMember {
                        Row(insets: rowInsets) {
                            Image(systemName: "person.badge.plus")
                                .frame(minWidth: 45)
                            Text("Invite People To Join")
                                .foregroundStyle(.textMain)
                            Spacer()
                        } action: {
                            Analytics.groupInviteSheetOpened(
                                source: .profile,
                                memberCount: conversation?.rosterSummary.memberCount ?? 0
                            )
                            isInviting = true
                        }
                        .accessibilityIdentifier("chat-profile-invite")

                        ChatMuteRow(conversationID: conversationID, insets: rowInsets)
                    }

                    // Outside the membership check, unlike every other row here. A non-member has
                    // no link to hand out, nothing to leave, and no viewer state on a chat they are
                    // not in — but a group you have already left is the one you are most likely to
                    // report.
                    ReportRow(target: .chat(conversationID), insets: rowInsets)

                    if isMember {
                        Row(
                            insets: rowInsets,
                            disabled: isLeaving,
                            accessory: isLeaving ? .loader(.textMain) : nil
                        ) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .frame(minWidth: 45)
                            Text("Leave Group")
                                .foregroundStyle(.textMain)
                            // Only while idle: the loader accessory brings its own spacer.
                            if !isLeaving {
                                Spacer()
                            }
                        } action: {
                            dialogItem = leaveDialog()
                        }
                        .accessibilityIdentifier("chat-profile-leave")
                    }
                }
                .font(.appDisplayXS)
                .padding(.top, 24)

                Spacer()
            }
            .padding(.horizontal, 20)
        }
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            if canEdit {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            router.push(.editGroup(conversationID))
                        } label: {
                            Label {
                                Text("Edit")
                            } icon: {
                                Image.system(.pencil)
                            }
                        }
                    } label: {
                        Image.system(.ellipsis)
                    }
                    .accessibilityIdentifier("chat-profile-overflow")
                }
            }
        }
        .dialog(item: $dialogItem)
        .sheet(isPresented: $isInviting) {
            GroupInviteSheet(conversationID: conversationID, isPresented: $isInviting) { chatID in
                router.push(.tipConversation(chatID))
            }
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

    /// Leaves, then unwinds to the chat list.
    ///
    /// Popping one screen would land on the chat the user just left, which the store still holds —
    /// so they'd be looking at the gated preview of a group they had chosen to be done with, with
    /// Join Chat offering to undo it. The chat list is this stack's root, and it no longer lists
    /// the group, so unwinding there is the same as popping both screens.
    private func leave() async {
        isLeaving = true
        defer { isLeaving = false }
        let memberCount = conversation?.rosterSummary.memberCount ?? 0
        do {
            try await conversationController.leave(conversationID: conversationID)
            Analytics.groupLeft(error: nil, memberCount: memberCount)
            router.popToRoot()
        } catch {
            Analytics.groupLeft(error: error, memberCount: memberCount)
            sessionContainer.session.dialogItem = .error(
                title: "Something Went Wrong",
                subtitle: "We were unable to leave this group. Please try again"
            )
            ErrorReporting.captureError(error, reason: "Failed to leave group")
        }
    }
}
