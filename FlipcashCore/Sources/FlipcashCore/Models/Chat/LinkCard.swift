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

    /// The URL the card stands for, jump wrapper already unwrapped. Tapping the card opens this.
    public var url: URL {
        switch self {
        case .cash(let cash): cash.url
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
        }
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
}
