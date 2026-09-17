//
//  LinkCard.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// A link in a message that renders as a card above the sender's text.
///
/// Display-ready by construction: whoever builds it has already classified the URL and formatted
/// the amount, so the transcript needs neither `Route` nor a currency formatter. See
/// `LinkCardClassifier` and `LinkCardResolver` in the app target.
public enum LinkCard: Hashable, Sendable, Codable {

    case cash(Cash)

    /// The URL the card stands for, jump wrapper already unwrapped. Tapping the card opens this.
    public var url: URL {
        switch self {
        case .cash(let cash): cash.url
        }
    }

    public struct Cash: Hashable, Sendable, Codable {

        public let url: URL
        public let entropy: String
        public let state: State

        public init(url: URL, entropy: String, state: State) {
            self.url = url
            self.entropy = entropy
            self.state = state
        }

        public enum State: Hashable, Sendable, Codable {
            /// Branded, no network. Also what a failed, timed-out, offline or switched-off
            /// resolution renders as — a cash link card never shows an error, because the link
            /// is still perfectly openable and the card is decoration over it.
            case unresolved
            case resolved(Resolved)
        }

        public struct Resolved: Hashable, Sendable, Codable {
            /// Pre-formatted, e.g. "$15.00".
            public let amount: String
            public let claim: Claim
            public let tokenSymbol: String
            public let iconURL: URL?
            public let issuedByViewer: Bool

            public init(amount: String, claim: Claim, tokenSymbol: String, iconURL: URL?, issuedByViewer: Bool) {
                self.amount = amount
                self.claim = claim
                self.tokenSymbol = tokenSymbol
                self.iconURL = iconURL
                self.issuedByViewer = issuedByViewer
            }

            /// The line under the amount. Resolved here, next to `ChatCashContent.caption`, so the
            /// cell stays dumb and both cash surfaces word themselves in one layer.
            ///
            /// A claimed or expired card says so and offers nothing to tap: the card is decoration
            /// over a link that is still openable, and the claim itself only ever happens through
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
