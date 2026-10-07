//
//  UserProfileScreen.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import UIKit
import FlipcashCore
import FlipcashUI

/// Another user's Flipcash profile: the shared header and stats, a ⋯ menu carrying the actions the
/// viewer has over the person, and one pinned button that starts, opens, or restores the chat.
///
/// Reached from a tip DM's title, from a face in a group transcript, and from a person link. All land
/// here because all are the same question — who is this — so Block works on the person either way.
struct UserProfileScreen: View {
    let userID: UserID
    let origin: UserProfileOrigin

    @Environment(SessionContainer.self) private var sessionContainer
    @Environment(BlocklistController.self) private var blocklistController
    @Environment(AppRouter.self) private var router

    var body: some View {
        let seed = sessionContainer.conversationController.counterpartSeed(forUserID: userID)
        UserProfileContent(
            origin: origin,
            model: UserProfileViewModel(
                userID: userID,
                flipClient: sessionContainer.flipClient,
                owner: sessionContainer.session.ownerKeyPair,
                blocklistController: blocklistController,
                router: router,
                blockReturnsToOpener: origin.blockReturnsToOpener,
                arrivesFetched: origin.arrivesFetched,
                session: sessionContainer.session,
                profileAvatars: sessionContainer.profileAvatars,
                seed: seed
            )
        )
    }
}

private struct UserProfileContent: View {

    @Environment(AppRouter.self) private var router
    @Environment(SessionContainer.self) private var sessionContainer
    @Environment(RatesController.self) private var ratesController
    @Environment(ConversationController.self) private var conversationController
    @Environment(BlocklistController.self) private var blocklistController
    @Environment(ToastController.self) private var toasts

    let origin: UserProfileOrigin

    @State private var isShowingShare = false
    @State private var model: UserProfileViewModel
    @State private var dialogItem: DialogItem?
    @State private var isPickingMuteDuration = false
    @State private var isReporting = false
    @State private var startChattingRequest: StartChattingRequest?
    @State private var postPayment = PostPaymentChat()
    /// Where this screen sits in its stack, recorded when it first appears.
    @State private var position: AppRouter.StackPosition?

    init(origin: UserProfileOrigin, model: UserProfileViewModel) {
        self.origin = origin
        _model = State(initialValue: model)
    }

    /// What the start-chatting sheet is opened for, snapshotted at the tap.
    private struct StartChattingRequest: Identifiable {
        let target: SendTarget
        let fee: FiatAmount

        var id: SendTarget { target }
    }

    // MARK: - Derived state -

    private var session: Session { sessionContainer.session }

    private var isSelf: Bool { model.userID == session.userID }

    private var isBlocked: Bool { blocklistController.isBlocked(model.userID) }

    private var dmID: ConversationID? { conversationController.tipDMID(withUserID: model.userID) }

    private var fee: FiatAmount? {
        let currency = ratesController.balanceCurrency
        return StartChattingFee.amount(
            recipientFee: model.minDmChatInitFee,
            presets: session.userFlags?.tipPresets(for: currency),
            currency: currency,
            rates: ratesController.cachedRates
        )
    }

    private var pinnedAction: ProfilePinnedAction {
        ProfilePinnedAction.resolve(isSelf: isSelf, isBlocked: isBlocked, dmID: dmID, fee: fee)
    }

    private var menuItems: [ProfileMenuItem] {
        guard !isSelf else { return [] }
        return ProfileMenuItems.resolve(isBlocked: isBlocked, hasDM: dmID != nil)
    }

    /// Whether this profile is the visible top of its stack, with its tab or sheet active.
    private var isScreenInFront: Bool {
        guard let position else { return false }
        return router.isTopmost(position)
    }

    private var sendTarget: SendTarget {
        .tip(TipRecipient(userID: model.userID, displayName: model.displayName, username: model.username, origin: .tipcard))
    }

    // MARK: - Body -

    var body: some View {
        Background(color: .backgroundMain) {
            ScrollView {
                VStack(spacing: 0) {
                    ProfileHeaderView(
                        cover: .user(model.userID, picture: model.coverPicture),
                        title: model.displayName,
                        subtitle: model.handle,
                        bodyText: model.bio,
                        avatar: {
                            ProfileHeaderAvatar(
                                id: model.userID.uuidString,
                                displayName: model.displayName,
                                imageData: model.imageData,
                                blurhash: model.blurhash
                            )
                        },
                        bannerControls: { EmptyView() },
                        coverAccessory: { statusBadges },
                        rowActions: {
                            shareButton
                        },
                        underSubtitle: { EmptyView() }
                    )

                    ProfileStatsCard(minimumToChat: fee, joinedAt: model.joinedAt)
                        .padding(.top, 20)

                    FeaturedGroupsSection(groups: model.featuredGroups) {
                        router.push(.chatProfile($0))
                    }
                    .padding(.top, 20)
                }
                .padding(.bottom, 24)
            }
            .profilePinnedBackdropClearance()
            // The banner runs under the status bar.
            .ignoresSafeArea(edges: .top)
            // The blur only belongs once the banner has scrolled up under the bar.
            .hidesTopScrollEdge(untilOffset: ProfileCoverBanner<EmptyView>.height / 2)
        }
        // On iOS 26 the pinned button joins the bottom scroll edge effect, so content fades under it.
        .scrollEdgeBar(.bottom) {
            pinnedButton
                .profilePinnedBackdrop()
                // Toasts rise above the button rather than covering it.
                .toastClearance(toasts)
        }
        // The system bar carries back and the overflow menu, and the soft edge the banner scrolls under.
        .toolbar {
            if !menuItems.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    overflowMenu
                }
            }
        }
        .fullScreenCover(isPresented: $isShowingShare) {
            ShareToChatsSheet(
                subject: .user(url: model.shareURL, displayName: model.name, directChatID: dmID),
                isPresented: $isShowingShare
            ) { chatID in
                router.push(.tipConversation(chatID))
            }
        }
        .dialog(item: $dialogItem)
        .sheet(isPresented: $isPickingMuteDuration) {
            if let dmID {
                MuteChatSheet(conversationID: dmID, isPresented: $isPickingMuteDuration)
            }
        }
        .fullScreenCover(isPresented: $isReporting) {
            NavigationStack {
                ReportFlowScreen(target: .user(model.userID))
            }
        }
        .sheet(item: $startChattingRequest, onDismiss: {
            if let id = postPayment.sheetDismissed(dmID: dmID, isScreenInFront: isScreenInFront) {
                router.push(.tipConversation(id))
            }
        }) { request in
            StartChattingSheet(target: request.target, fee: request.fee) {
                postPayment.paymentSucceeded()
            }
        }
        .onChange(of: dmID) { _, id in
            if let id = postPayment.dmArrived(id, isScreenInFront: isScreenInFront) {
                router.push(.tipConversation(id))
            }
        }
        // The record normally lands within a moment; past this the profile stays put and its
        // button has already flipped to Open Chat.
        .task(id: postPayment.isAwaitingChat) {
            guard postPayment.isAwaitingChat else { return }
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            postPayment.gaveUp()
        }
        .onAppear {
            if position == nil { position = router.positionOfTopmost() }
        }
        .task {
            await model.loadProfile()
            await model.loadFeaturedGroups()
        }
    }

    // MARK: - Status badges -

    /// Blocked and muted are separate settings, so each gets its own badge. They sit on the cover,
    /// whose height is fixed, so one coming or going never moves the bio below.
    private var statusBadges: some View {
        HStack(spacing: 8) {
            if isBlocked {
                ProfileStatusChip(systemImage: "nosign", text: "Blocked", tint: .warning, fill: .warningSecondary)
                    // The mute chip gives up width first, falling back to plain "Muted".
                    .fixedSize()
                    .accessibilityIdentifier("profile-blocked-badge")
            }
            if let dmID {
                ChatMuteStatusLabel(conversationID: dmID, reservesSpace: false)
            }
        }
    }

    // MARK: - Banner controls -

    private var overflowMenu: some View {
        Menu {
            ForEach(Array(menuItems.enumerated()), id: \.element.title) { index, item in
                // A divider wherever the red entries start or stop, so they sit apart.
                if index > 0, menuItems[index - 1].isDestructive != item.isDestructive {
                    Divider()
                }
                Button(role: item.isDestructive ? .destructive : nil) {
                    perform(item)
                } label: {
                    Label(item.title, systemImage: item.systemImage)
                }
                // Menu icons follow the app's white tint while the title follows the role, so a
                // destructive entry's icon is tinted red to match its title.
                .tint(item.isDestructive ? .red : nil)
            }
        } label: {
            Image.system(.ellipsis)
                .renderingMode(.template)
        }
        .accessibilityLabel("More")
        .accessibilityIdentifier("profile-overflow")
    }

    private var shareButton: some View {
        ProfileActionCircle(image: Image.asset(.shareOS)) {
            isShowingShare = true
        }
        .accessibilityLabel("Share profile")
        .accessibilityIdentifier("profile-share")
    }

    private func perform(_ item: ProfileMenuItem) {
        switch item {
        case .mute:
            isPickingMuteDuration = true
        case .report:
            isReporting = true
        case .block:
            dialogItem = blockDialog()
        case .unblock:
            Task { await model.unblock() }
        }
    }

    // MARK: - Pinned action -

    @ViewBuilder
    private var pinnedButton: some View {
        if let title = pinnedAction.title {
            VStack(spacing: 8) {
                if showsE2eeFooter {
                    E2eeFooter(kind: .dm)
                }

                CodeButton(style: .filled, title: title, action: tapPinned)
                    .accessibilityIdentifier("profile-pinned-action")
            }
            .padding(.horizontal, ProfileHeaderMetrics.inset)
            .padding(.top, 12)
            .padding(.bottom, 8)
        } else if showsE2eeFooter {
            E2eeFooter(kind: .dm)
        }
    }

    private func tapPinned() {
        switch pinnedAction {
        case .none:
            break
        case .unblock:
            Task { await model.unblock() }
        case .openChat(let id):
            if origin.returnsToExistingDM {
                router.popTopmost()
            } else {
                router.push(.tipConversation(id))
            }
        case .startChattingUnpriced:
            guard passesGiveCashGate() else { return }
            router.presentSendAmount(sendTarget)
        case .startChatting(let fee):
            guard passesGiveCashGate() else { return }
            startChattingRequest = StartChattingRequest(target: sendTarget, fee: fee)
        }
    }

    /// Shows the blocking dialog and returns false when the viewer can't pay yet.
    private func passesGiveCashGate() -> Bool {
        let rate = ratesController.rateForBalanceCurrency()
        guard let dialog = giveCashGate(session: session, rate: rate).blockingDialog(router: router, addMoneySource: .chat, context: .sendTips) else {
            return true
        }
        session.dialogItem = dialog
        return false
    }

    /// Only a DM that will actually be encrypted claims to be — see ``E2eePolicy``.
    private var showsE2eeFooter: Bool {
        guard let dmID, let conversation = conversationController.conversation(withID: dmID) else {
            return false
        }
        return E2eePolicy.shouldEncrypt(conversation)
    }

    private func blockDialog() -> DialogItem {
        .alert(
            title: "Block \(model.displayName)?",
            subtitle: "You won't see messages from them, but you will still receive cash they send you. Flipcash won't tell them you blocked them"
        ) {
            DialogAction.destructive("Block") {
                Task { await model.block() }
            }
            DialogAction.cancel()
        }
    }
}

/// Where a person's profile was opened from.
nonisolated enum UserProfileOrigin: Hashable {
    /// The title or card of the DM with this person.
    case directMessage
    /// Their face in a group transcript.
    case groupMember
    /// Their `@handle` or person link card tapped in a message, in a chat that is not a DM with them.
    case mention
    /// A `flipcash.com/<handle>` or `flipcash.com/<userId>` link opened into the app.
    case deeplink
    /// Their code scanned with the camera, or their profile QR link opened, after the card shows.
    case scan
    /// A username search from New Chat, whether or not a DM exists.
    case usernameLookup
    /// A transaction's details, with no DM yet.
    case transaction

    /// Whether Open Chat returns to the DM the profile was opened from rather than pushing a
    /// second copy of it.
    var returnsToExistingDM: Bool {
        switch self {
        case .directMessage:
            return true
        case .groupMember, .mention, .deeplink, .scan, .usernameLookup, .transaction:
            return false
        }
    }

    /// Whether the profile was fetched and cached just before the screen opened, so the screen
    /// reads the cache instead of fetching again. A link, a scan, and a username search all look the
    /// person up before they navigate.
    var arrivesFetched: Bool {
        switch self {
        case .deeplink, .scan, .usernameLookup:
            return true
        case .directMessage, .groupMember, .mention, .transaction:
            return false
        }
    }

    /// Whether blocking closes just the profile rather than resetting its stack. From a chat the
    /// stack beneath can hold the blocked person's DM, so it resets; a link opened the profile over
    /// whatever the user was on, and that is where blocking returns them, as does a transaction's
    /// details. A scan or a username search opens the profile as the Chats tab's only entry, so a
    /// reset lands on the chat list either way.
    var blockReturnsToOpener: Bool {
        switch self {
        case .deeplink, .transaction:
            return true
        case .directMessage, .groupMember, .mention, .scan, .usernameLookup:
            return false
        }
    }
}

@MainActor
@Observable
final class UserProfileViewModel {
    let userID: UserID

    /// The counterpart's own name, or `nil` for an account that hasn't set one.
    private(set) var name: String?

    private(set) var username: Username?
    private(set) var blurhash: String?
    private(set) var bio: String?
    private(set) var coverPicture: ProfilePicture?
    private(set) var customization: TipCardCustomization?
    private(set) var joinedAt: Date?
    private(set) var minDmChatInitFee: FiatAmount?
    /// The public groups this person features, in their order.
    private(set) var featuredGroups: [Conversation] = []

    /// What to call this person: their name when they have one, their handle
    /// when they don't. A handle is public and stable, so it beats the generic
    /// fallback, which is left for an account carrying neither.
    var displayName: String {
        name ?? username?.handle ?? ConversationController.fallbackCounterpartName
    }

    /// The handle line under the title. Left out when the title is already the
    /// handle, so a name-less account doesn't read it twice.
    var handle: String? {
        guard name != nil else { return nil }
        return username?.handle
    }

    @ObservationIgnored private let flipClient: FlipClient
    @ObservationIgnored private let owner: KeyPair
    @ObservationIgnored private let blocklistController: BlocklistController
    @ObservationIgnored private let router: AppRouter
    @ObservationIgnored private let blockReturnsToOpener: Bool
    @ObservationIgnored private let arrivesFetched: Bool
    @ObservationIgnored private let session: Session
    @ObservationIgnored private let profileAvatars: ProfileAvatarStore
    @ObservationIgnored private let seedImageData: Data?

    /// The avatar bytes to draw, read through to the store on every access rather than captured at
    /// init: the store fills in after a round trip, and a counterpart who changes their picture
    /// replaces what it holds. A screen holding a copy from init shows the blurhash until it is
    /// dismissed and reopened.
    var imageData: Data? {
        profileAvatars.data(for: userID) ?? seedImageData
    }

    init(userID: UserID, flipClient: FlipClient, owner: KeyPair, blocklistController: BlocklistController, router: AppRouter, blockReturnsToOpener: Bool, arrivesFetched: Bool, session: Session, profileAvatars: ProfileAvatarStore, seed: CounterpartSeed) {
        self.userID = userID
        self.flipClient = flipClient
        self.owner = owner
        self.blocklistController = blocklistController
        self.router = router
        self.blockReturnsToOpener = blockReturnsToOpener
        self.arrivesFetched = arrivesFetched
        self.session = session
        self.profileAvatars = profileAvatars
        self.name = seed.name
        self.username = seed.username
        self.seedImageData = seed.imageData
        self.blurhash = seed.blurhash
    }

    /// Fetches the profile for a fresh name, join date, and avatar. Seeds from
    /// the shared profile cache first for instant display, then caches the
    /// freshly fetched profile. A profile that arrived fetched stops at the cache.
    func loadProfile() async {
        if let cached = session.cachedUserProfile(for: userID) {
            apply(cached)
            await profileAvatars.load(userID: userID, picture: cached.profilePicture)
            if arrivesFetched { return }
        }
        guard let profile = try? await flipClient.fetchProfile(userID: userID, owner: owner) else { return }
        session.cacheUserProfile(profile, for: userID)
        apply(profile)
        await profileAvatars.load(userID: userID, picture: profile.profilePicture)
    }

    /// Reads the groups this person features, once their handle is known. A failure leaves the
    /// section hidden; the rest of the profile stands.
    func loadFeaturedGroups() async {
        guard let username else { return }
        do {
            featuredGroups = try await flipClient.getFeaturedGroups(owner: owner, username: username)
        } catch {
            guard !Task.isCancelled else { return }
            ErrorReporting.captureError(error, reason: "Failed to load featured groups")
        }
    }

    private func apply(_ profile: Profile) {
        if let name = profile.displayName, !name.isEmpty { self.name = name }
        if let username = profile.username { self.username = username }
        if blurhash == nil { blurhash = profile.profilePicture?.thumbnailBlurhash }
        bio = profile.bio
        coverPicture = profile.coverPicture
        customization = profile.tipCardCustomization
        if let joinedAt = profile.joinedAt { self.joinedAt = joinedAt }
        minDmChatInitFee = profile.minDmChatInitFee
    }

    /// This person's public link, the one their own You tab shares.
    var shareURL: URL { .tipcard(for: userID, username: username) }

    /// Lifts the block; the badge and pinned button follow the blocklist. A failure says so.
    func unblock() async {
        do {
            try await blocklistController.unblock(userID: userID)
        } catch {
            session.dialogItem = .error(title: "Something Went Wrong", subtitle: "We were unable to unblock the user. Please try again")
            ErrorReporting.captureError(error, reason: "Failed to unblock user")
        }
    }

    /// Blocks the user and closes the profile — see ``UserProfileOrigin/blockReturnsToOpener``. The
    /// blocklist reconcile hides the conversation.
    func block() async {
        do {
            try await blocklistController.block(userID: userID, displayName: displayName, avatarBlurhash: blurhash)
            if blockReturnsToOpener {
                router.popTopmost()
            } else {
                router.popToRoot()
            }
        } catch {
            session.dialogItem = .error(title: "Something Went Wrong", subtitle: "We were unable to block the user. Please try again")
            ErrorReporting.captureError(error, reason: "Failed to block user")
        }
    }
}
