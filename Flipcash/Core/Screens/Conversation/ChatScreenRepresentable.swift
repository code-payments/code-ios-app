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
    /// Fired when the user taps the profile card's call to action. The owner opens the
    /// counterpart's contact card (or the add-contact sheet), same as tapping the nav title.
    let onContactAction: () -> Void
    /// Fired when the user taps the profile card in a tip DM; nil disables the card tap.
    let onProfileTap: (() -> Void)?
    /// Fired when a context-menu action is chosen on a row, with the row's stable id. Copy never
    /// arrives here — the transcript puts the text on the pasteboard itself.
    let onMessageAction: (String, MessageCapability) -> Void
    /// Brings the quoted original into the loader's window; the scroll follows here.
    let onQuoteTap: (String) -> Void
    let showsSendCash: Bool
    let chatExists: Bool
    let conversationID: ConversationID?
    let symbol: String
    let onSendCash: () -> Void
    let conversationController: ConversationController
    let barModel: ConversationBarModel
    let composer: ComposerModel
    /// The row an edit is open on, or nil. Passed in rather than read off `composer` inside the
    /// representable so that the owning view's body depends on it — which is what gets
    /// `updateUIViewController` called, and the edit backdrop taken down, when the edit ends.
    let editingStableID: String?
    /// Raise the keyboard when the screen first appears (post-tip open). The UIKit screen focuses
    /// the composer field in `viewDidAppear` — a hosted SwiftUI `@FocusState` never presents the
    /// keyboard across the hosting boundary.
    let focusOnAppear: Bool
    /// Whether this is a tip DM — the send button then stays minimized.
    let isTipDm: Bool

    func makeUIViewController(context: Context) -> ChatScreenViewController {
        let barHost = UIHostingController(rootView: bar(coordinator: context.coordinator))
        barHost.view.backgroundColor = .clear
        // The bar's content is pinned to the bottom of this view and overhangs the top while the
        // height constraint catches up, so the overhang has to be allowed to draw.
        barHost.view.clipsToBounds = false
        let screen = ChatScreenViewController(bar: barHost.view, barController: barHost)
        screen.focusesComposerOnAppear = focusOnAppear
        screen.onReachTop = onReachTop
        screen.onRetry = onRetry
        screen.onCashCardTap = onCashCardTap
        screen.onOpenURL = onOpenURL
        screen.onContactAction = onContactAction
        screen.onProfileTap = onProfileTap
        screen.onMessageAction = keyboardFollowing(onMessageAction, screen: screen)
        screen.onQuoteTap = { [weak screen] stableID in
            onQuoteTap(stableID)
            // The reveal may have to move the loader's anchor first, so the scroll records a
            // pending target when the row is not in the window yet.
            screen?.scrollToMessage(id: stableID)
        }
        screen.onCancelEdit = { [composer] in composer.endEditing() }
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
        screen.onContactAction = onContactAction
        screen.onProfileTap = onProfileTap
        screen.onMessageAction = keyboardFollowing(onMessageAction, screen: screen)
        screen.onQuoteTap = { [weak screen] stableID in
            onQuoteTap(stableID)
            // The reveal may have to move the loader's anchor first, so the scroll records a
            // pending target when the row is not in the window yet.
            screen?.scrollToMessage(id: stableID)
        }
        screen.onCancelEdit = { [composer] in composer.endEditing() }
        // The backdrop is raised from the menu action itself (see `keyboardFollowing`) because it
        // has to claim the menu's blur before the dismissal fades it; it comes down here, whichever
        // way the edit ended — cancelled, saved, or abandoned by a tap outside.
        if editingStableID == nil {
            screen.endEditSpotlight()
        }

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

    /// Wraps the action handler so the screen follows the action. The menu dismissed the keyboard
    /// to present itself and the composer can't drive it back on its own — a hosted SwiftUI
    /// `@FocusState` doesn't make the field first responder — so only the screen can raise it for an
    /// edit, or hold it down for a delete, whose confirmation sheet it would otherwise cover. Edit
    /// also claims the menu's blur here, while the menu is still up, so the two states share one
    /// backdrop instead of fading one out and another in.
    private func keyboardFollowing(
        _ handler: @escaping (String, MessageCapability) -> Void,
        screen: ChatScreenViewController
    ) -> (String, MessageCapability) -> Void {
        { [weak screen] stableID, action in
            handler(stableID, action)
            switch action {
            case .edit:
                screen?.beginEditSpotlight(for: stableID)
                screen?.focusComposer()
            case .reply:
                screen?.focusComposer()
            case .delete:   screen?.dismissKeyboard()
            case .copy:     break
            }
        }
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
                model: barModel,
                composer: composer,
                isTipDm: isTipDm
            )
            .environment(conversationController)
            .modifier(
                MeasuredBarHeight(isReplying: composer.replyTarget != nil) { height, isReplying in
                    coordinator.screen?.setBarHeight(height, replying: isReplying)
                }
            )
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
    /// Whether a reply is open, reported alongside the height. The bar's clip decides what to do
    /// with a height from the two together, so this has to arrive from the same layout pass rather
    /// than be read separately afterwards.
    let isReplying: Bool
    let report: (CGFloat, Bool) -> Void

    /// The last height reported, so the reply can be reported without one. A reply that closes does
    /// not change the bar's height — the strip stays mounted underneath while it fades — and the
    /// clip still has to be told to close over it.
    @State private var measured: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
                measured = height
                report(height, isReplying)
            }
            .onChange(of: isReplying) { _, replying in
                guard measured > 0 else { return }
                report(measured, replying)
            }
            // Sit on the host's bottom edge rather than in the middle of it. The two heights are
            // never equal mid-change: SwiftUI ramps the content's own height on its spring while the
            // constraint above chases it on another, and centring turns every point of that gap into
            // half a point of vertical travel for the whole bar. Bottom-aligned, the gap goes
            // somewhere nobody looks — the bar grows and shrinks from the top, which is the edge the
            // reply strip arrives at.
            .frame(maxHeight: .infinity, alignment: .bottom)
    }
}
