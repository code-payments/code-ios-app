//
//  PostPaymentChat.swift
//  Flipcash
//

import FlipcashCore

/// Tracks the hand-off from paying to start a chat to opening that chat, which spans the sheet's
/// dismissal and the DM record arriving over the feed in either order.
nonisolated struct PostPaymentChat: Equatable {

    /// Set when the payment lands, consumed by the sheet's dismissal.
    private(set) var didPay = false

    /// True from the sheet's dismissal until the DM's record arrives, so the push happens once and
    /// only for a chat this screen just paid for.
    private(set) var isAwaitingChat = false

    /// Records that the payment succeeded.
    mutating func paymentSucceeded() {
        didPay = true
    }

    /// Consumes the success flag and returns the chat to push now, or `nil` when the record hasn't
    /// landed yet (the push waits for it) or the screen is no longer in front (the push is dropped).
    mutating func sheetDismissed(dmID: ConversationID?, isScreenInFront: Bool) -> ConversationID? {
        guard didPay else { return nil }
        didPay = false
        guard isScreenInFront else { return nil }
        guard let dmID else {
            isAwaitingChat = true
            return nil
        }
        return dmID
    }

    /// Returns the chat to push when its record arrives while one is awaited.
    mutating func dmArrived(_ dmID: ConversationID?, isScreenInFront: Bool) -> ConversationID? {
        guard isAwaitingChat, let dmID else { return nil }
        isAwaitingChat = false
        return isScreenInFront ? dmID : nil
    }

    /// Stops waiting for a record that never came.
    mutating func gaveUp() {
        isAwaitingChat = false
    }
}
