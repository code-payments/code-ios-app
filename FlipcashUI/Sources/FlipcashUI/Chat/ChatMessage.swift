//
//  ChatMessage.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// A single rendered chat row — pure data, no behavior. The whole chat UI is driven by
/// values like this; the views know nothing about the network, the database, or how the
/// message was produced. Everything they need to draw is here, already display-ready.
public struct ChatMessage: Hashable, Sendable, Identifiable {

    /// Which side of the transcript the message sits on.
    public enum Sender: Hashable, Sendable {
        case me
        case other
    }

    /// What the row renders. Display-ready — the cash case carries pre-formatted strings, not a
    /// money type, so the cell stays dumb.
    public enum Content: Hashable, Sendable {
        case text(String)
        case cash(ChatCashContent)
    }

    /// Outgoing delivery state shown beneath the bubble. `.normal` renders the receipt line (or
    /// nothing); `.sending`/`.failed` render their own status in the receipt slot.
    public enum DeliveryState: Hashable, Sendable {
        case normal
        case sending
        case failed
    }

    public let id: String
    public let content: Content
    public let sender: Sender
    /// The row above is the same sender — tighten the spacing and flatten the inner top
    /// corner so a same-sender run reads as one column.
    public let isContinuationFromPrevious: Bool
    /// The row below is the same sender — flatten the inner bottom corner.
    public let isContinuedByNext: Bool
    /// The delivery line shown under this bubble ("Delivered" / "Read 3:42 PM"), or nil for every
    /// message except the user's latest sent one. Carried on the message — not a separate transcript
    /// row — so a send stays a clean insert instead of tearing the line down and rebuilding it.
    public let receipt: String?
    /// Whether this outgoing row is in flight or failed; drives the sending/failed indicator in the
    /// receipt slot. `.normal` for received messages and confirmed sends.
    public let deliveryState: DeliveryState

    public init(
        id: String,
        content: Content,
        sender: Sender,
        isContinuationFromPrevious: Bool = false,
        isContinuedByNext: Bool = false,
        receipt: String? = nil,
        deliveryState: DeliveryState = .normal
    ) {
        self.id = id
        self.content = content
        self.sender = sender
        self.isContinuationFromPrevious = isContinuationFromPrevious
        self.isContinuedByNext = isContinuedByNext
        self.receipt = receipt
        self.deliveryState = deliveryState
    }

    /// Convenience for text rows.
    public init(
        id: String,
        text: String,
        sender: Sender,
        isContinuationFromPrevious: Bool = false,
        isContinuedByNext: Bool = false,
        receipt: String? = nil,
        deliveryState: DeliveryState = .normal
    ) {
        self.init(
            id: id,
            content: .text(text),
            sender: sender,
            isContinuationFromPrevious: isContinuationFromPrevious,
            isContinuedByNext: isContinuedByNext,
            receipt: receipt,
            deliveryState: deliveryState
        )
    }
}

/// A cash payment row's display data — already formatted, so the cell renders strings + images.
public struct ChatCashContent: Hashable, Sendable {
    /// The amount in the user's currency, formatted for display (e.g. "$5.00").
    public let amount: String
    /// The token's display name (e.g. "Cash").
    public let token: String
    /// Asset-catalog name of the currency flag shown beside the amount (e.g. "us", "USDC").
    public let flagImageName: String?
    /// Remote icon for a launchpad token shown beside its name; nil for plain cash (USDF).
    public let iconURL: URL?

    public init(amount: String, token: String, flagImageName: String? = nil, iconURL: URL? = nil) {
        self.amount = amount
        self.token = token
        self.flagImageName = flagImageName
        self.iconURL = iconURL
    }
}
