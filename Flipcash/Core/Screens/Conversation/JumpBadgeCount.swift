//
//  JumpBadgeCount.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Observation
import FlipcashCore

/// The count on the jump-to-bottom badge for one visit to a chat.
///
/// It opens equal to the unread divider's count and holds there until the first user drag, however
/// many of those rows are already on screen. An inbound message that arrives after the opening load
/// has landed adds to it. After the drag it is the live count: inbound messages past the viewer's
/// read pointer. A confirmed own send also ends the hold, since the viewer has caught up.
@MainActor
@Observable
final class JumpBadgeCount {

    @ObservationIgnored private let controller: ConversationController
    @ObservationIgnored private let conversationID: ConversationID
    /// The unread divider's count at open; 0 when the chat opened without one.
    @ObservationIgnored private let openingCount: Int
    /// The viewer's read pointer at open, before the opening read report moves it.
    @ObservationIgnored private let pointerAtOpen: MessageID?
    /// Own sends already confirmed at open; a rise past it releases the hold.
    @ObservationIgnored private let sendsAtOpen: Int
    /// Inbound messages past this id arrived on this visit. Nil until the opening load has landed.
    @ObservationIgnored private var arrivalCutoff: MessageID?
    private var didScroll = false

    /// Pass the boundary resolved at open, before the opening read report moves the pointer.
    init(controller: ConversationController, conversationID: ConversationID, boundary: UnreadBoundary) {
        self.controller = controller
        self.conversationID = conversationID
        self.openingCount = boundary.count ?? 0
        self.pointerAtOpen = controller.readThrough(for: conversationID)
        self.sendsAtOpen = controller.confirmedOwnSendCounts[conversationID] ?? 0
    }

    /// True until the reader's first drag or fling after the open, or the viewer's own send is
    /// confirmed. Programmatic scrolls (the opening position, auto-scroll on a new message, the jump
    /// button) don't clear it.
    var isFrozen: Bool {
        !didScroll && (controller.confirmedOwnSendCounts[conversationID] ?? 0) == sendsAtOpen
    }

    /// The number to show; the badge hides at zero.
    var count: Int {
        guard isFrozen else { return controller.unreadBelowCount(in: conversationID) }
        _ = controller.messageRevision   // observe: re-count when an inbound message lands
        guard let arrivalCutoff else { return openingCount }
        return openingCount + controller.inboundMessageCount(after: arrivalCutoff, in: conversationID)
    }

    /// Marks the opening page load as landed, so the history it brought in doesn't count as arrivals.
    /// Later calls do nothing.
    func openingLoadLanded() {
        guard arrivalCutoff == nil else { return }
        let newest = controller.newestInboundMessageID(in: conversationID)
        arrivalCutoff = [pointerAtOpen, newest].compactMap { $0 }.max() ?? MessageID(value: 0)
    }

    /// Ends the freeze; the badge follows the live count from here on.
    func userDidScroll() {
        guard !didScroll else { return }
        didScroll = true
    }
}
