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
/// Unmuting is not on this sheet: it is its own RPC, not a mute of zero length, and the row that
/// opens this sheet becomes the unmute once a chat is muted.
struct MuteChatSheet: View {

    let conversationID: ConversationID

    @Binding var isPresented: Bool

    @Environment(ConversationController.self) private var conversationController
    @Environment(SessionContainer.self) private var sessionContainer

    /// The offered durations, longest last. `nil` is the indefinite option.
    ///
    /// The set is WhatsApp's (8 hours, 1 week, Always) plus Telegram's 1 hour, which is the shortest
    /// option either offers and the one a noisy group most often wants. The labels double as the
    /// state readout on the row that opens this sheet, so they are named for the resulting state
    /// rather than the action — "1 Week", not "Mute for 1 week".
    private static let options: [(title: String, duration: TimeInterval?)] = [
        ("1 Hour", 60 * 60),
        ("8 Hours", 8 * 60 * 60),
        ("1 Week", 7 * 24 * 60 * 60),
        ("Always", nil),
    ]

    @State private var isMuting = false

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
                    ForEach(Self.options, id: \.title) { option in
                        ChatActionRow(
                            icon: option.duration == nil ? .system(.bellSlash) : .system(.clock),
                            title: option.title,
                            accessibilityIdentifier: "mute-chat-\(option.duration.map { "\(Int($0))" } ?? "forever")"
                        ) {
                            guard !isMuting else { return }
                            Task { await mute(option.duration) }
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

    /// Mutes, then dismisses. The expiry is computed here, at the tap, rather than carried as a
    /// duration: the server stores an instant, and the client owns the countdown against it.
    private func mute(_ duration: TimeInterval?) async {
        isMuting = true
        defer { isMuting = false }
        let mute: ConversationMuteState = duration.map { .until(.now.addingTimeInterval($0)) } ?? .forever
        do {
            try await conversationController.mute(conversationID: conversationID, mute)
            isPresented = false
        } catch {
            isPresented = false
            sessionContainer.session.dialogItem = .error(
                title: "Something Went Wrong",
                subtitle: "We were unable to mute this chat. Please try again"
            )
            ErrorReporting.captureError(error, reason: "Failed to mute chat")
        }
    }
}
