//
//  ChatSpotlightItem.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import CoreSpotlight
import UniformTypeIdentifiers
import FlipcashCore

/// A single DM conversation prepared for the on-device Spotlight index. The
/// mapping from `Conversation` to searchable attributes is pure so it can be
/// unit-tested without touching `CSSearchableIndex`.
nonisolated struct ChatSpotlightItem {

    /// Domain for every chat item, so the whole set can be cleared in one call
    /// on logout without disturbing other Spotlight contributions.
    static let domainIdentifier = "com.flipcash.chat"

    /// The conversation's `base64URLEncoded` id — the same token the
    /// `flipcash://chat/{id}` deep link carries, so a Spotlight tap routes
    /// through the existing deep-link path.
    let uniqueIdentifier: String
    let title: String
    let contentDescription: String?
    /// Extra searchable terms. Critical for a chat with no contact name: its
    /// title is a formatted phone number like "(586) 980-2333", and Spotlight
    /// won't match a bare "586" inside that punctuation — so the raw and
    /// digits-only number forms go here to make it findable by digits.
    let keywords: [String]
    /// PNG of the counterpart's avatar, shown as the result thumbnail (with
    /// Spotlight's automatic app-icon badge). Nil falls back to the app icon.
    let thumbnailData: Data?

    init(conversation: Conversation, displayName: String, counterpartPhoneE164: String?, thumbnailData: Data?) {
        self.uniqueIdentifier = conversation.id.base64URLEncoded
        self.title = displayName
        self.contentDescription = Self.preview(of: conversation.lastMessage)
        self.keywords = Self.keywords(displayName: displayName, phoneE164: counterpartPhoneE164)
        self.thumbnailData = thumbnailData
    }

    var searchableItem: CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = title
        attributes.contentDescription = contentDescription
        attributes.keywords = keywords
        attributes.thumbnailData = thumbnailData
        return CSSearchableItem(
            uniqueIdentifier: uniqueIdentifier,
            domainIdentifier: Self.domainIdentifier,
            attributeSet: attributes
        )
    }

    /// Mirrors the recipient picker's last-message subtitle.
    private static func preview(of message: ConversationMessage?) -> String? {
        switch message?.content {
        case .text(let text):    text
        case .cash(let amount):  "Cash · \(amount.nativeAmount.formatted())"
        case .deleted, nil:      nil
        }
    }

    /// The display name plus the counterpart number in every form a user might
    /// type: E.164, national, and digits-only of each (so a national-digits
    /// token like "5869802333" prefix-matches "586"). De-duplicated, empties
    /// dropped.
    private static func keywords(displayName: String, phoneE164: String?) -> [String] {
        var terms: [String] = [displayName]
        if let phoneE164, !phoneE164.isEmpty {
            terms.append(phoneE164)
            terms.append(phoneE164.filter(\.isNumber))
            if let national = Phone(phoneE164)?.national {
                terms.append(national)
                terms.append(national.filter(\.isNumber))
            }
        }
        var seen: Set<String> = []
        return terms.filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}
