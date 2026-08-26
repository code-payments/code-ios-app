//
//  ChatProfileCard.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// What the transcript's profile-card row shows about the counterpart: their avatar, title line,
/// and how they relate to the address book (which drives the subtitle and the call to action).
public struct ChatProfileCard: Hashable, Sendable, Codable {
    /// Title line: the contact's name, or their formatted number when they're not a contact.
    public var name: String
    /// Stable identity for the avatar (monogram color + image cache key).
    public var avatarID: String
    /// The contact's address-book thumbnail; nil renders the monogram placeholder.
    public var imageData: Data?
    /// The counterpart's profile-picture BlurHash, shown as a blurred preview while
    /// their avatar bytes load. Nil for address-book contacts.
    public var blurhash: String?
    public var counterpart: Counterpart

    /// What the card's subtitle line says about the counterpart, and whether it
    /// offers a contact action.
    public enum Counterpart: Hashable, Sendable, Codable {
        /// In the address book: the subtitle is their number and the CTA views their contact card.
        case contact(phone: String)
        /// Not in the address book: an "Unknown Contact" subtitle and a CTA that adds them.
        case unknown
        /// Known by their Flipcash handle: the subtitle is `@handle` and there is no
        /// contact CTA — the address book has nothing to say about them.
        case handle(Username)
        /// No address-book relationship to surface (e.g. a tip DM counterpart known by
        /// profile only): just the avatar and name, no subtitle and no contact CTA.
        case none
    }

    public init(name: String, avatarID: String, imageData: Data?, blurhash: String? = nil, counterpart: Counterpart) {
        self.name = name
        self.avatarID = avatarID
        self.imageData = imageData
        self.blurhash = blurhash
        self.counterpart = counterpart
    }
}
