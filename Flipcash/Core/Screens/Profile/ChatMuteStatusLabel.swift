//
//  ChatMuteStatusLabel.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// What the chat's mute currently is, drawn under the title on both chat settings surfaces —
/// "Muted until 5:56 PM" for a timed mute, plain "Muted" for an indefinite one, and nothing at all
/// while the chat is audible.
///
/// Stating the deadline is what makes a timed mute trustworthy: without it a timed mute can't be
/// told apart from an indefinite one, and the user has no way to know when the chat comes back.
/// It sits here rather than on ``ChatMuteRow`` because the row has no room for it and because the
/// mute is a fact about the chat, like the member count it follows.
struct ChatMuteStatusLabel: View {

    let conversationID: ConversationID

    @Environment(ConversationController.self) private var conversationController

    /// The instant the label is evaluated against, re-read when a timed mute lapses.
    ///
    /// A timed mute expires with nothing sent from the server, so no event can invalidate the
    /// label; it has to notice on its own. See ``muteExpiry``.
    @State private var now = Date.now

    private var conversation: Conversation? {
        conversationController.conversation(withID: conversationID)
    }

    private var text: String? {
        guard conversation?.isMuted(at: now) == true, let mute = conversation?.viewerState?.mute else {
            return nil
        }
        switch mute {
        case .until(let expiry):
            return "Muted until \(expiry.formattedRelatively(useTimeForToday: true))"
        case .forever:
            return "Muted"
        }
    }

    /// When the current mute lapses, or nil when it is indefinite or absent — the deadline the
    /// refresh below waits on.
    private var muteExpiry: Date? {
        guard case .until(let expiry) = conversation?.viewerState?.mute else { return nil }
        return expiry
    }

    var body: some View {
        if let text {
            HStack(spacing: 4) {
                Image(systemName: "bell.slash")
                Text(text)
            }
            .font(.appTextSmall)
            .foregroundStyle(.textSecondary)
            .accessibilityIdentifier("chat-mute-status")
            // Drop the label the moment a timed mute lapses. Re-run whenever the expiry changes, so
            // muting again while the screen is open re-arms it; cancelled with the screen.
            .task(id: muteExpiry) {
                guard let muteExpiry, muteExpiry > .now else { return }
                try? await Task.sleep(for: .seconds(muteExpiry.timeIntervalSinceNow))
                guard !Task.isCancelled else { return }
                now = .now
            }
        }
    }
}
