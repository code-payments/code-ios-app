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
    @State private var isPickingMuteDuration = false
    @State private var isUnmuting = false
    @State private var dialogItem: DialogItem?

    /// The instant the mute row is evaluated against, re-read when a timed mute lapses.
    ///
    /// A timed mute expires with nothing sent from the server, so no event can invalidate the row;
    /// the screen has to notice on its own. See ``muteExpiry``.
    @State private var now = Date.now

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

    private var isMuted: Bool {
        conversation?.isMuted(at: now) ?? false
    }

    /// The mute as the row reports it on the right — "Muted until 5:56 PM" for a timed mute, plain
    /// "Muted" for an indefinite one. Nil when the chat isn't muted.
    ///
    /// Stating the deadline is what makes a timed mute trustworthy: without it the row can't be
    /// told apart from an indefinite one, and the user has no way to know when the chat comes back.
    private var muteDetail: String? {
        guard isMuted, let mute = conversation?.viewerState?.mute else { return nil }
        switch mute {
        case .until(let expiry):
            return "Muted until \(expiry.formattedRelatively(useTimeForToday: true))"
        case .forever:
            return "Muted"
        }
    }

    /// When the current mute lapses, or nil when it is indefinite or absent — the deadline the
    /// refresh below waits on.
    private var muteExpiry: Date? {
        guard case .until(let expiry) = conversation?.viewerState?.mute else { return nil }
        return expiry
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
                            disabled: isUnmuting,
                            accessory: isUnmuting ? .loader(.textMain) : .chevron
                        ) {
                            Image(systemName: isMuted ? "bell.slash" : "bell")
                                .frame(minWidth: 45)
                            Text(isMuted ? "Unmute Notifications" : "Mute Notifications")
                                .foregroundStyle(.textMain)
                            if let muteDetail {
                                Text(muteDetail)
                                    .font(.appTextSmall)
                                    .foregroundStyle(.textSecondary)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                        } action: {
                            // Muting asks for how long; unmuting has nothing to ask, so it is the
                            // tap itself rather than a second sheet with one row on it.
                            if isMuted {
                                Task { await unmute() }
                            } else {
                                isPickingMuteDuration = true
                            }
                        }
                        .accessibilityIdentifier("chat-profile-mute")

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
        .sheet(isPresented: $isPickingMuteDuration) {
            MuteChatSheet(conversationID: conversationID, isPresented: $isPickingMuteDuration)
        }
        .task {
            await sessionContainer.profileAvatars.load(.chat(conversationID), picture: conversation?.picture)
        }
        // Flip the row back to "Mute" the moment a timed mute lapses. Re-run whenever the expiry
        // changes, so muting again while the screen is open re-arms it; cancelled with the screen.
        .task(id: muteExpiry) {
            guard let muteExpiry, muteExpiry > .now else { return }
            try? await Task.sleep(for: .seconds(muteExpiry.timeIntervalSinceNow))
            guard !Task.isCancelled else { return }
            now = .now
        }
    }

    private var rowInsets: EdgeInsets {
        .init(top: 25, leading: 0, bottom: 25, trailing: 0)
    }

    /// Unmutes, staying on the screen — unlike leaving, there is nothing to unwind to.
    private func unmute() async {
        isUnmuting = true
        defer { isUnmuting = false }
        do {
            try await conversationController.unmute(conversationID: conversationID)
            now = .now
        } catch {
            sessionContainer.session.dialogItem = .error(
                title: "Something Went Wrong",
                subtitle: "We were unable to unmute this chat. Please try again"
            )
            ErrorReporting.captureError(error, reason: "Failed to unmute chat")
        }
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
        do {
            try await conversationController.leave(conversationID: conversationID)
            router.popToRoot()
        } catch {
            sessionContainer.session.dialogItem = .error(
                title: "Something Went Wrong",
                subtitle: "We were unable to leave this group. Please try again"
            )
            ErrorReporting.captureError(error, reason: "Failed to leave group")
        }
    }
}
