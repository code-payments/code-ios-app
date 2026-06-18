//
//  ConversationTranscript.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashCore

/// The delivery receipt shown under the user's latest sent message: `delivered`
/// until the counterpart reads it, then `read` with the time they read (nil when
/// the server omits the timestamp).
nonisolated enum MessageReceipt: Equatable {
    case delivered
    case read(Date?)
}

/// A transcript entry: a date header, or a message with its position within
/// its same-sender run. Grouping never crosses a date header.
nonisolated enum ConversationTranscriptItem: Identifiable, Equatable {

    struct Position: Equatable {
        let isFromSelf: Bool
        let groupedAbove: Bool
        let groupedBelow: Bool
        /// The receipt to show beneath this message — set only on the user's
        /// latest sent message, `nil` everywhere else.
        let receipt: MessageReceipt?
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
        counterpartRead: ReadReceiptState? = nil,
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

            // Receipt only on the latest sent message: Read (with the
            // counterpart's read time) once their pointer reaches it, else
            // Delivered. nil counterpart pointer → Delivered, matching the
            // prior behaviour before they've read anything.
            let receipt: MessageReceipt? = message.id == latestFromSelfID
                ? (counterpartRead.map { $0.pointer >= message.id ? .read($0.date) : .delivered } ?? .delivered)
                : nil

            items.append(.message(message, Position(
                isFromSelf: isFromSelf,
                groupedAbove: groupedAbove,
                groupedBelow: groupedBelow,
                receipt: receipt,
                // Unknown watermark (cold first run, feed not hydrated yet) →
                // treat as seen so history renders statically instead of every
                // cash card rolling its amount at once.
                isUnseen: seenBoundary.map { message.id > $0 } ?? false
            )))
        }
        return items
    }
}

/// The chat transcript: a bottom-anchored `ChatScrollView` holding the full
/// message history, so scrolling up reaches the first message.
struct ConversationTranscript: View {

    let messages: [ConversationMessage]
    let selfUserID: UserID
    /// The signed-in user's READ watermark. Messages past it animate in —
    /// the once-per-message "never seen" animation.
    let seenBoundary: MessageID?
    /// The counterpart's READ watermark + read time, driving the "Read 3:42 PM"
    /// receipt. Derived live (not captured) so it updates as they read.
    let counterpartRead: ReadReceiptState?
    /// Whether an older page is in flight right now. Drives the top spinner while
    /// the full history pages in behind the user.
    let isLoadingOlder: Bool
    let onBackgroundTap: () -> Void

    /// How many of the newest rows render eagerly. Large enough to always exceed a
    /// viewport so the open never lands on an unrealized row.
    private static let eagerTailCount = 40

    var body: some View {
        let items = ConversationTranscriptItem.items(
            from: messages,
            selfUserID: selfUserID,
            seenBoundary: seenBoundary,
            counterpartRead: counterpartRead
        )
        // Newest run eager, older history lazy: a LazyVStack jumped to its bottom never
        // materializes those rows (the open goes blank), so a non-lazy tail guarantees
        // the open lands on rendered rows.
        let tailStart = max(0, items.count - Self.eagerTailCount)
        let history = items[..<tailStart]
        let tail = items[tailStart...]

        ChatScrollView(bottomID: items.last?.id) {
            VStack(spacing: 8) {
                LazyVStack(spacing: 8) {
                    if isLoadingOlder {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    ForEach(history) { ConversationTranscriptRow(item: $0) }
                }
                ForEach(tail) { ConversationTranscriptRow(item: $0) }
            }
            .padding(.vertical, 12)
            // Tapping empty space lowers the keyboard; bubbles consume their own taps.
            .contentShape(Rectangle())
            .onTapGesture(perform: onBackgroundTap)
        }
    }
}

/// One transcript row: a date separator or a message bubble.
struct ConversationTranscriptRow: View {
    let item: ConversationTranscriptItem

    var body: some View {
        switch item {
        case .separator(let date):
            ConversationDateSeparator(date: date)
        case .message(let message, let position):
            ConversationMessageRow(
                message: message,
                isFromSelf: position.isFromSelf,
                groupedAbove: position.groupedAbove,
                groupedBelow: position.groupedBelow,
                receipt: position.receipt,
                animatesAmount: position.isUnseen
            )
        }
    }
}

/// Distance from the bottom edge (in points) within which the scroll view is
/// considered "at the bottom" for auto-scroll purposes.
private nonisolated let bottomThreshold: CGFloat = 90

/// The transcript's container and content heights, sampled together so the follow
/// can tell genuine content growth from a keyboard-driven container resize.
private struct ScrollMetrics: Equatable {
    let containerHeight: CGFloat
    let contentHeight: CGFloat
}

/// A bottom-anchored scroll view for chat-style content: it opens pinned to the
/// newest message and keeps following the bottom as content arrives, until the
/// user scrolls away.
struct ChatScrollView<Content: View>: View {
    /// Identity of the newest row. Scrolled to by identity, not the content edge,
    /// because a `LazyVStack` won't materialize its bottom rows for a far offset jump.
    let bottomID: String?
    @ViewBuilder let content: Content

    @State private var isAtBottom = true
    /// Whether to keep snapping to the newest message as content changes — on until
    /// the user drags away, re-engaging when they scroll back to the bottom. Kept
    /// separate from `isAtBottom`, which the async first load flips false mid-open.
    @State private var followsBottom = true
    /// Whether the scroll view is settled (not interacting, decelerating, or animating).
    /// The follow re-engages only while idle, so the transient "at bottom" flip a keyboard
    /// or momentum settle produces mid-scroll can't re-arm it.
    @State private var isScrollIdle = true

    init(bottomID: String?, @ViewBuilder content: () -> Content) {
        self.bottomID = bottomID
        self.content = content()
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                content
            }
            // Anchor the opening offset to the bottom at layout time; an onAppear scroll
            // races a cached conversation's full content and can land at the top. Scoped
            // to `.initialOffset` — the follow below owns every later scroll.
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            // Drag the transcript down to lower the keyboard, the way Messages does;
            // the composer's focus-loss handler then collapses it back to the action bar.
            .scrollDismissesKeyboard(.interactively)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                let bottomEdge = geometry.contentOffset.y + geometry.containerSize.height
                return bottomEdge >= geometry.contentSize.height - bottomThreshold
            } action: { _, newValue in
                isAtBottom = newValue
                if newValue, isScrollIdle { followsBottom = true }
            }
            .onScrollGeometryChange(for: ScrollMetrics.self) { geometry in
                ScrollMetrics(containerHeight: geometry.containerSize.height,
                              contentHeight: geometry.contentSize.height)
            } action: { old, new in
                // Re-pin to the newest row as content grows while following (a message
                // arrives, history pages in). The container-stable guard skips the keyboard
                // resize, and growth-only avoids yanking the user down on a row's shrink.
                let containerStable = new.containerHeight == old.containerHeight
                if followsBottom, containerStable, new.contentHeight > old.contentHeight {
                    proxy.scrollToNewest(bottomID)
                }
            }
            .onScrollPhaseChange { _, newPhase in
                isScrollIdle = newPhase == .idle
                if newPhase == .interacting { followsBottom = false }
            }
            .overlay(alignment: .bottom) {
                Group {
                    if !isAtBottom {
                        ScrollToNewestButton { proxy.scrollToNewest(bottomID, animated: true) }
                            .padding(.bottom, 8)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.spring(duration: 0.3), value: isAtBottom)
            }
        }
    }
}

private extension ScrollViewProxy {
    /// Scrolls to the chat's newest row by identity (no-op when empty), which makes the
    /// `LazyVStack` realize it where an offset jump would not.
    func scrollToNewest(_ id: String?, animated: Bool = false) {
        guard let id else { return }
        if animated {
            withAnimation(.spring(duration: 0.3)) { scrollTo(id, anchor: .bottom) }
        } else {
            scrollTo(id, anchor: .bottom)
        }
    }
}

/// The circular "scroll to newest" affordance shown once the user has scrolled up.
private struct ScrollToNewestButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.down")
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(.interaction, Circle())
        }
        .buttonStyle(.plain)
        .background(.regularMaterial, in: Circle())
    }
}
