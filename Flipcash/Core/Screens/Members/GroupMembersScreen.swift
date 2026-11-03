//
//  GroupMembersScreen.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import UIKit
import FlipcashUI
import FlipcashCore

/// Every member of a private group, the host first, then the most recently joined.
struct GroupMembersScreen: View {

    let conversationID: ConversationID

    @Environment(ConversationController.self) private var conversationController
    @Environment(SessionContainer.self) private var sessionContainer
    @Environment(AppRouter.self) private var router
    @Environment(ToastController.self) private var toasts

    @State private var sheetTarget: MemberSheetTarget?
    @State private var silenceTarget: ModerationTarget?

    private var conversation: Conversation? {
        conversationController.conversation(withID: conversationID)
    }

    private var creator: UserID? {
        conversation?.creator
    }

    /// Whether the viewer may silence or ban here, which is what loads the restricted state.
    private var canModerate: Bool {
        guard let state = conversation?.viewerState else { return false }
        return state.canSilence || state.canBan
    }

    private var moderator: MemberModerator {
        MemberModerator(conversationID: conversationID, sessionContainer: sessionContainer, toasts: toasts)
    }

    private var members: [(portrait: GroupPortrait, joinedAt: Date?)] {
        sessionContainer.groupRosters.members(for: conversationID, creator: creator).compactMap { member in
            GroupPortrait(member, creator: creator).map { ($0, member.joinedAt) }
        }
    }

    var body: some View {
        Background(color: .backgroundMain) {
            // Around the list rather than a row, so the rows stay the list's own and keep their
            // swipe; a timed restriction counts down and drops off with it.
            TimelineView(.everyMinute) { context in
                list(now: context.date)
            }
        }
        .navigationTitle("Members")
        .navigationBarTitleDisplayMode(.inline)
        .memberSheet($sheetTarget)
        .silenceUserSheet($silenceTarget)
        .task(id: conversationID) {
            await sessionContainer.groupRosters.refresh(conversationID)
        }
        .task(id: canModerate) {
            guard canModerate else { return }
            await sessionContainer.groupRestrictions.refresh(conversationID)
        }
    }

    private func list(now: Date) -> some View {
        List {
            Text(PrivateGroupCopy.memberCount(conversation?.rosterSummary.memberCount ?? UInt64(members.count)))
                .font(.appTextCaption)
                .foregroundStyle(Color.textSecondary)
                .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 4, trailing: 20))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            ForEach(members, id: \.portrait.userID) { entry in
                let silence = canModerate ? sessionContainer.groupRestrictions.silence(of: entry.portrait.userID, in: conversationID, at: now) : nil
                row(entry.portrait, joinedAt: entry.joinedAt, silence: silence, now: now)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        swipeActions(for: entry.portrait, options: options(for: entry.portrait.userID, isRestricted: silence != nil))
                    }
                    .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func options(for userID: UserID, isRestricted: Bool) -> MemberModerationOptions {
        let state = conversation?.viewerState
        return MemberModerationOptions.resolve(
            canSilence: state?.canSilence ?? false,
            canBan: state?.canBan ?? false,
            isCreator: creator == userID,
            isSelf: userID == sessionContainer.session.userID,
            isRestricted: isRestricted
        )
    }

    private func moderationTarget(for portrait: GroupPortrait) -> ModerationTarget {
        ModerationTarget(
            conversationID: conversationID,
            userID: portrait.userID,
            firstName: GroupModerationCopy.firstName(of: portrait.name),
            groupName: conversation?.title ?? "this group"
        )
    }

    // MARK: - Swipe -

    /// Remove outermost, then Restrict or Lift, matching Android, in the chat list's tonal style. No full swipe: each
    /// one needs a choice or a confirm.
    @ViewBuilder
    private func swipeActions(for portrait: GroupPortrait, options: MemberModerationOptions) -> some View {
        if options.canRemove {
            Button {
                moderator.confirmRemove(moderationTarget(for: portrait))
            } label: {
                SwipeActionLabel(
                    title: "Remove",
                    systemImage: SystemSymbol.personBadgeMinus.rawValue,
                    glyphColor: Color.Sentiment.negative
                )
            }
            .tint(Color.Sentiment.negativeSecondary)
            .accessibilityLabel("Remove from group")
        }
        switch options.silence {
        case .restrict:
            Button {
                silenceTarget = moderationTarget(for: portrait)
            } label: {
                SwipeActionLabel(title: "Restrict", systemImage: "mic.slash", glyphColor: .warning)
            }
            .tint(.warningSecondary)
            .accessibilityLabel("Restrict")
        case .lift:
            Button {
                Task { await moderator.lift(portrait.userID, firstName: GroupModerationCopy.firstName(of: portrait.name)) }
            } label: {
                SwipeActionLabel(title: "Lift Restriction", systemImage: "lock.open")
            }
            .tint(.backgroundRow)
            .accessibilityLabel("Lift restriction")
        case nil:
            EmptyView()
        }
    }

    // MARK: - Row -

    private func row(_ portrait: GroupPortrait, joinedAt: Date?, silence: ConversationSilenceState?, now: Date) -> some View {
        Button {
            if portrait.userID == sessionContainer.session.userID {
                router.push(.userProfile(portrait.userID, origin: .groupMember(conversationID)))
            } else {
                sheetTarget = MemberSheetTarget(conversationID: conversationID, userID: portrait.userID, portrait: portrait)
            }
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
                    } else if let silence {
                        Text(GroupModerationCopy.restrictedStatus(silence, now: now))
                            .font(.appTextSmall)
                            .foregroundStyle(Color.warning)
                    } else if let joinedAt {
                        Text(PrivateGroupCopy.joinedAge(joinedAt: joinedAt, now: now))
                            .font(.appTextSmall)
                            .foregroundStyle(Color.textSecondary)
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
