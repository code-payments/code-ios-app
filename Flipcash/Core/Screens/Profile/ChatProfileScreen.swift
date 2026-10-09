//
//  ChatProfileScreen.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import UIKit
import FlipcashCore
import FlipcashUI
import FlipcashStore

/// A group chat's own profile (node 10913:358): the shared profile header with the group's cover,
/// picture and description, who is chatting, what it takes to join and to chat, and one pinned
/// button that opens the chat.
///
/// Reached by tapping the chat's head card or its navigation title, the way a DM's title opens the
/// counterpart's profile. The actions a member has over the group sit in the ⋯ menu. Opened from
/// the chat, there is no pinned button, since the chat is one back away, and Leave Chat ends the
/// scroll; otherwise Leave Chat sits under the pinned button.
struct ChatProfileScreen: View {

    let conversationID: ConversationID
    let origin: ChatProfileOrigin

    @Environment(ConversationController.self) private var conversationController
    @Environment(SessionContainer.self) private var sessionContainer
    @Environment(RatesController.self) private var ratesController
    @Environment(AppRouter.self) private var router
    @Environment(ToastController.self) private var toasts

    @State private var isInviting = false
    @State private var isPickingMuteDuration = false
    @State private var isReporting = false
    @State private var isShowingE2ee = false
    @State private var isLeaving = false
    @State private var dialogItem: DialogItem?
    @State private var chatters: [SampledChatter] = []
    @State private var mintMetadata: [PublicKey: StoredMintMetadata] = [:]
    @State private var mintNamesTimedOut = false
    @State private var scrollFit = ProfileScrollFit()

    private var session: Session { sessionContainer.session }

    private var conversation: Conversation? {
        conversationController.conversation(withID: conversationID)
    }

    private var title: String {
        conversation.map { conversationController.displayName(for: $0) } ?? ""
    }

    /// Whether the viewer belongs to this group. Read from the roster rather than the gate:
    /// satisfying the balance rule is not membership.
    private var isMember: Bool {
        guard let conversation, conversation.type == .group else { return false }
        return conversationController.isMember(of: conversation)
    }

    /// Reads ``Conversation/canEdit``, the server's answer, and nothing beside it. Membership and
    /// creator identity are deliberately not consulted; see that property.
    private var canEdit: Bool {
        conversation?.canEdit ?? false
    }

    private var isPrivate: Bool {
        conversation?.isPrivate ?? false
    }

    private var requirements: GroupBalanceRequirements? {
        GroupBalanceRequirements(conversation?.rules)
    }

    /// Every mint the card and the button name, deduplicated.
    private var namedMints: [PublicKey] {
        var mints: [PublicKey] = []
        let candidates = [requirements?.join?.mints.first, requirements?.chat?.mints.first]
        for mint in candidates.compactMap({ $0 }) where !mints.contains(mint) {
            mints.append(mint)
        }
        return mints
    }

    /// Whether the requirements can be stated: every token they name is known, so "$10" never turns
    /// into "$10 of NYC" in front of the viewer. A token that won't resolve stops holding them back
    /// after a moment.
    private var requirementsNamed: Bool {
        mintNamesTimedOut || namedMints.allSatisfy { $0 == .usdf || mintMetadata[$0] != nil }
    }

    /// "$10 of NYC", or the bare amount for a dollar-token or any-holding rule: the dollar amount
    /// already states it, the way the gate panel words it.
    private func holding(_ amount: FiatAmount, mint: PublicKey?) -> String {
        let formatted = amount.formattedDroppingZeroFraction()
        guard let mint, mint != .usdf, let name = mintMetadata[mint]?.name else { return formatted }
        return "\(formatted) of \(name)"
    }

    // MARK: - Body -

    var body: some View {
        Background(color: .backgroundMain) {
            ScrollView {
                VStack(spacing: 0) {
                    ProfileHeaderView(
                        cover: .group(conversationID, picture: conversation?.coverPicture),
                        title: title,
                        subtitle: nil,
                        bodyText: conversation?.description,
                        avatar: {
                            ProfileHeaderAvatar(
                                id: conversationID.description,
                                displayName: title,
                                imageData: sessionContainer.profileAvatars.data(for: .chat(conversationID)),
                                blurhash: conversation?.picture?.thumbnailBlurhash
                            )
                        },
                        bannerControls: { EmptyView() },
                        // On the cover rather than in the action row: a timed mute's label is
                        // wide enough to wrap Edit Group and push Share off the screen.
                        coverAccessory: {
                            if isMember {
                                ChatMuteStatusLabel(conversationID: conversationID, reservesSpace: false)
                            }
                        },
                        rowActions: {
                            if canEdit {
                                ProfileEditCapsule(title: "Edit Group") {
                                    router.push(.editGroup(conversationID))
                                }
                                .accessibilityIdentifier("chat-profile-edit")
                            }
                            shareButton
                        },
                        underSubtitle: { EmptyView() }
                    )

                    if GroupChattingGrid.isVisible(isPrivate: isPrivate, chatters: chatters) {
                        GroupChattingGrid(chatters: chatters) { userID in
                            router.push(.userProfile(userID, origin: .groupMember))
                        }
                        .padding(.top, 24)
                    }

                    if let requirements, requirementsNamed {
                        balanceRequirements(requirements)
                            .padding(.top, 24)
                    }

                    if origin == .chat, isMember {
                        // Holds Leave Chat at the bottom of the screen when the content is short.
                        Spacer(minLength: 24)
                        leaveButton
                            .padding(.horizontal, ProfileHeaderMetrics.inset)
                    }
                }
                .frame(minHeight: max(scrollFit.visibleHeight - 24, 0), alignment: .top)
                .padding(.bottom, 24)
            }
            .profilePinnedBackdropClearance(isActive: origin != .chat || scrollFit.overflows)
            .profileScrollFit($scrollFit)
            // The banner runs under the status bar.
            .ignoresSafeArea(edges: .top)
            // The blur only belongs once the banner has scrolled up under the bar.
            .hidesTopScrollEdge(untilOffset: ProfileCoverBanner<EmptyView>.height / 2)
        }
        .scrollEdgeBar(.bottom) {
            pinnedActions
                .toastClearance(toasts)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                overflowMenu
            }
        }
        .dialog(item: $dialogItem)
        .fullScreenCover(isPresented: $isInviting) {
            ShareToChatsSheet(subject: .group(conversationID), isPresented: $isInviting) { chatID in
                router.push(.tipConversation(chatID))
            }
        }
        .sheet(isPresented: $isPickingMuteDuration) {
            MuteChatSheet(conversationID: conversationID, isPresented: $isPickingMuteDuration)
        }
        .sheet(isPresented: $isShowingE2ee) {
            E2eeLearnMoreSheet(kind: .group, isPresented: $isShowingE2ee)
        }
        .fullScreenCover(isPresented: $isReporting) {
            NavigationStack {
                ReportFlowScreen(target: .chat(conversationID))
            }
        }
        .task {
            // A favorite group can be one the user isn't in, which the feed doesn't hold.
            let conversation = await conversationController.hydratedConversation(withID: conversationID)
            await sessionContainer.profileAvatars.load(.chat(conversationID), picture: conversation?.picture)
            await conversationController.fillCoverPicture(for: conversationID)
        }
        // Waits for the conversation to land before asking: a private group's sample is denied.
        .task(id: conversation.map { $0.isPrivate } ) {
            guard let conversation, !conversation.isPrivate else { return }
            await loadChatters()
        }
        // Name the requirements in the token they ask for. The mint may be one the user holds
        // nothing of, so the local store can miss and the fetch is what fills it.
        .task(id: namedMints) {
            var metadata: [PublicKey: StoredMintMetadata] = [:]
            for mint in namedMints {
                if let stored = session.storedMintMetadata(for: mint) {
                    metadata[mint] = stored
                } else if let fetched = try? await session.fetchMintMetadata(mint: mint) {
                    metadata[mint] = fetched
                }
            }
            mintMetadata = metadata
        }
        .task(id: namedMints) {
            mintNamesTimedOut = false
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            mintNamesTimedOut = true
        }
    }

    // MARK: - Chatting -

    /// Best effort: a sample that fails to load leaves the section hidden, as an empty one does.
    private func loadChatters() async {
        do {
            chatters = try await sessionContainer.flipClient.sampleChatters(
                owner: session.ownerKeyPair,
                conversationID: conversationID
            ).chatters
        } catch {
            chatters = []
        }
    }

    // MARK: - Balance Requirements -

    private func balanceRequirements(_ requirements: GroupBalanceRequirements) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Balance Requirements")
                .font(.appTextLarge)
                .foregroundStyle(Color.textMain)
                .accessibilityAddTraits(.isHeader)

            let token = requirements.soleToken.flatMap { mintMetadata[$0] }
            VStack(spacing: 0) {
                if let token {
                    tokenRow(token)
                    Color.rowSeparator
                        .frame(height: 1)
                }
                requirementRow("Join", requirements.join, namesToken: token == nil, identifier: "group-profile-join-minimum")
                Color.rowSeparator
                    .frame(height: 1)
                requirementRow("Chat", requirements.chat, namesToken: token == nil, identifier: "group-profile-chat-minimum")
            }
            .background(Color.backgroundRow, in: RoundedRectangle(cornerRadius: Metrics.boxRadius, style: .continuous))

            if let yourBalance = yourBalance(in: requirements) {
                HStack {
                    Text("Your Balance")
                    Spacer()
                    Text(yourBalance)
                }
                .font(.appTextSmall)
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, 16)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("group-profile-your-balance")
            }
        }
        .padding(.horizontal, ProfileHeaderMetrics.inset)
    }

    /// The chat's one token, opening its info page. The rows below then state bare amounts.
    private func tokenRow(_ token: StoredMintMetadata) -> some View {
        Button {
            Analytics.tokenInfoOpened(from: .openedFromChat, mint: token.mint)
            router.push(.currencyInfo(token.mint))
        } label: {
            HStack {
                Text("Community Currency")
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                TokenIconWithName(url: token.imageURL, monogramID: token.mint.base58, name: token.name, iconSize: 24)
                Image(systemName: "chevron.right")
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("group-profile-token")
    }

    private func requirementRow(_ label: String, _ requirement: MinimumBalanceRequirement?, namesToken: Bool, identifier: String) -> some View {
        HStack {
            Text(label)
                .font(.appTextSmall)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Text(requirement.map { holding($0.amount, mint: namesToken ? $0.mints.first : nil) } ?? "None")
                .font(.appTextMedium)
                .foregroundStyle(Color.textMain)
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }

    /// What the viewer holds toward the rule, in the rule's currency and token: the join rule when
    /// there is one, else the chat rule. Nil while no rate can restate it.
    private func yourBalance(in requirements: GroupBalanceRequirements) -> String? {
        guard let rule = requirements.join ?? requirements.chat else { return nil }
        let mint = rule.mints.first
        let held = heldBalance(in: mint, session: session).roundedToSmallestUnit()
        let currency = rule.amount.currency
        let stated: FiatAmount
        if currency == .usd {
            stated = held
        } else {
            guard let rate = ratesController.cachedRates[currency] else { return nil }
            stated = held.converting(to: rate)
        }
        return holding(stated, mint: mint)
    }

    // MARK: - Pinned -

    @ViewBuilder
    private var pinnedActions: some View {
        // Opened from the chat, the chat is one back away and Leave Chat ends the scroll instead;
        // the empty bar fades out content that scrolls under the home indicator.
        if origin == .chat {
            Color.clear
                .frame(height: 0)
                .profileBarlessFade(isActive: scrollFit.overflows)
        } else if conversation != nil {
            VStack(spacing: 8) {
                openChatButton
                if isMember {
                    leaveButton
                        // A text-only button is a full button tall, so its frame already leaves
                        // room under the title; let that room overlap the home indicator's inset.
                        .padding(.bottom, -12)
                }
            }
            .padding(.horizontal, ProfileHeaderMetrics.inset)
            .padding(.top, 12)
            .padding(.bottom, isMember ? 0 : 8)
        }
    }

    /// Joining and buying in happen in the chat's own gate, so the profile only ever opens it.
    private var openChatButton: some View {
        Button("Open Chat") { showChat() }
            .buttonStyle(.filled)
            .accessibilityIdentifier("group-profile-cta")
    }

    /// Returns to the chat when it sits underneath, otherwise pushes it over this profile.
    private func showChat() {
        switch origin {
        case .chat:
            router.popTopmost()
        case .featuredGroup, .link:
            router.push(.tipConversation(conversationID))
        }
    }

    // MARK: - Share -

    private var shareButton: some View {
        ProfileActionCircle(image: Image.asset(.shareOS)) {
            openInvite()
        }
        .accessibilityLabel("Share group")
        .accessibilityIdentifier("chat-profile-share")
    }

    private func openInvite() {
        Analytics.groupInviteSheetOpened(
            source: .profile,
            memberCount: conversation?.rosterSummary.memberCount ?? 0
        )
        isInviting = true
    }

    // MARK: - Overflow -

    private var overflowMenu: some View {
        Menu {
            Button {
                isShowingE2ee = true
            } label: {
                Label("Encryption", systemImage: "lock.open")
            }
            // Mute is a member's: someone reading a gated preview has no viewer state to mute.
            if isMember {
                Button {
                    isPickingMuteDuration = true
                } label: {
                    Label("Mute Notifications", systemImage: "bell.slash")
                }
            }
            Divider()
            // Outside the membership check: a group you have already left is the one you are most
            // likely to report.
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
        .accessibilityIdentifier("chat-profile-overflow")
    }

    // MARK: - Leave -

    private var leaveButton: some View {
        Button {
            dialogItem = leaveDialog()
        } label: {
            ButtonStateLabel("Leave Chat", state: isLeaving ? .loading : .normal)
        }
        .buttonStyle(.subtle)
        .disabled(isLeaving)
        .accessibilityIdentifier("chat-profile-leave")
    }

    private func leaveDialog() -> DialogItem {
        .info(
            title: "Leave \(title)?",
            subtitle: "You won't receive messages from this group any more. You can join again with an invite link"
        ) {
            DialogAction.standard("Leave Chat") {
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
            session.dialogItem = .error(
                title: "Something Went Wrong",
                subtitle: "We were unable to leave this group. Please try again"
            )
            ErrorReporting.captureError(error, reason: "Failed to leave group")
        }
    }
}

/// Where a group's profile was opened from.
nonisolated enum ChatProfileOrigin: Hashable {
    /// The group chat's own navigation title, so the chat sits underneath.
    case chat
    /// A favorite group on the You tab or someone's profile, with no chat underneath.
    case featuredGroup
    /// A group invite card in another chat's transcript, so the chat underneath is not this one.
    case link
}
