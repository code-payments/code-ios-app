//
//  ConversationTranscript.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import UIKit
import Combine
import FlipcashCore

/// A transcript entry: a date header, or a message with its position within
/// its same-sender run. Grouping never crosses a date header.
nonisolated enum ConversationTranscriptItem: Identifiable, Equatable {

    struct Position: Equatable {
        let isFromSelf: Bool
        let groupedAbove: Bool
        let groupedBelow: Bool
        let isLatestFromSelf: Bool
        /// Whether the message postdates the signed-in user's READ watermark —
        /// it has never been on screen, so it animates in this once.
        let isUnseen: Bool
    }

    case separator(Date)
    case message(ConversationMessage, Position)

    var id: String {
        switch self {
        case .separator(let date): "sep-\(date.timeIntervalSince1970)"
        case .message(let message, _): "msg-\(message.id.value)"
        }
    }

    /// Inserts a date header across `gap`-sized time gaps and computes each
    /// message's grouping within its same-sender run. `seenBoundary` is the
    /// user's READ watermark; a nil boundary means nothing was ever read.
    static func items(
        from messages: [ConversationMessage],
        selfUserID: UserID,
        seenBoundary: MessageID?,
        gap: TimeInterval = 15 * 60
    ) -> [ConversationTranscriptItem] {
        let latestFromSelfID = messages.last { $0.senderID == selfUserID }?.id
        var items: [ConversationTranscriptItem] = []

        for (index, message) in messages.enumerated() {
            let previous = index > 0 ? messages[index - 1] : nil
            let next = index + 1 < messages.count ? messages[index + 1] : nil
            let isFromSelf = message.senderID == selfUserID

            let showsSeparator: Bool
            if let previous {
                showsSeparator = message.date.timeIntervalSince(previous.date) > gap
            } else {
                showsSeparator = true
            }
            if showsSeparator {
                items.append(.separator(message.date))
            }

            let groupedAbove = !showsSeparator
                && previous.map { ($0.senderID == selfUserID) == isFromSelf } == true
            let groupedBelow = next.map {
                ($0.senderID == selfUserID) == isFromSelf
                    && $0.date.timeIntervalSince(message.date) <= gap
            } == true

            items.append(.message(message, Position(
                isFromSelf: isFromSelf,
                groupedAbove: groupedAbove,
                groupedBelow: groupedBelow,
                isLatestFromSelf: message.id == latestFromSelfID,
                // Unknown watermark (cold first run, feed not hydrated yet) →
                // treat as seen so history renders statically instead of every
                // cash card rolling its amount at once.
                isUnseen: seenBoundary.map { message.id > $0 } ?? false
            )))
        }
        return items
    }
}

/// The scrolling transcript. Born bottom-anchored; a `ScrollViewReader`
/// scrolls the newest message into view on new arrivals and as the keyboard
/// rises or falls.
struct ConversationTranscript: View {

    let messages: [ConversationMessage]
    let selfUserID: UserID
    /// The signed-in user's READ watermark. Messages past it animate in —
    /// the once-per-message "never seen" animation.
    let seenBoundary: MessageID?
    let onBackgroundTap: () -> Void

    /// New bubble scale + opacity insertion.
    private static let insertionSpring = Animation.spring(duration: 0.23, bounce: 0.27)

    /// New message sent/received — the list springs down to the newest bubble.
    private static let scrollSpring = Animation.spring(duration: 0.30, bounce: 0.12)

    /// Scroll that rides the keyboard up/down.
    private static let keyboardScrollSpring = Animation.spring(duration: 0.30, bounce: 0)

    /// Identity of the message stack; every scroll-to-bottom targets its
    /// bottom edge.
    private static let bottomAnchor = "conversation-bottom"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(items) { item in
                        switch item {
                        case .separator(let date):
                            ConversationDateSeparator(date: date)
                        case .message(let message, let position):
                            ConversationMessageRow(
                                message: message,
                                isFromSelf: position.isFromSelf,
                                groupedAbove: position.groupedAbove,
                                groupedBelow: position.groupedBelow,
                                showsDelivered: position.isLatestFromSelf,
                                animatesAmount: position.isUnseen
                            )
                            // A new bubble scales + fades in from its aligned edge.
                            .transition(
                                .scale(scale: 0.95, anchor: position.isFromSelf ? .trailing : .leading)
                                    .combined(with: .opacity)
                            )
                        }
                    }
                }
                // Every scroll-to-bottom targets the stack's bottom edge.
                .id(Self.bottomAnchor)
                .padding(.vertical, 12)
                // Tapping empty space lowers the keyboard; bubbles consume their
                // own taps (see ConversationMessageRow).
                .contentShape(Rectangle())
                .onTapGesture(perform: onBackgroundTap)
                .animation(Self.insertionSpring, value: messages.count)
            }
            .scrollDismissesKeyboard(.interactively)
            // The anchor positions the first paint at the newest message, but
            // it resolves against the lazy stack's *estimated* height — on
            // long transcripts the real layout can land mid-thread. The
            // instant scrollTo on appear (again after the first layout pass,
            // when the list is actually measured) corrects any residue.
            .defaultScrollAnchor(.bottom)
            .onAppear {
                proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
                DispatchQueue.main.async {
                    proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
                }
            }
            //   • a message arrives (sent or received) → spring down to it
            .onChange(of: messages.count) {
                scrollToBottom(proxy, animation: Self.scrollSpring)
            }
            //   • keyboard rises → ride the newest message up with it
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                scrollToBottom(proxy, animation: Self.keyboardScrollSpring)
            }
            //   • keyboard falls (swipe, tap-blank, system) → keep the thread
            //     pinned down
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                scrollToBottom(proxy, animation: Self.keyboardScrollSpring)
            }
        }
    }

    /// Scrolls the newest content into view. A thread too short to scroll
    /// no-ops and stays at the top.
    private func scrollToBottom(_ proxy: ScrollViewProxy, animation: Animation) {
        withAnimation(animation) { proxy.scrollTo(Self.bottomAnchor, anchor: .bottom) }
    }

    /// Kept on this child view (whose inputs exclude the composer draft) so
    /// keystrokes don't recompute it.
    private var items: [ConversationTranscriptItem] {
        ConversationTranscriptItem.items(from: messages, selfUserID: selfUserID, seenBoundary: seenBoundary)
    }
}
