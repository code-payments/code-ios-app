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
/// many of those rows are already on screen. A message that arrives while it holds adds to it. After
/// the drag it is the live count: inbound messages past the viewer's read pointer.
@MainActor
@Observable
final class JumpBadgeCount {

    /// True until the reader's first drag or fling after the open. Programmatic scrolls (the opening
    /// position, auto-scroll on a new message, the jump button) don't clear it.
    private(set) var isFrozen = true

    @ObservationIgnored private let controller: ConversationController
    @ObservationIgnored private let conversationID: ConversationID
    /// The unread divider's count at open; 0 when the chat opened without one.
    @ObservationIgnored private let openingCount: Int
    /// The newest inbound id at open; inbound messages past it arrived on this visit.
    @ObservationIgnored private let arrivalMark: MessageID

    /// Pass the boundary resolved at open, before the opening read report moves the pointer.
    init(controller: ConversationController, conversationID: ConversationID, boundary: UnreadBoundary) {
        self.controller = controller
        self.conversationID = conversationID
        self.openingCount = boundary.count ?? 0
        self.arrivalMark = controller.newestInboundMessageID(in: conversationID) ?? MessageID(value: 0)
    }

    /// The number to show; the badge hides at zero.
    var count: Int {
        guard isFrozen else { return controller.unreadBelowCount(in: conversationID) }
        _ = controller.messageRevision   // observe: re-count when an inbound message lands
        return openingCount + controller.inboundMessageCount(after: arrivalMark, in: conversationID)
    }

    /// Ends the freeze; the badge follows the live count from here on.
    func userDidScroll() {
        guard isFrozen else { return }
        isFrozen = false
    }
}
