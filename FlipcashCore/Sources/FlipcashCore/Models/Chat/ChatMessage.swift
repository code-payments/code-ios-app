//
//  ChatMessage.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// A single rendered chat row — pure data, no behavior. The whole chat UI is driven by
/// values like this; the views know nothing about the network, the database, or how the
/// message was produced. Everything they need to draw is here, already display-ready.
public struct ChatMessage: Hashable, Sendable, Codable, Identifiable {

    /// Which side of the transcript the message sits on.
    public enum Sender: Hashable, Sendable, Codable {
        case me
        case other
    }

    /// What the row renders. Display-ready — the cash case carries pre-formatted strings, not a
    /// money type, so the cell stays dumb.
    public enum Content: Hashable, Sendable, Codable {
        case text(String)
        case cash(ChatCashContent)
        /// A deleted message's placeholder copy, already resolved for the viewer — "You deleted this
        /// message" or "This message was deleted". The mapper decides which; the view just draws it.
        case deleted(String)
    }

    public let id: String
    public let content: Content
    public let sender: Sender
    /// The row above is the same sender — tighten the spacing and flatten the inner top
    /// corner so a same-sender run reads as one column.
    public let isContinuationFromPrevious: Bool
    /// The row below is the same sender — flatten the inner bottom corner.
    public let isContinuedByNext: Bool
    /// The status line shown under this bubble, or nil when the row carries none. Carried on the
    /// message — not a separate transcript row — so a send stays a clean insert instead of tearing
    /// the line down and rebuilding it.
    public let receipt: ChatReceipt?
    /// Whether this row failed to send: turns the status line red and makes the row tappable to retry.
    /// Other states (sending, delivered, received) render the same.
    public var isFailed: Bool { receipt?.isFailed ?? false }
    /// The web link this text row contains, or nil when it carries none — marks the row to render as
    /// tappable text. Derived from the text at map time (not stored/sent) — cash rows never carry one.
    public let linkPreview: LinkPreview?
    /// Whether to draw the muted "Edited" marker after the body.
    public let isEdited: Bool
    /// What the context menu offers for this row, already ordered. Empty means no menu.
    public let actions: [MessageCapability]
    /// The original this row replies to, already resolved for display, or `nil` when the row is
    /// not a reply.
    public let quote: ChatQuote?

    public init(
        id: String,
        content: Content,
        sender: Sender,
        isContinuationFromPrevious: Bool = false,
        isContinuedByNext: Bool = false,
        receipt: ChatReceipt? = nil,
        linkPreview: LinkPreview? = nil,
        isEdited: Bool = false,
        actions: [MessageCapability] = [],
        quote: ChatQuote? = nil
    ) {
        self.id = id
        self.content = content
        self.sender = sender
        self.isContinuationFromPrevious = isContinuationFromPrevious
        self.isContinuedByNext = isContinuedByNext
        self.receipt = receipt
        self.linkPreview = linkPreview
        self.isEdited = isEdited
        self.actions = actions
        self.quote = quote
    }

    /// Convenience for text rows.
    public init(
        id: String,
        text: String,
        sender: Sender,
        isContinuationFromPrevious: Bool = false,
        isContinuedByNext: Bool = false,
        receipt: ChatReceipt? = nil,
        linkPreview: LinkPreview? = nil,
        isEdited: Bool = false,
        actions: [MessageCapability] = [],
        quote: ChatQuote? = nil
    ) {
        self.init(
            id: id,
            content: .text(text),
            sender: sender,
            isContinuationFromPrevious: isContinuationFromPrevious,
            isContinuedByNext: isContinuedByNext,
            receipt: receipt,
            linkPreview: linkPreview,
            isEdited: isEdited,
            actions: actions,
            quote: quote
        )
    }
}

/// A cash payment row's display data — already formatted, so the cell renders strings + images.
public struct ChatCashContent: Hashable, Sendable, Codable {
    /// The amount in the user's currency, formatted for display (e.g. "$5.00").
    public let amount: String
    /// The token's display name (e.g. "Cash").
    public let token: String
    /// Asset-catalog name of the currency flag shown beside the amount (e.g. "us", "USDC").
    public let flagImageName: String?
    /// Remote icon for a launchpad token shown beside its name; nil for plain cash (USDF).
    public let iconURL: URL?
    /// Whether the payment was a tip, which selects the caption verb ("tipped" vs "sent").
    public let isTip: Bool

    public init(amount: String, token: String, flagImageName: String? = nil, iconURL: URL? = nil, isTip: Bool = false) {
        self.amount = amount
        self.token = token
        self.flagImageName = flagImageName
        self.iconURL = iconURL
        self.isTip = isTip
    }

    /// The caption shown above the amount on a cash card, selected by side and tip vs. plain send.
    public static func caption(isFromSelf: Bool, isTip: Bool) -> String {
        switch (isFromSelf, isTip) {
        case (true, false):  "You sent"
        case (false, false): "You received"
        case (true, true):   "You tipped"
        case (false, true):  "You received a tip"
        }
    }
}
