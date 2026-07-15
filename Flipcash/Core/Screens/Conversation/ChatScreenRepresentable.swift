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

/// Hosts the fully-UIKit chat (transcript + bar) inside SwiftUI. SwiftUI supplies the already-mapped
/// messages and hosts the single bottom bar — Send Cash beside the composer — pinned to the keyboard
/// layout guide. All scroll, keyboard, and flow-under behavior lives in the UIKit screen.
struct ChatScreenRepresentable: UIViewControllerRepresentable {

    let items: [ChatItem]
    /// Fired when the transcript nears the top — the owner fetches the next older page (the
    /// transcript preserves scroll offset across the prepend). This is the incremental
    /// reverse-infinite paging that the UIKit rebuild exists to enable.
    let onReachTop: () -> Void
    /// Fired when the user taps a failed outgoing row; the argument is the message's stable id (its
    /// client message id). The owner re-sends it.
    let onRetry: (String) -> Void
    /// Fired when the user taps a cash card; the argument is the message's stable id. The owner opens
    /// that token's currency info.
    let onCashCardTap: (String) -> Void
    /// Fired when the user taps a URL in a message. The owner routes it through the deep-link handler,
    /// falling back to the system browser.
    let onOpenURL: (URL) -> Void
    let showsSendCash: Bool
    let chatExists: Bool
    let conversationID: ConversationID?
    let symbol: String
    let onSendCash: () -> Void
    let conversationController: ConversationController
    let barModel: ConversationBarModel

    func makeUIViewController(context: Context) -> ChatScreenViewController {
        let barHost = UIHostingController(rootView: bar(coordinator: context.coordinator))
        barHost.view.backgroundColor = .clear
        let screen = ChatScreenViewController(bar: barHost.view, barController: barHost)
        screen.onReachTop = onReachTop
        screen.onRetry = onRetry
        screen.onCashCardTap = onCashCardTap
        screen.onOpenURL = onOpenURL
        screen.update(items: items)
        context.coordinator.barHost = barHost
        context.coordinator.screen = screen
        context.coordinator.lastMessageID = lastMessageID(of: items)
        return screen
    }

    func updateUIViewController(_ screen: ChatScreenViewController, context: Context) {
        // Re-supply the bar with current inputs; SwiftUI diffs it, so the composer's draft and
        // focus survive across updates.
        context.coordinator.barHost?.rootView = bar(coordinator: context.coordinator)
        screen.onReachTop = onReachTop
        screen.onRetry = onRetry
        screen.onCashCardTap = onCashCardTap
        screen.onOpenURL = onOpenURL

        // Scroll only when the user's *own* message was just appended — a new trailing message id
        // (skipping any trailing receipt) that is from me. Received messages and prepended history
        // leave the position alone.
        let newLastMessage = lastMessage(of: items)
        let newLastMessageID = newLastMessage?.id
        let lastIsOwnMessage = if case .message(let message) = newLastMessage { message.sender == .me } else { false }
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
                chatExists: chatExists,
                conversationID: conversationID,
                symbol: symbol,
                onSendCash: onSendCash,
                model: barModel
            )
            .environment(conversationController)
            .modifier(MeasuredBarHeight { coordinator.screen?.setBarHeight($0) })
        )
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor final class Coordinator {
        var barHost: UIHostingController<AnyView>?
        weak var screen: ChatScreenViewController?
        var lastMessageID: String?
    }
}

/// Reports a hosted bar's measured natural height to the UIKit screen, which drives its height
/// constraint. Take the natural height at the proposed width so the composer can grow to its full
/// multiline height — the hosting controller's intrinsic size mis-measures and lets the composer
/// overflow under the keyboard.
private struct MeasuredBarHeight: ViewModifier {
    let report: (CGFloat) -> Void

    func body(content: Content) -> some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: report)
    }
}
