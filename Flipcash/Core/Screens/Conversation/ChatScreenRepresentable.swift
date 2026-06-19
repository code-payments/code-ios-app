//
//  ChatScreenRepresentable.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import UIKit
import FlipcashCore
import FlipcashUI

/// Hosts the fully-UIKit chat (transcript + the Send Cash / Send Message bar) inside SwiftUI.
/// SwiftUI does only two things: supply the already-mapped messages and host the bar so its
/// send + cash actions keep working. All scroll, keyboard, and flow-under behavior lives in the
/// UIKit screen. The bar is hosted *inside* the UIKit screen (pinned to the keyboard layout
/// guide) so the keyboard avoidance stays entirely in UIKit.
struct ChatScreenRepresentable: UIViewControllerRepresentable {

    let items: [ChatItem]
    /// Fired when the transcript nears the top — the owner fetches the next older page (the
    /// transcript preserves scroll offset across the prepend). This is the incremental
    /// reverse-infinite paging that the UIKit rebuild exists to enable.
    let onReachTop: () -> Void
    let showsSendCash: Bool
    let showsSendMessage: Bool
    @Binding var isComposing: Bool
    let conversationID: ConversationID?
    let onSendCash: () -> Void
    let conversationController: ConversationController

    func makeUIViewController(context: Context) -> ChatScreenViewController {
        let host = UIHostingController(rootView: bar())
        host.view.backgroundColor = .clear
        let screen = ChatScreenViewController(barView: host.view, barViewController: host)
        screen.onReachTop = onReachTop
        screen.update(items: items)
        context.coordinator.host = host
        context.coordinator.lastItemID = items.last?.id
        return screen
    }

    func updateUIViewController(_ screen: ChatScreenViewController, context: Context) {
        // Re-supply the bar with current inputs; SwiftUI diffs it, so the composer's draft and
        // focus survive across updates.
        context.coordinator.host?.rootView = bar()
        screen.onReachTop = onReachTop

        // Scroll only when the user's *own* message was just appended (a new trailing id, and the
        // last item is a message from me). Received messages and prepended history (the same
        // trailing id) leave the position alone.
        let newLast = items.last?.id
        let lastIsOwnMessage = if case .message(let message) = items.last { message.sender == .me } else { false }
        let appendedOwn = newLast != context.coordinator.lastItemID && lastIsOwnMessage
        screen.update(items: items)
        if appendedOwn {
            screen.scrollToBottom(animated: true)
        }
        context.coordinator.lastItemID = newLast
    }

    private func bar() -> AnyView {
        AnyView(
            ConversationBottomBar(
                showsSendCash: showsSendCash,
                showsSendMessage: showsSendMessage,
                isComposing: $isComposing,
                conversationID: conversationID,
                onSendCash: onSendCash
            )
            .environment(conversationController)
        )
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor final class Coordinator {
        var host: UIHostingController<AnyView>?
        var lastItemID: String?
    }
}
