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

/// Hosts the fully-UIKit chat (transcript + bars) inside SwiftUI. SwiftUI supplies the already-mapped
/// messages and hosts two bars — the Send Cash / Send Message action bar (pinned to the safe area)
/// and the composer (pinned to the keyboard). All scroll, keyboard, and flow-under behavior lives in
/// the UIKit screen. Both bars share `barModel`, so the swap animates through observation rather than
/// `UIHostingController.rootView` reassignment (which can't carry it).
struct ChatScreenRepresentable: UIViewControllerRepresentable {

    let items: [ChatItem]
    /// Fired when the transcript nears the top — the owner fetches the next older page (the
    /// transcript preserves scroll offset across the prepend). This is the incremental
    /// reverse-infinite paging that the UIKit rebuild exists to enable.
    let onReachTop: () -> Void
    let showsSendCash: Bool
    let showsSendMessage: Bool
    let conversationID: ConversationID?
    let onSendCash: () -> Void
    let conversationController: ConversationController
    let barModel: ConversationBarModel

    func makeUIViewController(context: Context) -> ChatScreenViewController {
        let restingHost = UIHostingController(rootView: restingBar(coordinator: context.coordinator))
        let keyboardHost = UIHostingController(rootView: keyboardBar(coordinator: context.coordinator))
        restingHost.view.backgroundColor = .clear
        keyboardHost.view.backgroundColor = .clear
        let screen = ChatScreenViewController(
            restingBar: restingHost.view,
            keyboardBar: keyboardHost.view,
            restingBarController: restingHost,
            keyboardBarController: keyboardHost
        )
        screen.onReachTop = onReachTop
        screen.update(items: items)
        screen.setComposing(barModel.isComposing)
        context.coordinator.restingHost = restingHost
        context.coordinator.keyboardHost = keyboardHost
        context.coordinator.screen = screen
        context.coordinator.lastMessageID = lastMessageID(of: items)
        return screen
    }

    func updateUIViewController(_ screen: ChatScreenViewController, context: Context) {
        // Re-supply both bars with current inputs; SwiftUI diffs them, so the composer's draft and
        // focus survive across updates.
        context.coordinator.restingHost?.rootView = restingBar(coordinator: context.coordinator)
        context.coordinator.keyboardHost?.rootView = keyboardBar(coordinator: context.coordinator)
        screen.onReachTop = onReachTop
        screen.setComposing(barModel.isComposing)

        // Scroll only when the user's *own* message was just appended — a new trailing message id
        // (skipping any trailing receipt) that is from me. Received messages and prepended history
        // leave the position alone.
        let newLastMessage = lastMessage(of: items)
        let newLastMessageID = newLastMessage?.id
        let lastIsOwnMessage = if case .message(let message) = newLastMessage { message.sender == .me } else { false }
        let trailingMessageChanged = newLastMessageID != context.coordinator.lastMessageID
        let appendedOwn = trailingMessageChanged && lastIsOwnMessage
        // A message arrived from the other side while this conversation is the one on screen — buzz.
        // Guarded against the initial population (no prior id), receipt-only updates (the trailing id
        // is unchanged), and the chat not being the visible conversation, so it only fires for a
        // genuine live arrival the user is looking at.
        let receivedNew = trailingMessageChanged
            && context.coordinator.lastMessageID != nil
            && newLastMessageID != nil
            && !lastIsOwnMessage
            && conversationController.visibleConversationID == conversationID
        screen.update(items: items)
        if appendedOwn {
            screen.scrollToBottom(animated: true)
        }
        if receivedNew {
            Haptics.soft()
        }
        context.coordinator.lastMessageID = newLastMessageID
    }

    private func lastMessage(of items: [ChatItem]) -> ChatItem? {
        items.last { if case .message = $0 { true } else { false } }
    }

    private func lastMessageID(of items: [ChatItem]) -> String? {
        lastMessage(of: items)?.id
    }

    private func restingBar(coordinator: Coordinator) -> AnyView {
        AnyView(
            ConversationActionBar(
                showsSendCash: showsSendCash,
                showsSendMessage: showsSendMessage,
                onSendCash: onSendCash,
                model: barModel
            )
            .modifier(MeasuredBarHeight { coordinator.screen?.setRestingBarHeight($0) })
        )
    }

    private func keyboardBar(coordinator: Coordinator) -> AnyView {
        AnyView(
            ConversationComposer(conversationID: conversationID, model: barModel)
                .environment(conversationController)
                .modifier(MeasuredBarHeight { coordinator.screen?.setKeyboardBarHeight($0) })
        )
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor final class Coordinator {
        var restingHost: UIHostingController<AnyView>?
        var keyboardHost: UIHostingController<AnyView>?
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
