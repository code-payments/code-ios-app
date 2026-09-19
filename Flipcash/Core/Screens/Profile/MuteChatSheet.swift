//
//  MuteChatSheet.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import UIKit
import FlipcashCore
import FlipcashUI

/// How long to silence a chat's notifications for. Drawn as the chats flow's action rows, the way
/// ``GroupInviteSheet`` draws its two.
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
        /// Mute until now plus this offset.
        case until(TimeInterval)
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
        ("1 Hour", .until(60 * 60)),
        ("8 Hours", .until(8 * 60 * 60)),
        ("1 Week", .until(7 * 24 * 60 * 60)),
        ("Always", .forever),
    ]

    @State private var isWorking = false

    private var isMuted: Bool {
        conversationController.conversation(withID: conversationID)?.isMuted(at: .now) ?? false
    }

    /// The rows to draw. Unmuting leads when there is a mute to clear, and is left off entirely when
    /// there isn't — on an audible chat it is a row that would do nothing.
    private var options: [(title: String, option: Option)] {
        isMuted ? [("Never", .never)] + Self.durations : Self.durations
    }

    var body: some View {
        PartialSheet(background: .backgroundMain) {
            VStack(spacing: 20) {
                header

                // What muting does and doesn't do, the way WhatsApp captions the same sheet. Worth
                // saying here because the answer isn't obvious and is easy to get wrong: a muted
                // chat still delivers, still stores, and still counts unread.
                Text("You'll still receive messages and see unread counts. Only notifications are silenced.")
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                VStack(spacing: 12) {
                    ForEach(options, id: \.title) { row in
                        ChatActionRow(
                            icon: .system(icon(for: row.option)),
                            title: row.title,
                            accessibilityIdentifier: "mute-chat-\(identifier(for: row.option))"
                        ) {
                            guard !isWorking else { return }
                            Task { await apply(row.option) }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, bottomPadding)
        }
    }

    /// The sheet's own title bar — ``PartialSheet`` sizes itself to its content, so there is no
    /// navigation bar to hang a title on. Mirrors ``GroupInviteSheet/header``.
    private var header: some View {
        ZStack {
            Text("Mute Notifications")
                .font(.appBarButton)
                .foregroundStyle(Color.textMain)

            HStack {
                Spacer()
                CloseButton(binding: $isPresented)
                    .foregroundStyle(Color.textMain)
            }
        }
    }

    /// The design's 16 under the last row, less whatever the sheet already holds back for the home
    /// indicator.
    private var bottomPadding: CGFloat {
        let reserved = UIApplication.shared.currentKeyWindow?.safeAreaInsets.bottom ?? 0
        return max(0, 16 - reserved)
    }

    private func icon(for option: Option) -> SystemSymbol {
        switch option {
        case .until: .clock
        case .forever: .bellSlash
        case .never: .bell
        }
    }

    private func identifier(for option: Option) -> String {
        switch option {
        case .until(let duration): "\(Int(duration))"
        case .forever: "forever"
        case .never: "never"
        }
    }

    /// Applies the choice, then dismisses. A timed mute's expiry is computed here, at the tap,
    /// rather than carried as a duration: the server stores an instant, and the client owns the
    /// countdown against it.
    private func apply(_ option: Option) async {
        isWorking = true
        defer { isWorking = false }
        do {
            switch option {
            case .until(let duration):
                try await conversationController.mute(conversationID: conversationID, .until(.now.addingTimeInterval(duration)))
            case .forever:
                try await conversationController.mute(conversationID: conversationID, .forever)
            case .never:
                try await conversationController.unmute(conversationID: conversationID)
            }
            isPresented = false
        } catch {
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
}
