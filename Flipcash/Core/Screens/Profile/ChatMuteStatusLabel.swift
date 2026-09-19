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
/// It sits here rather than on ``ChatMuteRow`` because the row has no room for it.
///
/// Drawn as a chip rather than as another line of secondary text: the lines above it are the chat's
/// own identity — its name, its size, when someone joined — and this is the viewer's setting. Given
/// their styling it read as a fourth fact about the chat, and on a counterpart's profile it was the
/// fourth such line in a row. The fill gives it its own ground instead.
///
/// Amber, because a mute is the one thing on the screen that will stop being true on its own, and
/// the colour is what separates it from the settled facts above. Tinted rather than solid so it
/// stays under the title — see ``ChipStyle/tinted(_:on:)``.
struct ChatMuteStatusLabel: View {

    let conversationID: ConversationID

    @Environment(ConversationController.self) private var conversationController

    /// The instant the label is evaluated against, re-read when a timed mute lapses.
    ///
    /// A timed mute expires with nothing sent from the server, so no event can invalidate the
    /// label; it has to notice on its own. See ``muteExpiry``.
    @State private var now = Date.now

    /// What the chip last said, so a fade-out goes quiet on its own wording.
    ///
    /// The text is nil the instant a mute is cleared, but the chip is still on screen fading. Drawn
    /// straight from a placeholder it would change what it said on the way out, which reads as a
    /// correction rather than a dismissal.
    @State private var lastText = "Muted"

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
        HStack(spacing: 4) {
            Image(systemName: "bell.slash")
            // Drawn even when there is no mute, so the line claims its height either way — without
            // it the row block below jumps up the moment a mute lapses or is cleared, which reads
            // as the screen re-laying itself out rather than one fact going away. Invisible except
            // during a fade-out, which is the one moment the fallback is what the user sees.
            Text(text ?? lastText)
        }
        .chip(.tinted(.warning, on: .warningSecondary))
        // The chip takes its new width at once, inside the spring below. Geometry interpolates and
        // glyphs don't: the fill grew from the old string's width while the new string was already
        // drawn in full, so the text sat outside the capsule for the length of the animation.
        .animation(nil, value: text)
        .padding(.top, 3)
        .opacity(text == nil ? 0 : 1)
        .scaleEffect(text == nil ? 0.85 : 1)
        // Springs in and fades out. Arriving is the event worth seeing — the user just chose it —
        // so it gets the overshoot; going away is either their unmute or a deadline passing, and
        // neither wants drawing attention to. Read against the new state, so each direction picks
        // its own curve.
        .animation(
            text == nil
                ? .easeOut(duration: 0.2)
                : .spring(response: 0.34, dampingFraction: 0.62),
            value: text
        )
        .accessibilityHidden(text == nil)
        .accessibilityIdentifier("chat-mute-status")
        .onChange(of: text) { _, text in
            if let text { lastText = text }
        }
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
