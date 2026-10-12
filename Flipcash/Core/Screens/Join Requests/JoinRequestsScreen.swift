//
//  JoinRequestsScreen.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

/// The people asking to join a private group the user hosts, newest first, each with Deny and Approve.
struct JoinRequestsScreen: View {

    let conversationID: ConversationID

    @Environment(ConversationController.self) private var conversationController
    @Environment(SessionContainer.self) private var sessionContainer
    @Environment(AppRouter.self) private var router

    @State private var isInviting = false

    private var session: Session { sessionContainer.session }
    private var lobbies: HostedLobbies { sessionContainer.hostedLobbies }

    private var requests: [LobbyMember] {
        lobbies.requests(for: conversationID)
    }

    private var groupName: String {
        conversationController.conversation(withID: conversationID)
            .map { conversationController.displayName(for: $0) } ?? ""
    }

    var body: some View {
        Background(color: .backgroundMain) {
            if requests.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .navigationTitle("Join Requests")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: conversationID) {
            await lobbies.refresh(conversationID)
        }
        .fullScreenCover(isPresented: $isInviting) {
            ShareToChatsSheet(subject: .group(conversationID), isPresented: $isInviting) { chatID in
                router.push(.tipConversation(chatID))
            }
        }
    }

    // MARK: - List -

    private var list: some View {
        List {
            // Above the rows, so it's read before Approve and scrolls away with the list.
            Text("Approving shares the group key with them from this device.")
                .font(.appTextSmall)
                .foregroundStyle(Color.textSecondary)
                .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 12, trailing: 20))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            Section {
                ForEach(requests, id: \.userID) { member in
                    JoinRequestRow(
                        member: member,
                        imageData: sessionContainer.profileAvatars.data(for: member.userID),
                        isApproving: member.userID.map(lobbies.isApproving) ?? false,
                        openProfile: { openProfile(member) },
                        deny: { Task { await deny(member) } },
                        approve: { Task { await approve(member) } }
                    )
                    .task(id: member.userID) {
                        await sessionContainer.profileAvatars.load(
                            userID: member.userID,
                            picture: member.profile?.profilePicture
                        )
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .animation(.default, value: requests.map(\.userID))
    }

    // MARK: - Empty -

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No requests right now")
                .font(.appTextLarge)
                .foregroundStyle(Color.textMain)
            Text(PrivateGroupCopy.noRequests(groupName: groupName))
                .font(.appTextSmall)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
            Button("Share Group") {
                Analytics.groupInviteSheetOpened(
                    source: .profile,
                    memberCount: conversationController.conversation(withID: conversationID)?.rosterSummary.memberCount ?? 0
                )
                isInviting = true
            }
            .buttonStyle(JoinRequestCapsuleStyle(kind: .secondary))
            .padding(.top, 16)
            .accessibilityIdentifier("join-requests-share")
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions -

    private func openProfile(_ member: LobbyMember) {
        guard let userID = member.userID else { return }
        router.push(.userProfile(userID, origin: .joinRequest))
    }

    private func approve(_ member: LobbyMember) async {
        do {
            try await lobbies.approve(member, in: conversationID)
        } catch {
            session.dialogItem = .error(
                title: "Something Went Wrong",
                subtitle: "We were unable to approve this request. Please try again"
            )
            ErrorReporting.captureError(error, reason: "Failed to admit a lobby member")
        }
    }

    private func deny(_ member: LobbyMember) async {
        do {
            try await lobbies.deny(member, in: conversationID)
        } catch {
            session.dialogItem = .error(
                title: "Something Went Wrong",
                subtitle: "We were unable to deny this request. Please try again"
            )
            ErrorReporting.captureError(error, reason: "Failed to deny a lobby member")
        }
    }
}

// MARK: - Row -

private struct JoinRequestRow: View {

    let member: LobbyMember
    let imageData: Data?
    let isApproving: Bool
    let openProfile: () -> Void
    let deny: () -> Void
    let approve: () -> Void

    private var name: String {
        member.profile?.displayName ?? member.profile?.username?.value ?? ""
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: openProfile) {
                HStack(spacing: 12) {
                    ContactAvatarView(
                        id: member.userID?.uuidString ?? "",
                        displayName: name,
                        imageData: imageData,
                        size: 40
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.appTextMedium)
                            .foregroundStyle(Color.textMain)
                        TimelineView(.everyMinute) { context in
                            Text(PrivateGroupCopy.requestAge(requestedAt: member.enteredAt ?? context.date, now: context.date))
                                .font(.appTextCaption)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                    .lineLimit(1)
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button("Deny", action: deny)
                .buttonStyle(JoinRequestCapsuleStyle(kind: .secondary))
                .disabled(isApproving)
                .accessibilityIdentifier("join-request-deny")

            Button(action: approve) {
                // The label keeps its width while the spinner shows.
                Text("Approve")
                    .opacity(isApproving ? 0 : 1)
                    .overlay {
                        if isApproving {
                            ProgressView()
                                .tint(Color.textAction)
                        }
                    }
            }
            .buttonStyle(JoinRequestCapsuleStyle(kind: .primary))
            .allowsHitTesting(!isApproving)
            .accessibilityIdentifier("join-request-approve")
        }
    }
}

/// The small capsule buttons on the Join Requests screen: white Approve, grey Deny and Share Group.
struct JoinRequestCapsuleStyle: ButtonStyle {

    enum Kind { case primary, secondary }

    let kind: Kind

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.appTextSmall)
            .foregroundStyle(foreground.opacity(isEnabled ? 1 : 0.3))
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(background.opacity(isEnabled ? 1 : 0.5), in: .capsule)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }

    private var foreground: Color {
        switch kind {
        case .primary:   .textAction
        case .secondary: .textMain
        }
    }

    private var background: Color {
        switch kind {
        case .primary:   .action
        case .secondary: .action.opacity(0.1)
        }
    }
}
