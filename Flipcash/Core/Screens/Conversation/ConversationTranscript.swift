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

/// The scrolling transcript: a bottom-anchored `ScrollView` whose newest
/// message stays in view as rows append, via `defaultScrollAnchor(.bottom)`.
struct ConversationTranscript: View {

    let messages: [ConversationMessage]
    let selfUserID: UserID
    /// The signed-in user's READ watermark. Messages past it animate in —
    /// the once-per-message "never seen" animation.
    let seenBoundary: MessageID?
    let onBackgroundTap: () -> Void

    /// New bubble scale + opacity insertion.
    private static let insertionSpring = Animation.spring(duration: 0.23, bounce: 0.27)

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
                .padding(.vertical, 12)
                // Tapping empty space lowers the keyboard; bubbles consume their own taps.
                .contentShape(Rectangle())
                .onTapGesture(perform: onBackgroundTap)
                .animation(Self.insertionSpring, value: messages.count)
            }
            // Opens at the newest message and rides new arrivals down.
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            // The keyboard rising scrolls the newest into view — which also
            // forces the lazy rows to re-realize (the layout change otherwise
            // leaves the transcript blank until a manual scroll).
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                guard let lastID = items.last?.id else { return }
                withAnimation { proxy.scrollTo(lastID, anchor: .bottom) }
            }
        }
    }

    /// Kept on this child view (whose inputs exclude the composer draft) so
    /// keystrokes don't recompute it.
    private var items: [ConversationTranscriptItem] {
        ConversationTranscriptItem.items(from: messages, selfUserID: selfUserID, seenBoundary: seenBoundary)
    }
}
