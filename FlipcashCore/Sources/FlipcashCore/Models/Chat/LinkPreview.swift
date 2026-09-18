//
//  LinkPreview.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// What a message's links amount to: every tappable span, and at most one card.
///
/// It held a single `url` before this, which is why nothing in the transcript could show more
/// than the trailing link. The name was always a promise; this is it being kept.
public struct LinkPreview: Hashable, Sendable, Codable {

    /// Every web link in the message, in the order they appear.
    public let links: [DetectedLink]

    /// The first card-eligible Flipcash link, if any. At most one per message, so a pasted list
    /// of links cannot turn a transcript into a wall of cards.
    public let card: LinkCard?

    /// The trailing link, which is what the old single-field shape meant.
    public var url: URL? { links.last?.url }

    public init(links: [DetectedLink], card: LinkCard? = nil) {
        self.links = links
        self.card = card
    }

    public init(url: URL) {
        self.init(links: [DetectedLink(range: NSRange(location: 0, length: 0), url: url)], card: nil)
    }
}
