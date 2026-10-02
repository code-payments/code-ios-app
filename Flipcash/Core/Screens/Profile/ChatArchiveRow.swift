//
//  ChatArchiveRow.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// Archive / Unarchive, drawn beside ``ChatMuteRow`` on both chat settings screens. A named unit so
/// the DM and group screens cannot word or wire it differently.
struct ChatArchiveRow: View {

    let conversationID: ConversationID
    let insets: EdgeInsets

    @Environment(ConversationController.self) private var conversationController

    var body: some View {
        let isArchived = conversationController.isArchived(conversationID)
        Row(insets: insets) {
            Image(systemName: isArchived ? "tray.and.arrow.up" : "archivebox")
                .frame(minWidth: 45)
            Text(isArchived ? "Unarchive" : "Archive")
                .foregroundStyle(.textMain)
            Spacer()
        } action: {
            if isArchived {
                conversationController.unarchive(conversationID)
            } else {
                conversationController.archive(conversationID)
            }
        }
        .accessibilityIdentifier("chat-archive")
    }
}
