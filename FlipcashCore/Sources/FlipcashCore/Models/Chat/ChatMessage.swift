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
    /// The row above has the same author — the name above this row is suppressed, so a run reads as
    /// one speaker. Attribution only: the inner corner and the row gap are the bubble-run flags' job.
    public let isContinuationFromPrevious: Bool
    /// The row below has the same author — the run's single gutter face sits on the row that closes
    /// it, not on this one. Attribution only, as above.
    public let isContinuedByNext: Bool
    /// The bubble above is part of the same *bubble* run: flatten the inner top corner. Separate
    /// from the author run because a bare emoji row breaks the chrome without breaking attribution.
    public let joinsBubbleAbove: Bool
    /// The bubble below is part of the same bubble run: flatten the inner bottom corner, and take
    /// the tight row gap.
    public let joinsBubbleBelow: Bool
    /// The body is one to three emoji and nothing else. Derived from the text at map time the way
    /// `linkPreview` is. `rendersAsLargeEmoji` is what decides the rendering — this flag is just the
    /// body test, so a reply or a link row can carry it and still draw a bubble.
    public let isEmojiOnly: Bool
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
    /// Who wrote this row, in a transcript that names its authors. `nil` in a DM, where the two
    /// sides are already told apart by which edge the bubble hugs, and `nil` for the viewer's own
    /// rows in any transcript.
    public let author: ChatAuthor?
    /// Whether the transcript this row belongs to names its authors — a group chat. True on every
    /// row of one, including the viewer's own and a row whose sender no roster can name, so the
    /// avatar gutter is a property of the transcript rather than of whichever rows drew a face.
    public let isAttributedTranscript: Bool

    /// Whether this row draws as bare, enlarged emoji instead of a bubble: an emoji-only text body
    /// with nothing else in the bubble to hold. A reply's quote panel and a link row's preview both
    /// live inside the bubble and have no standalone layout, so either one keeps the chrome.
    public var rendersAsLargeEmoji: Bool {
        guard isEmojiOnly, quote == nil, linkPreview == nil else { return false }
        switch content {
        case .text:           return true
        case .cash, .deleted: return false
        }
    }

    public init(
        id: String,
        content: Content,
        sender: Sender,
        isContinuationFromPrevious: Bool = false,
        isContinuedByNext: Bool = false,
        joinsBubbleAbove: Bool = false,
        joinsBubbleBelow: Bool = false,
        isEmojiOnly: Bool = false,
        receipt: ChatReceipt? = nil,
        linkPreview: LinkPreview? = nil,
        isEdited: Bool = false,
        actions: [MessageCapability] = [],
        quote: ChatQuote? = nil,
        author: ChatAuthor? = nil,
        isAttributedTranscript: Bool = false
    ) {
        self.id = id
        self.content = content
        self.sender = sender
        self.isContinuationFromPrevious = isContinuationFromPrevious
        self.isContinuedByNext = isContinuedByNext
        self.joinsBubbleAbove = joinsBubbleAbove
        self.joinsBubbleBelow = joinsBubbleBelow
        self.isEmojiOnly = isEmojiOnly
        self.receipt = receipt
        self.linkPreview = linkPreview
        self.isEdited = isEdited
        self.actions = actions
        self.quote = quote
        self.author = author
        self.isAttributedTranscript = isAttributedTranscript
    }

    /// Convenience for text rows.
    public init(
        id: String,
        text: String,
        sender: Sender,
        isContinuationFromPrevious: Bool = false,
        isContinuedByNext: Bool = false,
        joinsBubbleAbove: Bool = false,
        joinsBubbleBelow: Bool = false,
        isEmojiOnly: Bool = false,
        receipt: ChatReceipt? = nil,
        linkPreview: LinkPreview? = nil,
        isEdited: Bool = false,
        actions: [MessageCapability] = [],
        quote: ChatQuote? = nil,
        author: ChatAuthor? = nil,
        isAttributedTranscript: Bool = false
    ) {
        self.init(
            id: id,
            content: .text(text),
            sender: sender,
            isContinuationFromPrevious: isContinuationFromPrevious,
            isContinuedByNext: isContinuedByNext,
            joinsBubbleAbove: joinsBubbleAbove,
            joinsBubbleBelow: joinsBubbleBelow,
            isEmojiOnly: isEmojiOnly,
            receipt: receipt,
            linkPreview: linkPreview,
            isEdited: isEdited,
            actions: actions,
            quote: quote,
            author: author,
            isAttributedTranscript: isAttributedTranscript
        )
    }
}

/// The writer of an incoming row in a transcript that names its authors — a group chat. Display
/// data only: the name as it goes above the bubble, and what the avatar gutter needs to find a
/// picture.
///
/// The picture's bytes are deliberately not here. These values are diffed on every transcript tick
/// and written to the shared app-group container for the notification preview, so image data in
/// them would cost a byte-compare per row and leave thumbnails in the clear on disk. ``id`` is what
/// the transcript looks the bytes up by, and what tints the name.
public struct ChatAuthor: Hashable, Sendable, Codable {

    /// The author's user id — the avatar lookup key, and the seed `ComplementaryPalette` derives
    /// the name's per-person tint from.
    public let id: UserID

    /// The name above the run. Empty when the roster does not name this sender; the row then draws
    /// no name label rather than a placeholder.
    public let name: String

    /// BlurHash of the author's avatar, drawn until the bytes arrive, or nil when they have no
    /// picture.
    public let blurhash: String?

    public init(id: UserID, name: String, blurhash: String? = nil) {
        self.id = id
        self.name = name
        self.blurhash = blurhash
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
