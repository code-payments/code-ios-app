//
//  MuteChatSheet.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// How long to silence a chat's notifications for, as a tray of option rows.
///
/// The durations are the client's choice; the contract admits only two mute shapes — until a
/// timestamp, or forever — so every timed option is the same shape with a different offset.
/// "Never" is the unmute, and is still its own RPC rather than a mute of zero length: it is worded
/// as a duration only because every label here names the resulting state rather than the action,
/// and it appears only once there is a mute to clear.
struct MuteChatSheet: View {

    let conversationID: ConversationID

    @Binding var isPresented: Bool

    @Environment(ConversationController.self) private var conversationController
    @Environment(SessionContainer.self) private var sessionContainer

    /// What a row on this sheet does.
    private enum Option: Hashable {
        /// Mute until now plus this offset, reported to analytics as `duration`.
        case until(TimeInterval, duration: MuteDuration)
        /// Mute with no end.
        case forever
        /// Clear the mute.
        case never
    }

    /// The offered durations, longest last. The labels double as the state readout, so they are
    /// named for the resulting state rather than the action — "1 Week", not "Mute for 1 week".
    ///
    /// The set is WhatsApp's (8 hours, 1 week, Always) plus Telegram's 1 hour, which is the shortest
    /// option either offers and the one a noisy group most often wants.
    private static let durations: [(title: String, option: Option)] = [
        ("1 Hour", .until(60 * 60, duration: .oneHour)),
        ("8 Hours", .until(8 * 60 * 60, duration: .eightHours)),
        ("1 Week", .until(7 * 24 * 60 * 60, duration: .oneWeek)),
        ("Always", .forever),
    ]

    @State private var isWorking = false

    /// The unmute row's presence, fixed for the dismissal by ``apply(_:)``.
    ///
    /// Nil while the sheet is idle, so a mute that lapses under an open sheet still drops the row.
    /// Applying a choice pins it, because the store converges before the sheet finishes animating
    /// away: read live, the list gained or lost its first row on the way out.
    @State private var pinnedOffersUnmute: Bool?

    private var isMuted: Bool {
        conversationController.conversation(withID: conversationID)?.isMuted(at: .now) ?? false
    }

    /// Whether to offer the unmute at all — on an audible chat it is a row that would do nothing.
    private var offersUnmute: Bool {
        pinnedOffersUnmute ?? isMuted
    }

    /// The rows to draw, unmuting first when it is offered.
    private var options: [(title: String, option: Option)] {
        offersUnmute ? [("Never", .never)] + Self.durations : Self.durations
    }

    /// The row picked for the CTA to apply, in the select-then-confirm pattern.
    @State private var selection: Option?

    var body: some View {
        Tray(
            title: "Mute Notifications",
            // What muting does and doesn't do, the way WhatsApp captions the same sheet. Worth
            // saying here because the answer isn't obvious and is easy to get wrong: a muted chat
            // still delivers, still stores, and still counts unread.
            message: "You'll still receive messages and see unread counts. Only notifications are silenced",
            icon: .central(.bell2Off),
            actions: actions
        ) {
            VStack(spacing: TrayOptionRow.gap) {
                ForEach(options, id: \.title) { row in
                    TrayOptionRow(
                        row.title,
                        icon: icon(for: row.option),
                        isSelected: selection == row.option
                    ) {
                        guard !isWorking else { return }
                        selection = row.option
                    }
                    .accessibilityIdentifier("mute-chat-\(identifier(for: row.option))")
                }
            }
        }
    }

    /// The CTA that applies the selected row, worded for an unmute when that is the pick.
    private var actions: [TrayAction] {
        [
            TrayAction(
                selection == .never ? "Unmute" : "Mute",
                state: isWorking ? .loading : .normal,
                isEnabled: selection != nil
            ) {
                guard let selection else { return }
                Task { await apply(selection) }
            },
        ]
    }

    private func icon(for option: Option) -> Icon {
        switch option {
        case .until: .clock
        case .forever: .bell2Off
        case .never: .bell2
        }
    }

    private func identifier(for option: Option) -> String {
        switch option {
        case .until(let offset, _): "\(Int(offset))"
        case .forever: "forever"
        case .never: "never"
        }
    }

    /// Applies the choice, then dismisses. A timed mute's expiry is computed here, at the tap,
    /// rather than carried as a duration: the server stores an instant, and the client owns the
    /// countdown against it.
    private func apply(_ option: Option) async {
        pinnedOffersUnmute = offersUnmute
        isWorking = true
        defer { isWorking = false }
        let chatType = conversationController.conversation(withID: conversationID)?.type
        do {
            switch option {
            case .until(let offset, _):
                try await conversationController.mute(conversationID: conversationID, .until(.now.addingTimeInterval(offset)))
            case .forever:
                try await conversationController.mute(conversationID: conversationID, .forever)
            case .never:
                try await conversationController.unmute(conversationID: conversationID)
            }
            track(option, chatType: chatType, error: nil)
            isPresented = false
        } catch {
            track(option, chatType: chatType, error: error)
            isPresented = false
            let unmuting = option == .never
            sessionContainer.session.dialogItem = .error(
                title: "Something Went Wrong",
                subtitle: unmuting
                    ? "We were unable to unmute this chat. Please try again"
                    : "We were unable to mute this chat. Please try again"
            )
            ErrorReporting.captureError(error, reason: unmuting ? "Failed to unmute chat" : "Failed to mute chat")
        }
    }

    /// Reports what the mute or unmute call returned; `error` is nil on success.
    private func track(_ option: Option, chatType: ConversationType?, error: Error?) {
        switch option {
        case .until(_, let duration): Analytics.chatMuted(chatType: chatType, duration: duration, error: error)
        case .forever:                Analytics.chatMuted(chatType: chatType, duration: .always, error: error)
        case .never:                  Analytics.chatUnmuted(chatType: chatType, error: error)
        }
    }
}
