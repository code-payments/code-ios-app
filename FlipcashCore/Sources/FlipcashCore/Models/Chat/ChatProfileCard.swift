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
    public var counterpart: Counterpart

    /// How the counterpart relates to the address book.
    public enum Counterpart: Hashable, Sendable, Codable {
        /// In the address book: the subtitle is their number and the CTA views their contact card.
        case contact(phone: String)
        /// Not in the address book: an "Unknown Contact" subtitle and a CTA that adds them.
        case unknown
    }

    public init(name: String, avatarID: String, imageData: Data?, counterpart: Counterpart) {
        self.name = name
        self.avatarID = avatarID
        self.imageData = imageData
        self.counterpart = counterpart
    }
}
