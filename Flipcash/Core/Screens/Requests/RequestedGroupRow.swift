//
//  RequestedGroupRow.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// A private group the user has asked to join, in the Requests screen's Sent section.
struct RequestedGroupRow: View {

    let conversation: Conversation
    let requestedAt: Date
    let onTap: () -> Void

    @Environment(ConversationController.self) private var conversationController
    @Environment(SessionContainer.self) private var sessionContainer

    var body: some View {
        let title = conversationController.displayName(for: conversation)
        // A minute's granularity is all the age shows, so the row only needs to redraw that often.
        TimelineView(.periodic(from: requestedAt, by: 60)) { context in
            let age = PrivateGroupCopy.pendingTitle(requestedAt: requestedAt, now: context.date)
            RecipientRowScaffold(
                avatarID: conversation.id.description,
                title: title,
                subtitle: AttributedString(age),
                imageData: sessionContainer.profileAvatars.data(for: .chat(conversation.id)),
                blurhash: conversation.picture?.thumbnailBlurhash,
                accessibilityLabel: "\(title), \(age)",
                onTap: onTap
            ) {
                Image(systemName: "chevron.right")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 9, height: 12)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .accessibilityIdentifier("chat-requested-group-row")
        .task(id: conversation.id) {
            await sessionContainer.profileAvatars.load(.chat(conversation.id), picture: conversation.picture)
        }
    }
}
