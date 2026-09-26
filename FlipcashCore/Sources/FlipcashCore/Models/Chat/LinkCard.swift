//
//  LinkCard.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// A link in a message that renders as a card in place of the sender's URL.
///
/// Identity only: which link, of which kind, over which span. Classified by construction, so the
/// transcript needs no `Route` — but not looked up, because the card view does that for itself and
/// a transcript that carried the answer would re-diff every row each time one landed. See
/// `LinkCardClassifier` and `LinkCardResolver` in the app target, and `LinkCardSource` in the UI.
public enum LinkCard: Hashable, Sendable, Codable {

    case cash(Cash)
    case token(Token)
    case group(Group)
    case user(User)

    /// The URL the card stands for, jump wrapper already unwrapped. Tapping the card opens this.
    public var url: URL {
        switch self {
        case .cash(let cash): cash.url
        case .token(let token): token.url
        case .group(let group): group.url
        case .user(let user): user.url
        }
    }

    /// The span in the message text the card was built from. The transcript splits the message
    /// around it, so the card is the link rather than an ornament beside it.
    ///
    /// It is the *detected* span, not a search for `url`: a jump-wrapped link's text is the
    /// wrapper and its `url` is the target, so matching on the URL would leave the wrapper behind.
    public var range: NSRange {
        switch self {
        case .cash(let cash): cash.range
        case .token(let token): token.range
        case .group(let group): group.range
        case .user(let user): user.range
        }
    }

    /// How far a card's lookup got, kept per kind so no kind can be handed another's answer.
    ///
    /// It does not live on the card. A card is the link's identity — url, entropy or mint, span —
    /// and the view resolves it, so a lookup landing cannot change what the transcript diffed.
    public enum State: Hashable, Sendable, Codable {
        case cash(Cash.State)
        case token(Token.State)
        case group(Group.State)
        case user(User.State)

        /// Whether the lookup came back with something. A failure of any kind is `unresolved` (or
        /// `unavailable` for a group, `notFound` for a person), which is the one answer not worth remembering — the next
        /// look asks again.
        public var isResolved: Bool {
            switch self {
            case .cash(.resolved), .token(.resolved), .group(.resolved), .user(.resolved):  true
            case .cash(.unresolved), .token(.unresolved), .group(.unavailable), .user(.notFound): false
            }
        }
    }

    public struct Cash: Hashable, Sendable, Codable {

        public let url: URL
        public let entropy: String
        /// UTF-16 offsets into the message text — the same frame `DetectedLink` indexes in.
        public let location: Int
        public let length: Int

        public var range: NSRange { NSRange(location: location, length: length) }

        public init(url: URL, entropy: String, range: NSRange) {
            self.url = url
            self.entropy = entropy
            self.location = range.location
            self.length = range.length
        }

        public enum State: Hashable, Sendable, Codable {
            /// Branded, no network. Also what a failed, timed-out, offline or switched-off
            /// resolution renders as — a cash link card never shows an error, because the link
            /// is still perfectly openable and the card is a drawing of it.
            case unresolved
            case resolved(Resolved)
        }

        public struct Resolved: Hashable, Sendable, Codable {
            /// Pre-formatted, e.g. "$15.00".
            public let amount: String
            public let claim: Claim
            /// The mint's name, as the wallet's own card shows it.
            public let tokenName: String
            public let iconURL: URL?

            public init(amount: String, claim: Claim, tokenName: String, iconURL: URL?) {
                self.amount = amount
                self.claim = claim
                self.tokenName = tokenName
                self.iconURL = iconURL
            }

            /// The line on the card's stub, from the claim it carries.
            public var caption: String { claim.caption }
        }

        public enum Claim: String, Hashable, Sendable, Codable {
            case claimable
            case claimed
            case expired

            /// The line on the card's stub. Resolved here, next to `ChatCashContent.caption`, so
            /// the view stays dumb and both cash surfaces word themselves in one layer.
            ///
            /// A claimable link reads the same for the sender and the recipient. The bubble's
            /// alignment already says who sent it, and the card would be saying it a second time in
            /// the one place both people look at the same object.
            ///
            /// "Tap to claim" names what the *link* does, not what the card does: the card claims
            /// nothing, and a tap on it opens the link through the deep-link path the URL took.
            /// That is also why an unresolved card can say it before it knows anything: the tap is
            /// live in every state, so the line describes a control that already works.
            public var caption: String {
                switch self {
                case .claimed:   "Claimed"
                case .expired:   "Expired"
                case .claimable: "Tap to claim"
                }
            }
        }
    }

    public struct Token: Hashable, Sendable, Codable {

        public let url: URL
        public let mint: PublicKey
        /// UTF-16 offsets into the message text — the same frame `DetectedLink` indexes in.
        public let location: Int
        public let length: Int

        public var range: NSRange { NSRange(location: location, length: length) }

        public init(url: URL, mint: PublicKey, range: NSRange) {
            self.url = url
            self.mint = mint
            self.location = range.location
            self.length = range.length
        }

        /// The address, shortened to its two ends. What the card names while the mint is still
        /// unknown, and the reason an unresolved token card is not a blank rectangle: the raw link
        /// showed the address, so a card that showed nothing would tell the reader less than the
        /// text it replaced.
        public var abbreviatedMint: String {
            let address = mint.base58
            guard address.count > Self.abbreviationChars * 2 else { return address }
            return "\(address.prefix(Self.abbreviationChars))…\(address.suffix(Self.abbreviationChars))"
        }

        private static let abbreviationChars = 4

        public enum State: Hashable, Sendable, Codable {
            /// The mint is known, its branding is not. Also where a failed or offline lookup stays.
            case unresolved
            case resolved(Resolved)
        }

        public struct Resolved: Hashable, Sendable, Codable {
            /// The mint's name, as the wallet's own card shows it.
            public let name: String
            public let iconURL: URL?
            /// The bill's gradient stops, `#RRGGBB`, straight off `MintMetadata.billColors`.
            public let colors: [String]
            /// Whether to draw the reserve's `$` watermark, which is USDF's alone.
            public let isReserve: Bool

            public init(name: String, iconURL: URL?, colors: [String], isReserve: Bool) {
                self.name = name
                self.iconURL = iconURL
                self.colors = colors
                self.isReserve = isReserve
            }
        }
    }
}

// MARK: - Group -

extension LinkCard {

    /// A group chat's invite link, `app.flipcash.com/chat/{uuid}`.
    public struct Group: Hashable, Sendable, Codable {

        public let url: URL
        /// The chat id's bytes. Stored raw because `ConversationID` is not `Codable`.
        public let chatIDData: Data
        /// UTF-16 offsets into the message text — the same frame `DetectedLink` indexes in.
        public let location: Int
        public let length: Int

        public var range: NSRange { NSRange(location: location, length: length) }

        /// The chat the link invites to.
        public var chatID: ConversationID { ConversationID(data: chatIDData) }

        public init(url: URL, chatID: ConversationID, range: NSRange) {
            self.url = url
            self.chatIDData = chatID.data
            self.location = range.location
            self.length = range.length
        }

        public enum State: Hashable, Sendable, Codable {
            /// No group to show: the lookup failed, or the chat is gone. Not remembered, so the
            /// next appearance asks again.
            case unavailable
            case resolved(Resolved)
        }

        /// The card's contents, already worded for display.
        ///
        /// Built from the chat's public record only — title, picture, member count, rules — and
        /// never from its roster, which is private to members whatever the group's mode.
        public struct Resolved: Hashable, Sendable, Codable {
            public let title: String
            /// "1 person" / "12 people".
            public let memberCount: String
            /// Stable identity for the avatar (monogram colour and image cache key).
            public let avatarID: String
            /// The chat picture's thumbnail bytes, once loaded.
            public let imageData: Data?
            /// The chat picture's BlurHash: the avatar's preview and the band's tint.
            public let blurHash: String?
            /// The entry rule as the chat's own head card states it, or nil when it states none.
            public let requirement: String?

            public init(
                title: String,
                memberCount: String,
                avatarID: String,
                imageData: Data?,
                blurHash: String?,
                requirement: String?
            ) {
                self.title = title
                self.memberCount = memberCount
                self.avatarID = avatarID
                self.imageData = imageData
                self.blurHash = blurHash
                self.requirement = requirement
            }
        }
    }
}

// MARK: - User -

extension LinkCard {

    /// A person's tip card link: `flipcash.com/<handle>`, `flipcash.com/<uuid>` for someone with no
    /// handle, or the legacy `flipcash.com/tip/<uuid>`.
    public struct User: Hashable, Sendable, Codable {

        /// Who the link names, as the URL spells it.
        public enum Identity: Hashable, Sendable, Codable {
            case userID(UserID)
            case username(Username)
        }

        public let url: URL
        public let identity: Identity
        /// UTF-16 offsets into the message text — the same frame `DetectedLink` indexes in.
        public let location: Int
        public let length: Int

        public var range: NSRange { NSRange(location: location, length: length) }

        public init(url: URL, identity: Identity, range: NSRange) {
            self.url = url
            self.identity = identity
            self.location = range.location
            self.length = range.length
        }

        /// The `@handle` the link itself names, or nil for an id link. What a card with no account
        /// behind it shows as the name, since the link is all it has to go on.
        public var linkedHandle: String? {
            switch identity {
            case .username(let username): username.handle
            case .userID:                 nil
            }
        }

        public enum State: Hashable, Sendable, Codable {
            /// No account to show: the handle is unclaimed, or the lookup failed. Not remembered, so
            /// the next appearance asks again.
            case notFound
            case resolved(Resolved)
        }

        /// The card's contents, already worded for display. Built from the person's public profile
        /// only.
        public struct Resolved: Hashable, Sendable, Codable {
            public let userID: UserID
            /// Whether the link is the viewer's own, which turns the button into a way to their card
            /// rather than into a chat with themselves.
            public let isOwn: Bool
            public let displayName: String
            /// "@handle", or nil when the person has not claimed one.
            public let handle: String?
            /// "Joined March 2024", or nil when the server gave no join date.
            public let joined: String?
            /// "Minimum To Chat: $1.00", or nil when the person charges nothing to start a chat.
            public let fee: String?
            /// The profile picture's thumbnail bytes, once loaded.
            public let imageData: Data?
            /// The profile picture's BlurHash: the avatar's preview and the card's backdrop.
            public let blurHash: String?

            public init(
                userID: UserID,
                isOwn: Bool,
                displayName: String,
                handle: String?,
                joined: String?,
                fee: String?,
                imageData: Data?,
                blurHash: String?
            ) {
                self.userID = userID
                self.isOwn = isOwn
                self.displayName = displayName
                self.handle = handle
                self.joined = joined
                self.fee = fee
                self.imageData = imageData
                self.blurHash = blurHash
            }

            /// Stable identity for the avatar (monogram colour and image cache key).
            public var avatarID: String { userID.uuidString }
        }
    }
}

// MARK: - The span the card takes -

nonisolated extension LinkCard {

    /// The same card over `range` — for the row that draws the card alone, whose text is the link
    /// and nothing else.
    public func relocated(to range: NSRange) -> LinkCard {
        switch self {
        case .cash(let cash):   .cash(Cash(url: cash.url, entropy: cash.entropy, range: range))
        case .token(let token): .token(Token(url: token.url, mint: token.mint, range: range))
        case .group(let group): .group(Group(url: group.url, chatID: group.chatID, range: range))
        case .user(let user):   .user(User(url: user.url, identity: user.identity, range: range))
        }
    }
}
