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

    var body: some View {
        let items = ConversationTranscriptItem.items(
            from: messages,
            selfUserID: selfUserID,
            seenBoundary: seenBoundary,
            counterpartRead: counterpartRead
        )

        ChatScrollView {
            LazyVStack(spacing: 8) {
                if isLoadingOlder {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                ForEach(items) { ConversationTranscriptRow(item: $0) }
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
private nonisolated let bottomThreshold: CGFloat = 80

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
    @ViewBuilder let content: Content

    @State private var scrollPosition = ScrollPosition(edge: .bottom)
    @State private var isAtBottom = true
    /// Whether to keep snapping to the newest message as content changes. Stays on
    /// — pinning the view to the bottom through the async first load, the full
    /// history paging in, and sent/received messages — until the user drags away,
    /// and re-engages when they scroll back to the bottom. Tracked separately from
    /// `isAtBottom`, which the async first load flips false at the wrong moment and
    /// would otherwise land the open mid-list.
    @State private var followsBottom = true
    /// Whether the scroll view is settled (not interacting, decelerating, or animating).
    /// The follow re-engages only while idle, so the transient "at bottom" flip a keyboard
    /// or momentum settle produces mid-scroll can't re-arm it.
    @State private var isScrollIdle = true

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            content
        }
        .scrollPosition($scrollPosition)
        // Open at the newest message using SwiftUI's first-class chat anchor.
        .modifier(InitialBottomAnchor())
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
            // Re-assert the bottom on any content-height change while following — not just
            // growth. The mount-time landing targets the LazyVStack's *estimated* height;
            // when its rows measure and the estimate corrects downward, a growth-only check
            // misses it and leaves the open parked in empty space (the sporadic blank). The
            // container-stable guard still skips the keyboard raise/lower, which momentarily
            // misreports the content height. The re-scroll realizes the bottom rows and the
            // height then settles, so this converges rather than looping.
            let containerStable = new.containerHeight == old.containerHeight
            if followsBottom, containerStable, new.contentHeight != old.contentHeight {
                scrollPosition.scrollTo(edge: .bottom)
            }
        }
        .onScrollPhaseChange { _, newPhase in
            isScrollIdle = newPhase == .idle
            if newPhase == .interacting { followsBottom = false }
        }
        .onAppear {
            scrollPosition.scrollTo(edge: .bottom)
        }
        .overlay(alignment: .bottom) {
            Group {
                if !isAtBottom {
                    scrollToBottomButton
                        .padding(.bottom, 8)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.3), value: isAtBottom)
        }
    }

    private var scrollToBottomButton: some View {
        Button {
            withAnimation(.spring(duration: 0.3)) {
                scrollPosition.scrollTo(edge: .bottom)
            }
        } label: {
            Image(systemName: "arrow.down")
                .font(.body.weight(.semibold))
                .frame(width: 32, height: 32)
                .contentShape(.interaction, Circle())
        }
        .buttonStyle(.plain)
        .background(.regularMaterial, in: Circle())
    }
}

/// Pins the scroll view's first frame to the newest message via SwiftUI's chat
/// anchor (iOS 18+). Scoped to `.initialOffset`, so it only sets the opening
/// position and leaves the keyboard- and growth-driven follow to manage every
/// later scroll. Below iOS 18 the initial `ScrollPosition(edge: .bottom)` does it.
private struct InitialBottomAnchor: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content.defaultScrollAnchor(.bottom, for: .initialOffset)
        } else {
            content
        }
    }
}
