//
//  ChatMuteRow.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// The mute control as both chat settings surfaces draw it: one row that opens the duration picker
/// while the chat is audible, and unmutes on the tap once it isn't.
///
/// A named unit rather than a copy per screen, because the two have to agree. A DM and a group are
/// the same mute — the contract doesn't distinguish them — so a row that read its state or drew its
/// deadline differently on one would be a bug neither screen could catch from the other.
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

    @Environment(ConversationController.self) private var conversationController
    @Environment(SessionContainer.self) private var sessionContainer

    @State private var isPickingDuration = false
    @State private var isUnmuting = false

    /// The instant the row is evaluated against, re-read when a timed mute lapses.
    ///
    /// A timed mute expires with nothing sent from the server, so no event can invalidate the row;
    /// it has to notice on its own. See ``muteExpiry``.
    @State private var now = Date.now

    private var conversation: Conversation? {
        conversationController.conversation(withID: conversationID)
    }

    private var isMuted: Bool {
        conversation?.isMuted(at: now) ?? false
    }

    /// The mute as the row reports it on the right — "Muted until 5:56 PM" for a timed mute, plain
    /// "Muted" for an indefinite one. Nil when the chat isn't muted.
    ///
    /// Stating the deadline is what makes a timed mute trustworthy: without it the row can't be
    /// told apart from an indefinite one, and the user has no way to know when the chat comes back.
    private var muteDetail: String? {
        guard isMuted, let mute = conversation?.viewerState?.mute else { return nil }
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

    /// The trailing accessory: the loader while unmuting, else ``Row``'s chevron for the standard
    /// style. The secondary style draws its own inside the content, so it takes no accessory.
    private var accessory: RowAccessory? {
        if isUnmuting { return .loader(.textMain) }
        return chevron == .standard ? .chevron : nil
    }

    var body: some View {
        Row(insets: insets, disabled: isUnmuting, accessory: accessory) {
            Image(systemName: isMuted ? "bell.slash" : "bell")
                .frame(minWidth: 45)
            Text(isMuted ? "Unmute Notifications" : "Mute Notifications")
                .foregroundStyle(.textMain)

            if let muteDetail {
                Text(muteDetail)
                    .font(.appTextSmall)
                    .foregroundStyle(.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            if chevron == .secondary, !isUnmuting {
                // Nothing has claimed the slack when there is no deadline to print, so the chevron
                // needs the spacer the accessory would have brought.
                if muteDetail == nil {
                    Spacer()
                }
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.textSecondary)
            }
        } action: {
            // Muting asks for how long; unmuting has nothing to ask, so it is the tap itself rather
            // than a second sheet with one row on it.
            if isMuted {
                Task { await unmute() }
            } else {
                isPickingDuration = true
            }
        }
        .accessibilityIdentifier("chat-mute")
        .sheet(isPresented: $isPickingDuration) {
            MuteChatSheet(conversationID: conversationID, isPresented: $isPickingDuration)
        }
        // Flip the row back to "Mute" the moment a timed mute lapses. Re-run whenever the expiry
        // changes, so muting again while the screen is open re-arms it; cancelled with the screen.
        .task(id: muteExpiry) {
            guard let muteExpiry, muteExpiry > .now else { return }
            try? await Task.sleep(for: .seconds(muteExpiry.timeIntervalSinceNow))
            guard !Task.isCancelled else { return }
            now = .now
        }
    }

    /// Unmutes, staying on the screen — unlike leaving, there is nothing to unwind to.
    private func unmute() async {
        isUnmuting = true
        defer { isUnmuting = false }
        do {
            try await conversationController.unmute(conversationID: conversationID)
            now = .now
        } catch {
            sessionContainer.session.dialogItem = .error(
                title: "Something Went Wrong",
                subtitle: "We were unable to unmute this chat. Please try again"
            )
            ErrorReporting.captureError(error, reason: "Failed to unmute chat")
        }
    }
}
