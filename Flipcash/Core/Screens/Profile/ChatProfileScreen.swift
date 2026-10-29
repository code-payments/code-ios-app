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

/// A group chat's own profile: a public group's cover-colored page with its requirements and
/// pulse, or a private group's shared profile header with its members, and one pinned button that
/// opens the chat.
///
/// Reached by tapping the chat's head card or its navigation title, the way a DM's title opens the
/// counterpart's profile. The actions a member has over the group sit in the ⋯ menu. Opened from
/// the chat, there is no pinned button, since the chat is one back away, and Leave Chat ends the
/// scroll; otherwise a private group's Leave Chat sits under the pinned button and a public
/// group's ends the scroll.
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
    @State private var isRequesting = false
    @State private var hostName: String?
    @State private var dialogItem: DialogItem?
    @State private var chatters: [SampledChatter] = []
    @State private var senders: [UserID] = []
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

    /// A private group's roster as portraits, the host first; empty until the roster is read.
    private var rosterPortraits: [GroupPortrait] {
        let creator = conversation?.creator
        return sessionContainer.groupRosters.members(for: conversationID, creator: creator)
            .compactMap { GroupPortrait($0, creator: creator) }
    }

    /// The roster when it can be read, else the members this device knows of from the chat.
    private var memberPortraits: [GroupPortrait] {
        let roster = rosterPortraits
        guard roster.isEmpty else { return roster }
        return GroupPortrait.known(
            creator: conversation?.creator,
            selfID: conversationController.selfUserID,
            senders: senders,
            members: sessionContainer.knownAuthors.snapshot.membersByUserID
        )
    }

    /// Whether the viewer sees the requester's layout: a private group they don't belong to, whose
    /// chat they can't open without the key the host hands over on approval.
    private var isRequester: Bool {
        isPrivate && !isMember
    }

    /// When the viewer asked to join, while that request is outstanding.
    private var requestedAt: Date? {
        sessionContainer.lobbyRequests.requestedAt(conversationID)
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
        screen
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
        .tray(isPresented: $isPickingMuteDuration) {
            MuteChatSheet(conversationID: conversationID, isPresented: $isPickingMuteDuration)
        }
        .tray(isPresented: $isShowingE2ee) {
            E2eeLearnMoreSheet(kind: isPrivate ? .privateGroup : .group, isPresented: $isShowingE2ee)
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
        // No push says a request was decided, so every visit asks. Keyed on membership so an
        // admission that lands while the profile is open stops the asking.
        .task(id: isRequester) {
            guard isRequester else { return }
            if let fresh = await conversationController.refreshRequestedGroup(conversationID) {
                sessionContainer.lobbyRequests.reconcile(with: fresh)
            }
        }
        .task(id: requestedAt != nil ? conversation?.creator : nil) {
            guard requestedAt != nil, let creator = conversation?.creator else { return }
            hostName = try? await sessionContainer.flipClient.fetchProfile(
                userID: creator,
                owner: session.ownerKeyPair
            ).displayName
        }
        // Waits for the conversation to land before asking: a private group's sample is denied.
        .task(id: conversation.map { $0.isPrivate && $0.creator == conversationController.selfUserID }) {
            guard let conversation, conversation.isPrivate, conversation.creator == conversationController.selfUserID else { return }
            await sessionContainer.hostedLobbies.refresh(conversationID)
        }
        // A private group's members read its roster in place of the denied sample.
        .task(id: isPrivate && isMember) {
            guard isPrivate, isMember else { return }
            await sessionContainer.groupRosters.refresh(conversationID)
        }
        // GetRoster is off server-side and SampleChatters refuses private groups, so the grid falls
        // back to the people this device has seen post.
        .task(id: isPrivate && isMember) {
            guard isPrivate, isMember else { return }
            senders = conversationController.senderIDs(in: conversationID)
            let creator = conversation?.creator.map { [$0] } ?? []
            await sessionContainer.knownAuthors.resolve(creator + [conversationController.selfUserID] + senders)
        }
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

    /// A public group gets its cover-colored page; a private group keeps the shared profile layout,
    /// as does a group not yet loaded, so a private one never paints as public.
    @ViewBuilder
    private var screen: some View {
        if isPrivate || conversation == nil {
            privateScreen
        } else {
            publicScreen
        }
    }

    /// The shared profile layout, drawn for a private group.
    private var privateScreen: some View {
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

                    if isPrivate {
                        privateSummary
                            .padding(.top, 16)
                    }

                    if joinRequestCount > 0 {
                        joinRequestsCard
                            .padding(.top, 24)
                    }

                    if isPrivate, isMember, !memberPortraits.isEmpty {
                        GroupChattingGrid(
                            title: "Members",
                            portraits: Array(memberPortraits.prefix(GroupChattingGrid.memberLimit)),
                            count: conversation?.rosterSummary.memberCount,
                            onCount: rosterPortraits.isEmpty ? nil : { router.push(.groupMembers(conversationID)) }
                        ) { userID in
                            router.push(.userProfile(userID, origin: .groupMember))
                        }
                        .padding(.top, 24)
                    }

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

                    if endsWithLeaveButton {
                        // Holds Leave Chat at the bottom of the screen when the content is short.
                        Spacer(minLength: 24)
                        leaveButton
                            .padding(.horizontal, ProfileHeaderMetrics.inset)
                    }
                }
                .frame(minHeight: max(scrollFit.visibleHeight - contentBottomPadding, 0), alignment: .top)
                .padding(.bottom, contentBottomPadding)
            }
            .profilePinnedBackdropClearance(isActive: origin != .chat)
            .profileScrollFit($scrollFit)
            .scrollIndicators(.hidden)
            // The banner runs under the status bar.
            .ignoresSafeArea(edges: .top)
            // The blur only belongs once the banner has scrolled up under the bar.
            .hidesTopScrollEdge(untilOffset: ProfileCoverBanner<EmptyView>.height / 2)
            // Leave Chat ends the scroll under the empty bar, so the edge blur lifts at the end.
            .hidesBottomScrollEdge(origin == .chat && !scrollFit.fadesBottom)
        }
        .scrollEdgeBar(.bottom) {
            pinnedActions
                .toastClearance(toasts)
        }
    }

    // MARK: - Public -

    /// A public group's profile: the cover melting into a page of its own color. The colors come
    /// from the best image there is (see ``PublicGroupBleedSource``).
    private var publicScreen: some View {
        let source = PublicGroupBleedSource(
            conversation: conversation,
            coverData: sessionContainer.profileAvatars.data(for: .groupCover(conversationID)),
            avatarData: sessionContainer.profileAvatars.data(for: .chat(conversationID))
        )
        return PublicGroupProfileView(
            content: publicContent(cover: source?.kind == .cover ? source?.image : nil),
            hasPinned: showsPublicCTA,
            portraitData: { sessionContainer.profileAvatars.data(for: $0) },
            loadPortrait: { portrait in
                await sessionContainer.profileAvatars.load(userID: portrait.userID, picture: portrait.picture)
            },
            onSelectPerson: { userID in
                router.push(.userProfile(userID, origin: .groupMember))
            },
            onToken: { token in
                Analytics.tokenInfoOpened(from: .openedFromChat, mint: token.mint)
                router.push(.currencyInfo(token.mint))
            },
            accessory: {
                if isMember {
                    ChatMuteStatusLabel(conversationID: conversationID, reservesSpace: false)
                }
            },
            actions: {
                if canEdit {
                    Button("Edit Group") {
                        router.push(.editGroup(conversationID))
                    }
                    .buttonStyle(PublicGroupOutlineButtonStyle())
                    .accessibilityIdentifier("chat-profile-edit")
                }
                Button("Share") {
                    openInvite()
                }
                .buttonStyle(PublicGroupOutlineButtonStyle())
                .accessibilityLabel("Share group")
                .accessibilityInputLabels(["Share"])
                .accessibilityIdentifier("chat-profile-share")
            },
            hasFooter: isMember,
            footer: {
                if isMember {
                    publicLeaveButton
                }
            },
            pinned: {
                publicPinnedActions
                    .toastClearance(toasts)
            }
        )
        .bleedPalette(key: source?.key, image: source?.image, settings: PublicGroupLook.settings)
        .task(id: conversation?.coverPicture?.blobID) {
            await sessionContainer.profileAvatars.load(.groupCover(conversationID), picture: conversation?.coverPicture)
        }
    }

    /// Leave Chat as the last box of a public group's stack.
    private var publicLeaveButton: some View {
        Button {
            dialogItem = leaveDialog()
        } label: {
            ButtonStateLabel("Leave Chat", state: isLeaving ? .loading : .normal)
        }
        .buttonStyle(PublicGroupDestructiveBoxButtonStyle())
        .disabled(isLeaving)
        .accessibilityIdentifier("chat-profile-leave")
    }

    private func publicContent(cover: UIImage?) -> PublicGroupProfileContent {
        let named = requirements.flatMap { requirementsNamed ? $0 : nil }
        return PublicGroupProfileContent(
            id: conversationID.description,
            title: title,
            memberCount: conversation?.rosterSummary.memberCount,
            description: conversation?.description,
            avatarImageData: sessionContainer.profileAvatars.data(for: .chat(conversationID)),
            avatarBlurhash: conversation?.picture?.thumbnailBlurhash,
            cover: cover,
            requirements: named.map { PublicGroupRequirementTile.tiles(for: $0, metadata: mintMetadata) } ?? [],
            yourBalance: named.flatMap { yourBalance(in: $0) },
            // Held back with the requirements above it, so a late reveal doesn't push the card down.
            pulse: chatters.isEmpty || !requirementsNamed ? nil : PublicGroupPulse(chatters: chatters, now: .now),
            host: chatters.first(where: \.isCreator).map(GroupPortrait.init)
        )
    }

    /// Whether the pinned Open Chat button shows: not from the chat itself, where the chat is one
    /// back away.
    private var showsPublicCTA: Bool {
        origin != .chat && conversation != nil
    }

    @ViewBuilder
    private var publicPinnedActions: some View {
        if showsPublicCTA {
            Button("Open Chat") { showChat() }
                .buttonStyle(PublicGroupCapsuleButtonStyle())
                .accessibilityIdentifier("group-profile-cta")
                .padding(.horizontal, PublicGroupCapsuleButtonStyle.sideInset)
                .padding(.top, 12)
                .padding(.bottom, 8)
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

    // MARK: - Join Requests -

    /// Pending requests to join, shown only to this private group's host.
    private var joinRequestCount: Int {
        guard isPrivate, conversation?.creator == conversationController.selfUserID else { return 0 }
        return sessionContainer.hostedLobbies.requests(for: conversationID).count
    }

    private var joinRequestsCard: some View {
        Button {
            router.push(.joinRequests(conversationID))
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Join Requests")
                        .font(.appTextMedium)
                        .foregroundStyle(Color.textMain)
                    Text(PrivateGroupCopy.waiting(count: joinRequestCount))
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
                Text("\(joinRequestCount)")
                    .font(.appTextHeading)
                    .foregroundStyle(Color.textMain)
                    .padding(.horizontal, 6)
                    .frame(minWidth: 22, minHeight: 22)
                    .background(Color.textSecondary.opacity(0.3), in: .capsule)
                Image(systemName: "chevron.right")
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.horizontal, 16)
            .frame(height: 64)
            .background(Color.backgroundRow, in: RoundedRectangle(cornerRadius: Metrics.boxRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, ProfileHeaderMetrics.inset)
        .accessibilityIdentifier("group-profile-join-requests")
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

    /// Whether Leave Chat ends the scroll content rather than sitting in the pinned bar.
    private var endsWithLeaveButton: Bool {
        origin == .chat && isMember
    }

    /// Space under the scroll content. Leave Chat ending it draws down into the scroll view's bottom
    /// inset: a text-only button is a full button tall, so its frame already leaves room under the
    /// title. The bottom fade lifts at the end of the scroll, so it never covers the button.
    private var contentBottomPadding: CGFloat {
        endsWithLeaveButton ? -scrollFit.bottomInset : 24
    }

    // MARK: - Pinned -

    @ViewBuilder
    private var pinnedActions: some View {
        // Opened from the chat, the chat is one back away and Leave Chat ends the scroll instead;
        // the empty bar fades out content that scrolls under the home indicator.
        if origin == .chat {
            Color.clear
                .frame(height: 0)
                .profileBarlessFade(isActive: scrollFit.fadesBottom)
        } else if conversation != nil, isRequester {
            requestActions
                .padding(.horizontal, ProfileHeaderMetrics.inset)
                .padding(.top, 12)
                .padding(.bottom, requestedAt == nil ? 8 : 0)
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

    // MARK: - Private -

    private var privateSummary: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label {
                Text(PrivateGroupCopy.summary(memberCount: conversation?.rosterSummary.memberCount ?? 0))
            } icon: {
                Image.icon(.lock)
                    .iconSize(14)
            }
            .labelStyle(.titleAndIcon)
            Text("The host approves who joins")
        }
        .font(.appTextSmall)
        .foregroundStyle(Color.textSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, ProfileHeaderMetrics.inset)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("chat-profile-private-summary")
    }

    @ViewBuilder
    private var requestActions: some View {
        if let requestedAt {
            VStack(spacing: 8) {
                Text(PrivateGroupCopy.awaitingApproval(hostName: hostName))
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 8)
                TimelineView(.everyMinute) { context in
                    Button(PrivateGroupCopy.pendingTitle(requestedAt: requestedAt, now: context.date)) {}
                        .buttonStyle(.filled)
                        .disabled(true)
                        .accessibilityIdentifier("group-profile-request-pending")
                }
                Button {
                    Task { await cancelRequest() }
                } label: {
                    ButtonStateLabel("Cancel Request", state: isRequesting ? .loading : .normal)
                }
                .buttonStyle(.subtle)
                .disabled(isRequesting)
                .accessibilityIdentifier("group-profile-cancel-request")
                // Same as Leave Chat: a text-only button already leaves room under its title.
                .padding(.bottom, -12)
            }
        } else {
            Button {
                Task { await requestToJoin() }
            } label: {
                ButtonStateLabel("Request to Join", state: isRequesting ? .loading : .normal)
            }
            .buttonStyle(.filled)
            .disabled(isRequesting)
            .accessibilityIdentifier("group-profile-request")
        }
    }

    private func requestToJoin() async {
        isRequesting = true
        defer { isRequesting = false }
        do {
            switch try await sessionContainer.lobbyRequests.request(conversationID) {
            case .requested:
                break
            case .alreadyMember:
                _ = await conversationController.refreshRequestedGroup(conversationID)
            }
        } catch let error as LobbyRequests.RequestError {
            dialogItem = .info(
                title: PrivateGroupCopy.unavailableTitle(groupName: title),
                subtitle: error.explanation
            ) {
                DialogAction.okay(kind: .standard)
            }
        } catch {
            session.dialogItem = .error(
                title: "Something Went Wrong",
                subtitle: "We were unable to send your request. Please try again"
            )
            ErrorReporting.captureError(error, reason: "Failed to request to join a private group")
        }
    }

    private func cancelRequest() async {
        isRequesting = true
        defer { isRequesting = false }
        do {
            try await sessionContainer.lobbyRequests.cancel(conversationID)
        } catch {
            session.dialogItem = .error(
                title: "Something Went Wrong",
                subtitle: "We were unable to cancel your request. Please try again"
            )
            ErrorReporting.captureError(error, reason: "Failed to cancel a private group request")
        }
    }

    // MARK: - Share -

    private var shareButton: some View {
        ProfileActionCircle(image: Image.icon(.shareOs)) {
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
                Label("Encryption", systemImage: isPrivate ? "lock.fill" : "lock.open")
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
            subtitle: PrivateGroupCopy.leaveSubtitle(isPrivate: isPrivate)
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
    /// Anywhere with no chat underneath: a favorite group on the You tab or someone's profile, or
    /// a private group just created.
    case featuredGroup
    /// A group invite card in another chat's transcript, so the chat underneath is not this one.
    case link
}
