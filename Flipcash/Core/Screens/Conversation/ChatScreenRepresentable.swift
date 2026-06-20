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
        let host = UIHostingController(rootView: bar(coordinator: context.coordinator))
        host.view.backgroundColor = .clear
        let screen = ChatScreenViewController(barView: host.view, barViewController: host)
        screen.onReachTop = onReachTop
        screen.update(items: items)
        context.coordinator.host = host
        context.coordinator.screen = screen
        context.coordinator.lastMessageID = lastMessageID(of: items)
        return screen
    }

    func updateUIViewController(_ screen: ChatScreenViewController, context: Context) {
        // Re-supply the bar with current inputs; SwiftUI diffs it, so the composer's draft and
        // focus survive across updates.
        context.coordinator.host?.rootView = bar(coordinator: context.coordinator)
        screen.onReachTop = onReachTop

        // Scroll only when the user's *own* message was just appended — a new trailing message id
        // (skipping any trailing receipt) that is from me. Received messages and prepended history
        // leave the position alone.
        let newLastMessageID = lastMessageID(of: items)
        let lastIsOwnMessage = if case .message(let message) = lastMessage(of: items) { message.sender == .me } else { false }
        let appendedOwn = newLastMessageID != context.coordinator.lastMessageID && lastIsOwnMessage
        screen.update(items: items)
        if appendedOwn {
            screen.scrollToBottom(animated: true)
        }
        context.coordinator.lastMessageID = newLastMessageID
    }

    private func lastMessage(of items: [ChatItem]) -> ChatItem? {
        items.last { if case .message = $0 { true } else { false } }
    }

    private func lastMessageID(of items: [ChatItem]) -> String? {
        lastMessage(of: items)?.id
    }

    private func bar(coordinator: Coordinator) -> AnyView {
        AnyView(
            ConversationBottomBar(
                showsSendCash: showsSendCash,
                showsSendMessage: showsSendMessage,
                isComposing: $isComposing,
                conversationID: conversationID,
                onSendCash: onSendCash
            )
            .environment(conversationController)
            // Take the natural height at the proposed width so the composer can grow to its full
            // multiline height, then report that measured height to the UIKit screen, which drives
            // the bar's height constraint. This keeps the bar's frame matched to its content — the
            // hosting controller's intrinsic size mis-measures and lets the composer overflow under
            // the keyboard.
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                coordinator.screen?.setBarHeight(height)
            }
        )
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor final class Coordinator {
        var host: UIHostingController<AnyView>?
        weak var screen: ChatScreenViewController?
        var lastMessageID: String?
    }
}
