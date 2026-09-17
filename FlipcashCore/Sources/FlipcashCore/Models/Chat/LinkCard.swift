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
            /// The mint's bill-customization colors (`#RRGGBB`) — the gradient the card is painted
            /// in. Empty takes the fallback.
            public let billColors: [String]
            /// Whether this is the reserve, which has fixed gold branding rather than a mint's own.
            public let isUSDF: Bool
            public let issuedByViewer: Bool

            public init(
                amount: String,
                claim: Claim,
                tokenName: String,
                iconURL: URL?,
                billColors: [String],
                isUSDF: Bool,
                issuedByViewer: Bool
            ) {
                self.amount = amount
                self.claim = claim
                self.tokenName = tokenName
                self.iconURL = iconURL
                self.billColors = billColors
                self.isUSDF = isUSDF
                self.issuedByViewer = issuedByViewer
            }

            /// The line inside the bill, under the amount. Resolved here, next to
            /// `ChatCashContent.caption`, so the view stays dumb and both cash surfaces word
            /// themselves in one layer.
            ///
            /// A claimed or expired card says so and offers nothing to tap: the card is a drawing
            /// of a link that is still openable, and the claim itself only ever happens through
            /// the deep-link path.
            public var caption: String {
                switch claim {
                case .claimed:   "Claimed"
                case .expired:   "Expired"
                case .claimable: issuedByViewer ? "You sent this" : "Tap to claim"
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
