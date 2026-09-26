//
//  UserProfileScreen.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// The counterpart's Flipcash profile, carrying the actions the viewer has over the person rather
/// than over one chat: muting the DM with them, and blocking them outright.
///
/// Reached from a tip DM's title and from a face in a group transcript. Both land here because both
/// are the same question — who is this — so Block works on the person either way. The mute row
/// silences the DM with them, so it shows only when the profile was opened from that DM.
struct UserProfileScreen: View {
    let userID: UserID
    let origin: UserProfileOrigin

    @Environment(SessionContainer.self) private var sessionContainer
    @Environment(BlocklistController.self) private var blocklistController
    @Environment(AppRouter.self) private var router

    var body: some View {
        let seed = sessionContainer.conversationController.counterpartSeed(forUserID: userID)
        UserProfileContent(
            // Nil until a tip creates the chat server-side, and re-read on every pass, so a DM that
            // appears while the screen is open brings its mute row with it.
            conversationID: origin.showsMute
                ? sessionContainer.conversationController.tipDM(withUserID: userID)?.id
                : nil,
            showsChatActions: origin.showsChatActions(
                profileUserID: userID,
                selfUserID: sessionContainer.conversationController.selfUserID
            ),
            model: UserProfileViewModel(
                userID: userID,
                flipClient: sessionContainer.flipClient,
                owner: sessionContainer.session.ownerKeyPair,
                blocklistController: blocklistController,
                router: router,
                session: sessionContainer.session,
                profileAvatars: sessionContainer.profileAvatars,
                seed: seed
            )
        )
    }
}

private struct UserProfileContent: View {
    /// The DM to mute, or nil when there is no chat with this person yet or the profile wasn't
    /// opened from it.
    let conversationID: ConversationID?
    /// Whether to offer Message and Send Cash — see ``UserProfileOrigin/showsChatActions(profileUserID:selfUserID:)``.
    let showsChatActions: Bool

    @Environment(AppRouter.self) private var router
    @Environment(RatesController.self) private var ratesController

    @State private var model: UserProfileViewModel
    @State private var dialogItem: DialogItem?

    init(conversationID: ConversationID?, showsChatActions: Bool, model: UserProfileViewModel) {
        self.conversationID = conversationID
        self.showsChatActions = showsChatActions
        _model = State(initialValue: model)
    }

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 16) {
                ContactAvatarView(
                    id: model.userID.uuidString,
                    displayName: model.displayName,
                    imageData: model.imageData,
                    blurhash: model.blurhash,
                    size: 88
                )
                .padding(.top, 40)

                VStack(spacing: 0) {
                    // The handle and join date read as a block under the name, so
                    // they group tighter than the screen's other spacing (node
                    // 9443:8928).
                    VStack(spacing: 5) {
                        Text(model.displayName)
                            .font(.appDisplaySmall)
                            .foregroundStyle(.textMain)

                        if let handle = model.handle {
                            Text(handle)
                                .font(.appTextSmall)
                                .foregroundStyle(.textSecondary)
                        }

                        if let joined = model.joinedText {
                            Text(joined)
                                .font(.appTextSmall)
                                .foregroundStyle(.textSecondary)
                        }

                        if let conversationID {
                            ChatMuteStatusLabel(conversationID: conversationID)
                        }
                    }

                    if showsChatActions {
                        // Centered between the join date and the first row's text, 25pt each side;
                        // the row's own top inset supplies the lower 25.
                        HStack(spacing: 0) {
                            ProfileActionButton(title: "Message") {
                                Image(systemName: "bubble.left.fill")
                                    .font(.appTextLarge)
                            } action: {
                                router.push(.tipConversationForUser(model.userID))
                            }
                            .accessibilityIdentifier("profile-message")

                            // Hidden for now; the destination and `startSendCash` stay wired, so
                            // bringing it back is uncommenting this.
                            // ProfileActionButton(title: "Send Cash") {
                            //     // The chat's collapsed Send Cash style, so € and ¥ read the same here.
                            //     Text(ratesController.balanceCurrency.compactSymbol)
                            //         .font(.appTextXL)
                            // } action: {
                            //     router.push(.tipConversationForUserSendingCash(model.userID))
                            // }
                            // .accessibilityIdentifier("profile-send-cash")
                        }
                        .padding(.top, 25)
                    }

                    VStack(spacing: 0) {
                        // Mute, then report, then block: the reversible and routine first, then the
                        // one that asks someone else to look, then the one that ends the relationship.
                        // Same shape as a group's profile, where leaving holds the last place.
                        if let conversationID {
                            ChatMuteRow(conversationID: conversationID, insets: rowInsets)
                        }

                        ReportRow(target: .user(model.userID), insets: rowInsets)

                        Row(insets: rowInsets) {
                            Image(systemName: "nosign")
                                .frame(minWidth: 45)
                            Text("Block")
                                .foregroundStyle(.textMain)
                            Spacer()
                        } action: {
                            dialogItem = blockDialog()
                        }
                        .accessibilityIdentifier("chat-block")
                    }
                    .font(.appDisplayXS)
                    .padding(.top, showsChatActions ? 0 : 40)
                }

                Spacer()
            }
            .padding(.horizontal, 20)
        }
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
        .dialog(item: $dialogItem)
        .task { await model.loadProfile() }
    }

    private var rowInsets: EdgeInsets {
        .init(top: 25, leading: 0, bottom: 25, trailing: 0)
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

    /// Whether the profile offers Message and Send Cash: not from the DM they would lead back
    /// into, and never on the viewer's own profile.
    func showsChatActions(profileUserID: UserID, selfUserID: UserID) -> Bool {
        guard profileUserID != selfUserID else { return false }
        switch self {
        case .directMessage: return false
        case .groupMember:   return true
        }
    }

    /// Whether the profile offers muting the DM with this person: only from that DM, since from a
    /// group the row would read as muting the group.
    var showsMute: Bool {
        switch self {
        case .directMessage: return true
        case .groupMember:   return false
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
    private(set) var joinedText: String?

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

    init(userID: UserID, flipClient: FlipClient, owner: KeyPair, blocklistController: BlocklistController, router: AppRouter, session: Session, profileAvatars: ProfileAvatarStore, seed: CounterpartSeed) {
        self.userID = userID
        self.flipClient = flipClient
        self.owner = owner
        self.blocklistController = blocklistController
        self.router = router
        self.session = session
        self.profileAvatars = profileAvatars
        self.name = seed.name
        self.username = seed.username
        self.seedImageData = seed.imageData
        self.blurhash = seed.blurhash
    }

    /// Fetches the profile for a fresh name, join date, and avatar. Seeds from
    /// the shared profile cache first for instant display, then caches the
    /// freshly fetched profile.
    func loadProfile() async {
        if let cached = session.cachedUserProfile(for: userID) {
            apply(cached)
            await profileAvatars.load(userID: userID, picture: cached.profilePicture)
        }
        guard let profile = try? await flipClient.fetchProfile(userID: userID, owner: owner) else { return }
        session.cacheUserProfile(profile, for: userID)
        apply(profile)
        await profileAvatars.load(userID: userID, picture: profile.profilePicture)
    }

    private func apply(_ profile: Profile) {
        if let name = profile.displayName, !name.isEmpty { self.name = name }
        if let username = profile.username { self.username = username }
        if blurhash == nil { blurhash = profile.profilePicture?.thumbnailBlurhash }
        if let joined = profile.joinedAt {
            joinedText = "Joined \(joined.formatted(.dateTime.month(.wide).year()))"
        }
    }

    /// Blocks the user and returns to the Tips list; the blocklist reconcile hides the conversation.
    func block() async {
        do {
            try await blocklistController.block(userID: userID, displayName: displayName, avatarBlurhash: blurhash)
            router.popToRoot()
        } catch {
            session.dialogItem = .error(title: "Something Went Wrong", subtitle: "We were unable to block the user. Please try again")
            ErrorReporting.captureError(error, reason: "Failed to block user")
        }
    }
}
