//
//  LinkCard.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// A link in a message that renders as a card in place of the sender's URL.
///
/// Display-ready by construction: whoever builds it has already classified the URL, formatted the
/// amount, and read the mint's branding, so the transcript needs neither `Route` nor a currency
/// formatter. See `LinkCardClassifier` and `LinkCardResolver` in the app target.
public enum LinkCard: Hashable, Sendable, Codable {

    case cash(Cash)
    case token(Token)

    /// The URL the card stands for, jump wrapper already unwrapped. Tapping the card opens this.
    public var url: URL {
        switch self {
        case .cash(let cash): cash.url
        case .token(let token): token.url
        }
    }

    /// The span in the message text the card was built from. The bubble cuts this out of the body,
    /// so the card is the link rather than an ornament above it.
    ///
    /// It is the *detected* span, not a search for `url`: a jump-wrapped link's text is the
    /// wrapper and its `url` is the target, so matching on the URL would leave the wrapper behind.
    public var range: NSRange {
        switch self {
        case .cash(let cash): cash.range
        case .token(let token): token.range
        }
    }

    /// How far a card's lookup got, kept per kind so the two cannot be handed to each other. The
    /// resolver memoizes these and a re-map applies them back, which is what stops a scroll from
    /// asking again for a card it has already filled in.
    public enum State: Hashable, Sendable, Codable {
        case cash(Cash.State)
        case token(Token.State)
    }

    public struct Cash: Hashable, Sendable, Codable {

        public let url: URL
        public let entropy: String
        /// UTF-16 offsets into the message text — the same frame `DetectedLink` indexes in.
        public let location: Int
        public let length: Int
        public let state: State

        public var range: NSRange { NSRange(location: location, length: length) }

        public init(url: URL, entropy: String, range: NSRange, state: State) {
            self.url = url
            self.entropy = entropy
            self.location = range.location
            self.length = range.length
            self.state = state
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

            /// The line on the card's stub. Resolved here, next to `ChatCashContent.caption`, so
            /// the view stays dumb and both cash surfaces word themselves in one layer.
            ///
            /// A claimable link reads the same for the sender and the recipient. The bubble's
            /// alignment already says who sent it, and the card would be saying it a second time in
            /// the one place both people look at the same object.
            ///
            /// "Tap to claim" names what the *link* does, not what the card does: the card claims
            /// nothing, and a tap on it opens the link through the deep-link path the URL took.
            public var caption: String {
                switch claim {
                case .claimed:   "Claimed"
                case .expired:   "Expired"
                case .claimable: "Tap to claim"
                }
            }
        }

        public enum Claim: String, Hashable, Sendable, Codable {
            case claimable
            case claimed
            case expired
        }
    }

    public struct Token: Hashable, Sendable, Codable {

        public let url: URL
        public let mint: PublicKey
        /// UTF-16 offsets into the message text — the same frame `DetectedLink` indexes in.
        public let location: Int
        public let length: Int
        public let state: State

        public var range: NSRange { NSRange(location: location, length: length) }

        public init(url: URL, mint: PublicKey, range: NSRange, state: State) {
            self.url = url
            self.mint = mint
            self.location = range.location
            self.length = range.length
            self.state = state
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
