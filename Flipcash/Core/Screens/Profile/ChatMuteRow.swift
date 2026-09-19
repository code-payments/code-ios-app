//
//  ChatMuteRow.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// The mute control as both chat settings surfaces draw it: one row that opens the duration picker.
///
/// A named unit rather than a copy per screen, because the two have to agree. A DM and a group are
/// the same mute — the contract doesn't distinguish them — so a row that wired its sheet differently
/// on one would be a bug neither screen could catch from the other.
///
/// The row says nothing about the current mute. It reads the same muted or not, and the state it
/// would have reported lives in ``ChatMuteStatusLabel`` under the title instead. A row whose label
/// changed under the tap that changed it read as a missed tap, and the deadline it drew alongside
/// left nothing for the label — the two longest strings appeared together, because the wording that
/// grew was the muted one.
struct ChatMuteRow: View {

    /// How the trailing chevron draws. The two hosts style it differently and each is right on its
    /// own screen, so the caller says which rather than one of them taking the other's look.
    enum Chevron {
        /// ``Row``'s own accessory chevron, matching the chat profile's other rows.
        case standard
        /// The smaller secondary chevron the user profile uses to match its profile card.
        case secondary
    }

    let conversationID: ConversationID
    let insets: EdgeInsets
    var chevron: Chevron = .standard

    @State private var isPickingDuration = false

    var body: some View {
        Row(insets: insets, accessory: chevron == .standard ? .chevron : nil) {
            Image(systemName: "bell.slash")
                .frame(minWidth: 45)
            Text("Mute Notifications")
                .foregroundStyle(.textMain)

            if chevron == .secondary {
                // Nothing has claimed the slack, so the chevron needs the spacer the accessory
                // would have brought.
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.textSecondary)
            }
        } action: {
            isPickingDuration = true
        }
        .accessibilityIdentifier("chat-mute")
        .sheet(isPresented: $isPickingDuration) {
            MuteChatSheet(conversationID: conversationID, isPresented: $isPickingDuration)
        }
    }
}
