//
//  RequestsScreen.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// Join requests in both directions: private groups the user hosts with people waiting, and groups
/// the user has asked to join. Pushed from the Chats tab's leading bar item.
struct RequestsScreen: View {

    @Environment(ConversationController.self) private var conversationController
    @Environment(SessionContainer.self) private var sessionContainer
    @Environment(AppRouter.self) private var router

    var body: some View {
        let hosted = sessionContainer.hostedLobbies.groupsWithRequests
            .compactMap { conversationController.conversation(withID: $0) }
        let sent = conversationController.requestedGroups(sessionContainer.lobbyRequests)

        Background(color: .backgroundMain) {
            if hosted.isEmpty, sent.isEmpty {
                // Join Requests' empty state, without its Share Group button: no one group to share.
                VStack(spacing: 8) {
                    Text("No requests right now")
                        .font(.appTextLarge)
                        .foregroundStyle(Color.textMain)
                    Text("Requests to join your private groups, and the ones you send, show up here")
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if !hosted.isEmpty {
                        Section {
                            ForEach(hosted, id: \.id) { conversation in
                                HostedRequestsRow(
                                    conversation: conversation,
                                    count: sessionContainer.hostedLobbies.requests(for: conversation.id).count
                                ) {
                                    router.push(.joinRequests(conversation.id))
                                }
                                .requestRowChrome()
                            }
                        } header: {
                            ListHeader("Waiting on you").requestHeaderInset()
                        }
                    }
                    if !sent.isEmpty {
                        Section {
                            ForEach(sent, id: \.conversation.id) { entry in
                                RequestedGroupRow(conversation: entry.conversation, requestedAt: entry.requestedAt) {
                                    router.push(.chatProfile(entry.conversation.id, origin: .featuredGroup))
                                }
                                .requestRowChrome()
                            }
                        } header: {
                            ListHeader("Sent").requestHeaderInset()
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Requests")
        .toolbarTitleDisplayMode(.inline)
    }
}

private extension View {

    /// The chat rows' insets and clear background. Set here because the List reads them only off
    /// its direct children, not from inside a row's own wrappers.
    func requestRowChrome() -> some View {
        listRowInsets(EdgeInsets(top: 14, leading: 20, bottom: 14, trailing: 20))
            .listRowBackground(Color.clear)
    }

    /// A plain List insets section headers 16pt; this brings them to the rows' 20pt.
    func requestHeaderInset() -> some View {
        padding(.leading, 4)
    }
}

// MARK: - HostedRequestsRow -

/// A private group the user hosts with people waiting to join; opens its Join Requests list.
private struct HostedRequestsRow: View {

    let conversation: Conversation
    let count: Int
    let onTap: () -> Void

    @Environment(ConversationController.self) private var conversationController
    @Environment(SessionContainer.self) private var sessionContainer

    var body: some View {
        let title = conversationController.displayName(for: conversation)
        let subtitle = PrivateGroupCopy.waiting(count: count)
        RecipientRowScaffold(
            avatarID: conversation.id.description,
            title: title,
            subtitle: AttributedString(subtitle),
            imageData: sessionContainer.profileAvatars.data(for: .chat(conversation.id)),
            blurhash: conversation.picture?.thumbnailBlurhash,
            accessibilityLabel: "\(title), \(subtitle)",
            onTap: onTap
        ) {
            HStack(spacing: 12) {
                // Secondary, like Archived's count: requests are not unread messages.
                Text("\(count)")
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
                Image(systemName: "chevron.right")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 9, height: 12)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .accessibilityIdentifier("requests-hosted-group-row")
        .task(id: conversation.id) {
            await sessionContainer.profileAvatars.load(.chat(conversation.id), picture: conversation.picture)
        }
    }
}

// MARK: - Requested groups -

extension ConversationController {

    /// The groups the user has asked to join, newest request first. A group whose metadata isn't
    /// held yet is left out until ``refreshRequestedGroup(_:)`` fetches it.
    func requestedGroups(_ requests: LobbyRequests) -> [(conversation: Conversation, requestedAt: Date)] {
        requests.conversationIDs
            .compactMap { id in
                guard let requestedAt = requests.requestedAt(id),
                      let conversation = conversation(withID: id)
                else { return nil }
                return (conversation, requestedAt)
            }
            .sorted { $0.requestedAt > $1.requestedAt }
    }
}
