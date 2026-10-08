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
        /// A message this client cannot display — today, an encrypted one it cannot decrypt. Drawn
        /// as a dashed "This message can't be displayed" bubble with `hint` beneath it.
        case unavailable(UnavailableHint)
        /// A shared profile, drawn as a card with a Share button. The card carries only the
        /// handle's link; the name and picture are looked up by the view, as a link card's are.
        case shareProfile(LinkCard.User)
        /// A photo, drawn from its blob once a download URL is resolved and from its BlurHash until then.
        case media(ChatMediaContent)
    }

    /// The line under an unavailable message's bubble, chosen by why it can't be shown.
    public enum UnavailableHint: Hashable, Sendable, Codable {
        /// A newer client can read it: "Update Flipcash to see it".
        case updateApp
        /// It failed to decrypt and only a resend can fix it: "Ask {first name} to send it again".
        case askToResend(firstName: String)
        /// The viewer's own message failed to decrypt: "Try sending it again".
        case resend

        /// The hint's copy.
        public var text: String {
            switch self {
            case .updateApp: "Update Flipcash to see it"
            case .askToResend(let firstName): "Ask \(firstName) to send it again"
            case .resend: "Try sending it again"
            }
        }

        /// The hint under a message that failed to decrypt for `failure`, sent by the viewer or by
        /// `senderName`.
        public static func decryptFailure(
            _ failure: ConversationMessage.DecryptFailure?,
            isFromSelf: Bool,
            senderName: String
        ) -> Self {
            switch failure {
            case .unsupported, nil:
                return .updateApp
            case .authentication:
                if isFromSelf { return .resend }
                let firstName = senderName.split(separator: " ").first.map(String.init) ?? ""
                return .askToResend(firstName: firstName.isEmpty ? "them" : firstName)
            }
        }
    }

    /// The bubble copy for an unavailable message.
    public static let unavailableCopy = "This message can\u{2019}t be displayed"

    public let id: String
    /// The server's id for the message this row draws, or nil while the send is still pending. A
    /// row without one can never count toward the viewer's READ pointer.
    public let serverID: MessageID?
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
    /// Which piece of its message this row draws, for a message split into rows around its link
    /// card, or nil for a row that is the whole of its message.
    public let part: ChatMessagePart?
    /// The reaction pills under the bubble, in display order.
    public let reactions: [ReactionPill]
    /// The emoji the viewer is shown reacting with; the reaction strip highlights these.
    public let selfReactions: [SelfReaction]
    /// Whether the viewer may add or remove a reaction — false for someone previewing a group they
    /// have not joined. They still see the pills other members left; the trailing "+" is withheld
    /// and a tap on an existing pill is inert, but a long-press still opens the reactors sheet.
    public let canReact: Bool
    /// Whether this is the viewer's own row that the server has not confirmed — still sending, or
    /// failed. Only an earlier-confirmed row's `receipt` is withheld, so a nil receipt doesn't say this.
    public let isUnsent: Bool

    /// The id of the message this row draws some or all of. Every action that means the message
    /// rather than the row — the menu, a reply swipe, retry, a jump to a quoted original — goes by
    /// this, so a split message answers the same from any of its rows.
    public var messageID: String { part?.messageID ?? id }

    /// Whether this row draws as bare, enlarged emoji instead of a bubble: an emoji-only text body
    /// with nothing else in the bubble to hold. A reply's quote panel and a link row's preview both
    /// live inside the bubble and have no standalone layout, so either one keeps the chrome.
    public var rendersAsLargeEmoji: Bool {
        guard isEmojiOnly, quote == nil, linkPreview == nil else { return false }
        switch content {
        case .text:           return true
        case .cash, .deleted, .unavailable, .shareProfile, .media: return false
        }
    }

    /// Whether this row draws as the link card on its own, with no bubble behind it.
    ///
    /// The card is already a surface with its own rounded shape, so a bubble behind it would draw
    /// a second, slightly larger card around the first. The transcript gives a carded link a row of
    /// its own and the sender's words the rows around it, so a row that carries a card is the card —
    /// a reply or an edited message included, whose quote and "Edited" marker stand outside it.
    /// A web card is the exception: it draws inside the text bubble, under the sender's words.
    public var rendersAsBareLinkCard: Bool {
        if case .web = linkPreview?.card { return false }
        return linkPreview?.card != nil
    }

    /// Whether a long-press on this row should offer the reaction strip above the context menu.
    /// False for a deleted message (a tombstone keeps whatever pills it has, but there is nothing
    /// left to add a new one to) and for the user's own message still in flight — the server has
    /// nothing to record a reaction against until the send lands. A row with no context menu at all
    /// never reaches this check, since the menu itself is what hosts the strip.
    /// A redacted photo keeps its reactions hidden, so it offers no strip to add one either.
    public var offersReactionStrip: Bool {
        switch content {
        case .deleted, .unavailable:
            return false
        case .media(let media) where media.isRedacted:
            return false
        case .text, .cash, .shareProfile, .media:
            return !isUnsent
        }
    }

    /// Whether a double tap on this row's bubble brings up the reaction strip on its own. Cash and
    /// profile cards and bare link cards keep their instant single tap instead.
    public var takesDoubleTapReaction: Bool {
        guard offersReactionStrip, !rendersAsBareLinkCard else { return false }
        switch content {
        case .text, .media:                                 return true
        case .cash, .deleted, .unavailable, .shareProfile:  return false
        }
    }

    public init(
        id: String,
        serverID: MessageID? = nil,
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
        isAttributedTranscript: Bool = false,
        part: ChatMessagePart? = nil,
        reactions: [ReactionPill] = [],
        selfReactions: [SelfReaction] = [],
        canReact: Bool = true,
        isUnsent: Bool = false
    ) {
        self.id = id
        self.serverID = serverID
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
        self.part = part
        self.reactions = reactions
        self.selfReactions = selfReactions
        self.canReact = canReact
        self.isUnsent = isUnsent
    }

    /// Convenience for text rows.
    public init(
        id: String,
        serverID: MessageID? = nil,
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
        isAttributedTranscript: Bool = false,
        part: ChatMessagePart? = nil,
        reactions: [ReactionPill] = [],
        selfReactions: [SelfReaction] = [],
        canReact: Bool = true,
        isUnsent: Bool = false
    ) {
        self.init(
            id: id,
            serverID: serverID,
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
            isAttributedTranscript: isAttributedTranscript,
            part: part,
            reactions: reactions,
            selfReactions: selfReactions,
            canReact: canReact,
            isUnsent: isUnsent
        )
    }
}

/// One row of a message the transcript split around its link card: the text before the link, the
/// card, or the text after it.
public struct ChatMessagePart: Hashable, Sendable, Codable {

    public enum Kind: String, Hashable, Sendable, Codable {
        case leadingText
        case card
        case trailingText
    }

    /// The stable id of the message the row belongs to.
    public let messageID: String
    public let kind: Kind
    /// The message's whole text, so Copy from any of its rows copies what the sender wrote.
    public let messageText: String

    public init(messageID: String, kind: Kind, messageText: String) {
        self.messageID = messageID
        self.kind = kind
        self.messageText = messageText
    }

    /// The row's id: the message's, qualified by the part, so every row of one message is unique.
    public var rowID: String { "\(messageID)#\(kind.rawValue)" }
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

/// A photo row's display data: what the bubble needs to size itself and draw a placeholder before
/// any bytes arrive. The download URL and a pending row's local image stay outside this value — a
/// URL is signed and minted per fetch, and an image is not `Codable` — and reach the cell at
/// configure time instead.
public struct ChatMediaContent: Hashable, Sendable, Codable {
    /// The photo's blob, or nil for a pending row whose upload has not produced one yet.
    public let blobID: BlobID?
    /// Pixel width of the photo, or 0 when the server carried none.
    public let width: Int
    /// Pixel height of the photo, or 0 when the server carried none.
    public let height: Int
    /// The photo's BlurHash, drawn until the image loads.
    public let blurhash: String?
    /// The text sent with the photo, drawn as its own bubble under the image.
    public let caption: String?
    /// Whether the server withheld the photo's download URL; the bubble then only ever draws its BlurHash.
    public let isRedacted: Bool
    /// What decrypting the blob needs when it is end-to-end encrypted, nil for a plaintext blob.
    public let sealed: SealedBlob?

    public init(blobID: BlobID?, width: Int, height: Int, blurhash: String?, caption: String?, isRedacted: Bool, sealed: SealedBlob? = nil) {
        self.blobID = blobID
        self.width = width
        self.height = height
        self.blurhash = blurhash
        self.caption = caption
        self.isRedacted = isRedacted
        self.sealed = sealed
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
