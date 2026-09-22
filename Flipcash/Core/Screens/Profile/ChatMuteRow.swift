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

    let conversationID: ConversationID
    let insets: EdgeInsets

    @State private var isPickingDuration = false

    var body: some View {
        // No chevron: this row opens a sheet rather than pushing a screen. The spacer is the one
        // the accessory would have brought, holding the label against the leading edge.
        Row(insets: insets) {
            Image(systemName: "bell.slash")
                .frame(minWidth: 45)
            Text("Mute Notifications")
                .foregroundStyle(.textMain)
            Spacer()
        } action: {
            isPickingDuration = true
        }
        .accessibilityIdentifier("chat-mute")
        .sheet(isPresented: $isPickingDuration) {
            MuteChatSheet(conversationID: conversationID, isPresented: $isPickingDuration)
        }
    }
}
