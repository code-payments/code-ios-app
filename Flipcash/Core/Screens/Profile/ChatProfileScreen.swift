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

/// A group chat's own profile (node 10913:358): the shared profile header with the group's cover,
/// picture and description, who is chatting, what it takes to join and to chat, and one pinned
/// button that joins, buys in, or opens the chat.
///
/// Reached by tapping the chat's head card or its navigation title, the way a DM's title opens the
/// counterpart's profile. The actions a member has over the group sit in the ⋯ menu, and Leave Chat
/// sits under the pinned button.
struct ChatProfileScreen: View {

    let conversationID: ConversationID

    @Environment(ConversationController.self) private var conversationController
    @Environment(SessionContainer.self) private var sessionContainer
    @Environment(RatesController.self) private var ratesController
    @Environment(AppRouter.self) private var router
    @Environment(ToastController.self) private var toasts

    @State private var isInviting = false
    @State private var isShowingShare = false
    @State private var shareChoice: ProfileShareChoice?
    @State private var isPickingMuteDuration = false
    @State private var isReporting = false
    @State private var isShowingE2ee = false
    @State private var isJoining = false
    @State private var isLeaving = false
    @State private var dialogItem: DialogItem?
    @State private var chatters: [SampledChatter] = []
    @State private var mintNames: [PublicKey: String] = [:]

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

    // MARK: - Gate -

    /// Recomputed on each observation tick, so a balance that crosses a minimum or a rate that
    /// lands moves the button without a reopen.
    private var gate: ConversationGate {
        guard let conversation else { return .open }
        return conversationGate(
            session: session,
            rules: conversation.rules,
            creator: conversation.creator,
            rates: ratesController.cachedRates
        )
    }

    private var cta: GroupProfileCTA {
        guard conversation != nil else { return .none }
        return GroupProfileCTA.resolve(gate: gate, isMember: isMember)
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

    /// "$10 of NYC", or the bare amount for a dollar-token or any-holding rule: the dollar amount
    /// already states it, the way the gate panel words it.
    private func holding(_ amount: FiatAmount, mint: PublicKey?) -> String {
        let formatted = amount.formattedDroppingZeroFraction()
        guard let mint, mint != .usdf, let name = mintNames[mint] else { return formatted }
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
                        rowActions: {
                            if isMember {
                                ChatMuteStatusLabel(conversationID: conversationID, reservesSpace: false)
                            }
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

                    if let requirements {
                        balanceRequirements(requirements)
                            .padding(.top, 24)
                    }
                }
                .padding(.bottom, 24)
            }
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
        .sheet(isPresented: $isShowingShare, onDismiss: handleShareChoice) {
            ProfileShareSheet(
                title: "Share Group",
                subtitle: title,
                shareRow: ("Share on Flipcash", Image(systemName: "paperplane")),
                offersCard: false
            ) { shareChoice = $0 }
        }
        .sheet(isPresented: $isInviting) {
            GroupInviteSheet(conversationID: conversationID, isPresented: $isInviting) { chatID in
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
            await sessionContainer.profileAvatars.load(.chat(conversationID), picture: conversation?.picture)
        }
        // Waits for the conversation to land before asking: a private group's sample is denied.
        .task(id: conversation.map { $0.isPrivate } ) {
            guard let conversation, !conversation.isPrivate else { return }
            await loadChatters()
        }
        // Name the requirements in the token they ask for. The mint may be one the user holds
        // nothing of, so the local store can miss and the fetch is what fills it.
        .task(id: namedMints) {
            var names: [PublicKey: String] = [:]
            for mint in namedMints {
                if let stored = session.storedMintMetadata(for: mint) {
                    names[mint] = stored.name
                } else if let fetched = try? await session.fetchMintMetadata(mint: mint).name {
                    names[mint] = fetched
                }
            }
            mintNames = names
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

            VStack(spacing: 0) {
                requirementRow("Join", requirements.join, identifier: "group-profile-join-minimum")
                Color.rowSeparator
                    .frame(height: 1)
                requirementRow("Chat", requirements.chat, identifier: "group-profile-chat-minimum")
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

    private func requirementRow(_ label: String, _ requirement: MinimumBalanceRequirement?, identifier: String) -> some View {
        HStack {
            Text(label)
                .font(.appTextSmall)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Text(requirement.map { holding($0.amount, mint: $0.mints.first) } ?? "None")
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
        let cta = cta
        if cta != .none || isMember {
            VStack(spacing: 8) {
                if let line = requirementLine(cta) {
                    Text(line)
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                        .accessibilityIdentifier("group-profile-requirement-line")
                }
                if let ctaTitle = ctaTitle(cta) {
                    Button { tap(cta) } label: {
                        ButtonStateLabel(ctaTitle, state: isJoining ? .loading : .normal)
                    }
                    .buttonStyle(.filled)
                    .disabled(isJoining)
                    .accessibilityIdentifier("group-profile-cta")
                }
                if isMember {
                    Button {
                        dialogItem = leaveDialog()
                    } label: {
                        ButtonStateLabel("Leave Chat", state: isLeaving ? .loading : .normal)
                    }
                    .buttonStyle(.subtle)
                    .disabled(isLeaving)
                    .accessibilityIdentifier("chat-profile-leave")
                }
            }
            .padding(.horizontal, ProfileHeaderMetrics.inset)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
    }

    /// The full requirement over a Buy button, which itself names only the shortfall.
    private func requirementLine(_ cta: GroupProfileCTA) -> String? {
        switch cta {
        case .buyToJoin(let amount, let mint):
            return "\(holding(amount, mint: mint)) Required to Join"
        case .buyToChat(let amount, let mint):
            return "\(holding(amount, mint: mint)) Required to Chat"
        case .none, .join, .openChat:
            return nil
        }
    }

    private func ctaTitle(_ cta: GroupProfileCTA) -> String? {
        switch cta {
        case .none:
            return nil
        case .join:
            return "Join"
        case .openChat:
            return "Open Chat"
        case .buyToJoin(let amount, let mint):
            return "Buy \(holding(shortfall(of: amount, mint: mint), mint: mint)) to Join"
        case .buyToChat(let amount, let mint):
            return "Buy \(holding(shortfall(of: amount, mint: mint), mint: mint)) to Chat"
        }
    }

    /// The amount still to buy, or the whole requirement when no rate can restate the gap.
    private func shortfall(of amount: FiatAmount, mint: PublicKey?) -> FiatAmount {
        balanceShortfall(of: amount, mint: mint, holdings: session, rates: ratesController.cachedRates) ?? amount
    }

    private func tap(_ cta: GroupProfileCTA) {
        switch cta {
        case .none:
            break
        case .join:
            join()
        case .openChat:
            // The only way here is the chat's own head card or title, so the chat is underneath.
            router.popTopmost()
        case .buyToJoin(_, let mint), .buyToChat(_, let mint):
            buy(mint)
        }
    }

    /// Buys the mint the requirement names, or opens add-cash when there is no one token to buy: a
    /// rule spanning every holding, or a dollar-token one, which adding cash satisfies directly.
    private func buy(_ mint: PublicKey?) {
        guard let mint, mint != .usdf else {
            Analytics.groupGateFundingTapped(method: .addCash, gateMint: mint)
            router.presentAddMoney(.general, source: .chat)
            return
        }
        Analytics.groupGateFundingTapped(method: .buyToken, gateMint: mint)
        router.push(.buyCurrency(mint))
    }

    /// Joins, then returns to the chat underneath, which loads its transcript once the gate stops
    /// obscuring it. A refused join leaves the profile as it was, so the failure is said out loud.
    private func join() {
        guard !isJoining else { return }
        isJoining = true
        // Read before the join, which seats a roster that already counts the viewer.
        let memberCount = conversation?.rosterSummary.memberCount ?? 0
        let gated = conversation?.rules?.listener.isEmpty == false
        Task {
            defer { isJoining = false }
            do {
                try await conversationController.join(conversationID: conversationID)
                Analytics.groupJoined(error: nil, memberCount: memberCount, gated: gated)
                router.popTopmost()
            } catch {
                Analytics.groupJoined(error: error, memberCount: memberCount, gated: gated)
                let subtitle: String
                if case ErrorJoinChat.rulesNotSatisfied = error {
                    subtitle = "You don't meet this chat's requirements yet."
                } else {
                    subtitle = "Something went wrong. Please try again."
                }
                session.dialogItem = .alert(title: "Couldn't Join Chat", subtitle: subtitle) {
                    DialogAction.okay(kind: .standard)
                }
            }
        }
    }

    // MARK: - Share -

    private var shareButton: some View {
        ProfileActionCircle(image: Image.asset(.shareOS)) {
            isShowingShare = true
        }
        .accessibilityLabel("Share group")
        .accessibilityIdentifier("chat-profile-share")
    }

    /// Runs once the share sheet is gone, so a following sheet doesn't present over it.
    private func handleShareChoice() {
        defer { shareChoice = nil }
        switch shareChoice {
        case .share:
            openInvite()
        case .copyLink:
            UIPasteboard.general.string = URL.groupChatInvite(for: conversationID).absoluteString
            toasts.show(.init("Copied", systemImage: "checkmark.circle.fill", duration: .seconds(2)))
        case .showCard, nil:
            break
        }
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
            // Invite and Mute are a member's: someone reading a gated preview has no link to hand
            // out and no viewer state to mute.
            if isMember {
                Button {
                    openInvite()
                } label: {
                    Label("Invite People", systemImage: "person.badge.plus")
                }
                Button {
                    isPickingMuteDuration = true
                } label: {
                    Label("Mute Notifications", systemImage: "bell.slash")
                }
            }
            // Outside the membership check: a group you have already left is the one you are most
            // likely to report.
            Button {
                isReporting = true
            } label: {
                Label("Report", systemImage: "exclamationmark.bubble")
            }
            Button {
                isShowingE2ee = true
            } label: {
                Label("Encryption", systemImage: "lock")
            }
        } label: {
            Image.system(.ellipsis)
                .renderingMode(.template)
        }
        .accessibilityLabel("More")
        .accessibilityIdentifier("chat-profile-overflow")
    }

    // MARK: - Leave -

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
