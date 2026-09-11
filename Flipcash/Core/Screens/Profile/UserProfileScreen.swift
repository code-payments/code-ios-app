//
//  UserProfileScreen.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// The counterpart's Flipcash profile with a Block action, reached from a tip DM.
struct UserProfileScreen: View {
    let userID: UserID

    @Environment(SessionContainer.self) private var sessionContainer
    @Environment(BlocklistController.self) private var blocklistController
    @Environment(AppRouter.self) private var router

    var body: some View {
        let seed = sessionContainer.conversationController.counterpartSeed(forUserID: userID)
        let avatarData = sessionContainer.tipAvatars.data(for: userID)
        UserProfileContent(
            model: UserProfileViewModel(
                userID: userID,
                flipClient: sessionContainer.flipClient,
                owner: sessionContainer.session.ownerKeyPair,
                blocklistController: blocklistController,
                router: router,
                session: sessionContainer.session,
                seed: seed,
                avatarData: avatarData
            )
        )
    }
}

private struct UserProfileContent: View {
    @State private var model: UserProfileViewModel
    @State private var dialogItem: DialogItem?

    init(model: UserProfileViewModel) {
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
                }

                Row(insets: .init(top: 25, leading: 0, bottom: 25, trailing: 0)) {
                    Image(systemName: "nosign")
                        .frame(minWidth: 45)
                    Text("Block")
                        .foregroundStyle(.textMain)
                    Spacer()
                    // Secondary (alpha-white) chevron, matching the profile card.
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.textSecondary)
                } action: {
                    dialogItem = blockDialog()
                }
                .font(.appDisplayXS)
                .padding(.top, 24)

                Spacer()
            }
            .padding(.horizontal, 20)
        }
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
        .dialog(item: $dialogItem)
        .task { await model.loadProfile() }
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

@MainActor
@Observable
final class UserProfileViewModel {
    let userID: UserID

    /// The counterpart's own name, or `nil` for an account that hasn't set one.
    private(set) var name: String?

    private(set) var username: Username?
    private(set) var imageData: Data?
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

    init(userID: UserID, flipClient: FlipClient, owner: KeyPair, blocklistController: BlocklistController, router: AppRouter, session: Session, seed: CounterpartSeed, avatarData: Data?) {
        self.userID = userID
        self.flipClient = flipClient
        self.owner = owner
        self.blocklistController = blocklistController
        self.router = router
        self.session = session
        self.name = seed.name
        self.username = seed.username
        self.imageData = avatarData ?? seed.imageData
        self.blurhash = seed.blurhash
    }

    /// Fetches the profile for a fresh name, join date, and avatar. Seeds from
    /// the shared profile cache first for instant display, then caches the
    /// freshly fetched profile.
    func loadProfile() async {
        if let cached = session.cachedUserProfile(for: userID) {
            apply(cached)
        }
        guard let profile = try? await flipClient.fetchProfile(userID: userID, owner: owner) else { return }
        session.cacheUserProfile(profile, for: userID)
        apply(profile)
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
