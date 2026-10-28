//
//  GroupInviteScreen.swift
//  Code
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// What `/chat/invite#s=…` opens (nodes 12846:59, 12846:126, 12846:148, 12846:160). A member goes
/// straight to the chat; anyone else sees the group and joins with the link or, once the link is
/// dead, asks the host to let them in. Mirrors Android's `GroupInviteScreen`.
///
/// The profile's own pieces draw the preview: ``ChatProfileScreen`` is bound to a chat the viewer
/// is in, and this one isn't.
struct GroupInviteScreen: View {

    /// Held for the screen's life only; nil for a link whose fragment holds none.
    let secret: InviteLinkSecret?

    @Environment(SessionContainer.self) private var sessionContainer
    @Environment(ConversationController.self) private var conversationController
    @Environment(AppRouter.self) private var router

    @State private var phase: Phase = .loading
    @State private var token: InviteToken?
    @State private var members: [ConversationMember] = []
    @State private var memberCount: UInt64 = 0
    @State private var isJoining = false
    @State private var isRequesting = false
    @State private var dialogItem: DialogItem?
    @State private var isShowingE2ee = false
    @State private var isReporting = false

    enum Phase {
        case loading
        case preview(Conversation, dead: Bool, reason: GroupInviteLanding.DeadReason?)
        case notFound
        case groupGone
        case banned
        case loadFailed
    }

    private var landing: GroupInviteLanding { sessionContainer.inviteLanding }

    var body: some View {
        content
            .dialog(item: $dialogItem)
            .task { await open() }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            Background(color: .backgroundMain) {
                ProgressView()
                    .tint(Color.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .preview(let conversation, let dead, let reason):
            preview(conversation, dead: dead, reason: reason)
        case .notFound:
            notice(title: "Link Not Found", body: "This invite link isn’t valid. Ask whoever sent it for a new one.")
        case .groupGone:
            notice(title: "Group Not Found", body: "This group no longer exists")
        case .banned:
            notice(title: "You Can’t Join This Group", body: "The host has removed you from this group.")
        case .loadFailed:
            notice(title: "Couldn’t Join Group", body: "Check your connection and try again.")
        }
    }

    // MARK: - Preview -

    private func preview(_ conversation: Conversation, dead: Bool, reason: GroupInviteLanding.DeadReason?) -> some View {
        let id = conversation.id
        let title = conversationController.displayName(for: conversation)
        return Background(color: .backgroundMain) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ProfileHeaderView(
                        cover: .group(id, picture: conversation.coverPicture),
                        title: title,
                        subtitle: nil,
                        bodyText: conversation.description,
                        avatar: {
                            ProfileHeaderAvatar(
                                id: id.description,
                                displayName: title,
                                imageData: sessionContainer.profileAvatars.data(for: .chat(id)),
                                blurhash: conversation.picture?.thumbnailBlurhash
                            )
                        },
                        bannerControls: { EmptyView() },
                        coverAccessory: { EmptyView() },
                        rowActions: { EmptyView() },
                        underSubtitle: { EmptyView() }
                    )

                    // A dead link whose reason isn't known gets no line rather than a guessed one.
                    if let note = dead ? reason.map(Self.deadLine) : "Private group · You’ve been invited to join" {
                        Label {
                            Text(note)
                        } icon: {
                            Image(systemName: "lock.fill")
                        }
                        .labelStyle(.titleAndIcon)
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                        .padding(.horizontal, ProfileHeaderMetrics.inset)
                        .padding(.top, 16)
                        .accessibilityIdentifier("group-invite-note")
                    }

                    let portraits = members.compactMap { GroupPortrait($0, creator: conversation.creator) }
                    GroupChattingGrid(
                        title: PrivateGroupCopy.memberCount(memberCount),
                        portraits: Array(portraits.prefix(GroupChattingGrid.memberLimit))
                    ) { _ in }
                    .padding(.top, 24)
                }
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)
        }
        .scrollEdgeBar(.bottom) {
            Group {
                if dead {
                    requestActions(id)
                } else {
                    Button {
                        Task { await join(id) }
                    } label: {
                        ButtonStateLabel("Join Group", state: isJoining ? .loading : .normal)
                    }
                    .buttonStyle(.filled)
                    .disabled(isJoining)
                    .accessibilityIdentifier("group-invite-join")
                }
            }
            .padding(.horizontal, ProfileHeaderMetrics.inset)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                overflowMenu
            }
        }
        .sheet(isPresented: $isShowingE2ee) {
            E2eeLearnMoreSheet(kind: .privateGroup, isPresented: $isShowingE2ee)
        }
        .fullScreenCover(isPresented: $isReporting) {
            NavigationStack {
                ReportFlowScreen(target: .chat(id))
            }
        }
        .task(id: id) {
            await sessionContainer.profileAvatars.load(.chat(id), picture: conversation.picture)
        }
    }

    /// The profile's menu as a non-member sees it: no Mute, since there's no viewer state to mute.
    private var overflowMenu: some View {
        Menu {
            Button {
                isShowingE2ee = true
            } label: {
                Label("Encryption", systemImage: "lock.fill")
            }
            Divider()
            Button(role: .destructive) {
                isReporting = true
            } label: {
                Label("Report", systemImage: "exclamationmark.bubble")
            }
            // Menu icons follow the app's white tint while the title follows the role.
            .tint(.red)
        } label: {
            Image.system(.ellipsis)
                .renderingMode(.template)
        }
        .accessibilityLabel("More")
        .accessibilityIdentifier("group-invite-overflow")
    }

    /// A dead link can still lead in: the host approves a request, as on the group's profile.
    @ViewBuilder
    private func requestActions(_ id: ConversationID) -> some View {
        if let requestedAt = sessionContainer.lobbyRequests.requestedAt(id) {
            TimelineView(.everyMinute) { context in
                Button(PrivateGroupCopy.pendingTitle(requestedAt: requestedAt, now: context.date)) {}
                    .buttonStyle(.filled)
                    .disabled(true)
            }
        } else {
            Button {
                Task { await requestToJoin(id) }
            } label: {
                ButtonStateLabel("Request to Join", state: isRequesting ? .loading : .normal)
            }
            .buttonStyle(.filled)
            .disabled(isRequesting)
            .accessibilityIdentifier("group-invite-request")
        }
    }

    /// The line that stands where "You've been invited to join" does.
    static func deadLine(_ reason: GroupInviteLanding.DeadReason) -> String {
        switch reason {
        case .exhausted: "This invite link has reached its limit."
        case .expired:   "This invite link has expired."
        case .revoked:   "This invite link was turned off by the host."
        }
    }

    // MARK: - Notice -

    /// Nodes 12846:148 and 12846:160: a title, a line, and OK, centred.
    private func notice(title: String, body: String) -> some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 16) {
                Text(title)
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textMain)
                Text(body)
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
                Button("OK") { router.popTopmost() }
                    .buttonStyle(.subtle)
                    .padding(.top, 8)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, ProfileHeaderMetrics.inset * 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("group-invite-notice")
        }
    }

    // MARK: - Actions -

    private func open() async {
        guard case .loading = phase else { return }
        guard let secret else {
            phase = .notFound
            return
        }
        switch await landing.lookup(secret) {
        case .alreadyMember(let id):
            openChat(id)
        case .notFound:
            phase = .notFound
        case .banned:
            phase = .banned
        case .failed:
            phase = .loadFailed
        case .found(let token, let conversation, let dead):
            self.token = token
            memberCount = conversation.rosterSummary.memberCount
            phase = .preview(conversation, dead: dead != nil, reason: dead)
            // A dead link's roster is refused, so only a live one is asked for.
            if dead == nil {
                await loadRoster(conversation, token: token)
            }
        }
    }

    private func loadRoster(_ conversation: Conversation, token: InviteToken) async {
        switch await landing.roster(of: conversation.id, token: token) {
        case .page(let page, let count):
            members = page
            memberCount = count
        case .denied:
            // The link stopped admitting people while the roster was read. The real status is
            // asked for again; when it can't be learned, the line is left out rather than guessed.
            var reason: GroupInviteLanding.DeadReason?
            if let secret, case .found(_, _, let dead) = await landing.lookup(secret) {
                reason = dead
            }
            phase = .preview(conversation, dead: true, reason: reason)
        case .failed:
            break
        }
    }

    private func join(_ id: ConversationID) async {
        guard let secret, !isJoining, case .preview(let conversation, _, _) = phase else { return }
        isJoining = true
        defer { isJoining = false }
        let result = await landing.join(secret, conversationID: id)
        if let alert = result.alert {
            let item = DialogItem.error(title: alert.title, subtitle: alert.subtitle)
            dialogItem = alert.popsPreview ? item.onDismiss { router.popTopmost() } : item
            return
        }
        switch result {
        case .joined(let id):
            openChat(id)
        case .dead(let reason):
            phase = .preview(conversation, dead: true, reason: reason)
        case .groupGone:
            phase = .groupGone
        case .notFound, .banned, .refused, .failed:
            break
        }
    }

    private func requestToJoin(_ id: ConversationID) async {
        isRequesting = true
        defer { isRequesting = false }
        do {
            if case .alreadyMember = try await sessionContainer.lobbyRequests.request(id) {
                openChat(id)
            }
        } catch let error as LobbyRequests.RequestError {
            dialogItem = .error(title: "Couldn’t Send Request", subtitle: error.explanation)
        } catch {
            dialogItem = .error(
                title: "Something Went Wrong",
                subtitle: "We were unable to send your request. Please try again"
            )
            ErrorReporting.captureError(error, reason: "Failed to request to join a private group from an invite")
        }
    }

    /// Replaces this screen, so back from the chat doesn't land on the link again.
    private func openChat(_ id: ConversationID) {
        router.replaceTopmostAny(AppRouter.Destination.tipConversation(id))
    }
}
