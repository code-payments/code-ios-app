//
//  RestrictedUsersScreen.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

/// One of the host's moderation lists: the members they silenced, or the ones they removed, each
/// with the button that undoes it.
struct RestrictedUsersScreen: View {

    let conversationID: ConversationID
    let list: RestrictedUserList

    @Environment(Container.self) private var container
    @Environment(SessionContainer.self) private var sessionContainer
    @Environment(AppRouter.self) private var router

    @State private var model: RestrictedUsersModel?

    private var title: String {
        switch list {
        case .silenced: "Silenced"
        case .removed:  "Removed"
        }
    }

    var body: some View {
        Background(color: .backgroundMain) {
            content
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: conversationID) {
            let model = RestrictedUsersModel(
                list: list,
                moderation: GroupModeration(
                    moderation: container.flipClient,
                    owner: sessionContainer.session.ownerKeyPair,
                    conversationID: conversationID
                )
            )
            self.model = model
            await model.load()
        }
    }

    @ViewBuilder
    private var content: some View {
        if let model {
            switch model.phase {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed:
                message("Couldn't load this list")
            case .loaded:
                TimelineView(.everyMinute) { context in
                    let rows = model.rows(at: context.date)
                    if rows.isEmpty {
                        message(list == .silenced ? GroupModerationCopy.noSilenced : GroupModerationCopy.noRemoved)
                    } else {
                        List(rows) { user in
                            RestrictedUserRow(
                                user: user,
                                list: list,
                                now: context.date,
                                imageData: user.userID.flatMap { sessionContainer.profileAvatars.data(for: $0) },
                                isWorking: model.inFlight.contains(user.id),
                                openProfile: { openProfile(user) },
                                undo: { Task { await undo(user, in: model) } }
                            )
                            .task(id: user.userID) {
                                await sessionContainer.profileAvatars.load(userID: user.userID, picture: user.profilePicture)
                            }
                            .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .animation(.default, value: rows.map(\.id))
                    }
                }
            }
        } else {
            Color.clear
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.appTextMedium)
            .foregroundStyle(Color.textSecondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func openProfile(_ user: ConversationRestrictedUser) {
        guard let userID = user.userID else { return }
        router.push(.userProfile(userID, origin: .groupMember(conversationID)))
    }

    private func undo(_ user: ConversationRestrictedUser, in model: RestrictedUsersModel) async {
        do {
            try await model.undo(user)
        } catch {
            let action = list == .silenced ? "unsilence" : "unban"
            sessionContainer.session.dialogItem = .error(
                title: "Something Went Wrong",
                subtitle: "We were unable to \(action) \(GroupModerationCopy.firstName(of: user.displayName)). Please try again"
            )
            ErrorReporting.captureError(error, reason: "Failed to \(action) user")
        }
    }
}

private struct RestrictedUserRow: View {

    let user: ConversationRestrictedUser
    let list: RestrictedUserList
    let now: Date
    let imageData: Data?
    let isWorking: Bool
    let openProfile: () -> Void
    let undo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: openProfile) {
                HStack(spacing: 12) {
                    ContactAvatarView(
                        id: user.userID?.uuidString ?? user.displayName,
                        displayName: user.displayName,
                        imageData: imageData,
                        size: 40
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.displayName)
                            .font(.appTextMedium)
                            .foregroundStyle(Color.textMain)
                        Text(user.detail(on: list, now: now))
                            .font(.appTextCaption)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .lineLimit(1)
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: undo) {
                // The label keeps its width while the spinner shows.
                Text(list == .silenced ? "Unsilence" : "Unban")
                    .opacity(isWorking ? 0 : 1)
                    .overlay {
                        if isWorking {
                            ProgressView()
                        }
                    }
            }
            .buttonStyle(JoinRequestCapsuleStyle(kind: .secondary))
            .allowsHitTesting(!isWorking)
            .accessibilityIdentifier("restricted-user-undo")
        }
    }
}
