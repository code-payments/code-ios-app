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
        case .message(let message, _): Self.rowID(for: message.id)
        }
    }

    /// The scroll identity of a message row — the single source the `ForEach` id
    /// and the programmatic `scrollTo(id:)` targets both resolve through.
    static func rowID(for messageID: MessageID) -> String {
        "msg-\(messageID.value)"
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

/// The scrolling transcript: a bottom-anchored `ScrollView`
/// (`defaultScrollAnchor(.bottom)`) that opens on the newest message and pages
/// older history in at the top.
struct ConversationTranscript: View {

    let messages: [ConversationMessage]
    let selfUserID: UserID
    /// The signed-in user's READ watermark. Messages past it animate in —
    /// the once-per-message "never seen" animation.
    let seenBoundary: MessageID?
    /// The counterpart's READ watermark + read time, driving the "Read 3:42 PM"
    /// receipt. Derived live (not captured) so it updates as they read.
    let counterpartRead: ReadReceiptState?
    /// Whether the composer is open.
    let isComposing: Bool
    let onBackgroundTap: () -> Void
    /// Whether older history may still be paged in. Keeps the invisible top
    /// trigger present, whose appearance fires `onLoadOlder`.
    let hasMoreOlder: Bool
    /// Whether an older page is in flight right now. Drives the spinner so it
    /// shows only during a fetch, not perpetually while more history exists.
    let isLoadingOlder: Bool
    let onLoadOlder: () -> Void

    /// New bubble scale + opacity insertion.
    private static let insertionSpring = Animation.spring(duration: 0.23, bounce: 0.27)

    /// Programmatic scroll target for the two moves `defaultScrollAnchor(.bottom)`
    /// can't make on its own — it only holds the bottom: riding the newest message
    /// up when the keyboard opens, and holding position when an older page prepends.
    @State private var scrollPosition = ScrollPosition()
    /// Armed when the composer opens, consumed by the next keyboard appearance.
    @State private var scrollOnKeyboard = false

    var body: some View {
        let items = ConversationTranscriptItem.items(
            from: messages,
            selfUserID: selfUserID,
            seenBoundary: seenBoundary,
            counterpartRead: counterpartRead
        )

        ScrollView {
            LazyVStack(spacing: 8) {
                // Invisible top trigger: paging fires when this scrolls into view
                // (i.e. the top is reached), never on open since it sits above the
                // newest message and is off-screen there.
                if hasMoreOlder {
                    Color.clear
                        .frame(height: 1)
                        .onAppear(perform: onLoadOlder)
                }
                // The spinner shows only while a page is actually loading — not
                // perpetually whenever more history exists — so it can't sit at the
                // top looking stuck after a page has already loaded beneath it.
                if isLoadingOlder {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
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
                            receipt: position.receipt,
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
        // Anchor content to the bottom: the transcript opens on the newest message
        // (above the composer) and stays pinned as off-screen rows realize and as
        // new messages arrive while at the bottom. The layout-level bottom anchor
        // positions from the bottom up, so it lands on the true newest message
        // regardless of how the rows above the fold are estimated.
        .defaultScrollAnchor(.bottom)
        .scrollPosition($scrollPosition)
        .scrollDismissesKeyboard(.interactively)
        // Older page prepended (oldest id moved earlier): snap the previously-oldest
        // message back to the top so the new page lands above it and the loader rides
        // off-screen, instead of the viewport pinning at offset 0 with the new
        // messages stuffed under the loader. Lets the user keep scrolling up into them.
        .onChange(of: messages.first?.id) { oldFirst, newFirst in
            guard let oldFirst, let newFirst, newFirst < oldFirst else { return }
            scrollPosition.scrollTo(id: ConversationTranscriptItem.rowID(for: oldFirst), anchor: .top)
        }
        // Arm a one-shot scroll for the next keyboard frame, so the newest message
        // rides up above the keyboard. Arming on isComposing (not the keyboard event)
        // means a cancelled back-swipe — which churns the keyboard but never reopens
        // the composer — finds the flag disarmed and can't scroll.
        .onChange(of: isComposing) { _, composing in
            if composing { scrollOnKeyboard = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            guard scrollOnKeyboard, let lastID = messages.last?.id else { return }
            scrollOnKeyboard = false
            withAnimation { scrollPosition.scrollTo(id: ConversationTranscriptItem.rowID(for: lastID), anchor: .bottom) }
        }
    }
}
