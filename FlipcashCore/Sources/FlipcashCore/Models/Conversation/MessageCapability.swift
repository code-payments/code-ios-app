//
//  MessageCapability.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// Something a person may do to a message. This is both the capability a policy grants and the row
/// the transcript's context menu renders, because the two are always the same set.
public enum MessageCapability: String, Hashable, Sendable, Codable, CaseIterable {
    case copy
    case reply
    case edit
    case delete
}

extension MessageCapability {

    /// The menu row's label.
    public var title: String {
        switch self {
        case .copy:   "Copy"
        case .reply:  "Reply"
        case .edit:   "Edit"
        case .delete: "Delete"
        }
    }

    /// Whether the menu should render this row in its destructive style.
    public var isDestructive: Bool {
        switch self {
        case .copy, .reply, .edit: false
        case .delete:              true
        }
    }
}

extension MessageCapability {

    /// The capabilities `selfUserID` has over `message`. Pure — the same inputs always give the same
    /// answer, which is what lets the transcript mapper run off the main actor.
    ///
    /// `conversation` is accepted but unread today: it is the seam a group-chat permissions model
    /// plugs into (an admin deleting another member's message, a read-only channel), and taking it
    /// now means adding that model does not change every call site. It is optional because the
    /// transcript can paint before the conversation record is loaded, and a message's own
    /// capabilities do not depend on it in a direct message.
    ///
    /// `now` is a parameter rather than `Date.now` so the result stays a function of its inputs.
    public static func resolve(
        for message: ConversationMessage,
        in conversation: Conversation?,
        as selfUserID: UserID,
        policy: MessagePolicy,
        now: Date
    ) -> Set<MessageCapability> {
        switch message.content {
        case .deleted:
            // Nothing is left to act on, and a tombstone must not be re-deleted.
            return []
        case .cash:
            // Reply is a cash message's only capability: there is no text to copy, the server
            // authored it so there is nothing to edit, and delete is deliberately withheld from
            // a payment record.
            return [.reply]
        case .text:
            break
        }

        guard message.isFromSelf(selfUserID) else {
            return [.copy, .reply]
        }

        // An unconfirmed message has no `eventSequence` to send as `expected_event_sequence`, so no
        // mutation request can be built for it. Copy is withheld too, so the menu does not appear
        // and then grow rows the instant the send confirms.
        guard message.eventSequence > 0 else {
            return []
        }

        var capabilities: Set<MessageCapability> = [.copy, .reply]
        if isWithin(policy.editWindow, of: message, at: now) {
            capabilities.insert(.edit)
        }
        if isWithin(policy.deleteWindow, of: message, at: now) {
            capabilities.insert(.delete)
        }
        return capabilities
    }

    /// Whether `message` is still inside `window` at `now`. A `nil` window never lapses.
    ///
    /// The comparison is `<=`, so a message at exactly the window's length is still actionable.
    /// Android's `MessageCapability.kt` uses `<=` at the same boundary; the two must agree.
    private static func isWithin(_ window: TimeInterval?, of message: ConversationMessage, at now: Date) -> Bool {
        guard let window else { return true }
        return now.timeIntervalSince(message.date) <= window
    }

    /// The earliest instant after `now` at which some message in `messages` loses a capability, or
    /// `nil` when none of them will ever change again.
    ///
    /// Eligibility runs through ``resolve(for:in:as:policy:now:)`` rather than re-deriving it, so a
    /// message that has no windowed capability to lose — someone else's, a tombstone, an
    /// unconfirmed send — contributes no deadline and the two stay in step by construction.
    public static func nextExpiry(
        among messages: [ConversationMessage],
        in conversation: Conversation?,
        as selfUserID: UserID,
        policy: MessagePolicy,
        now: Date
    ) -> Date? {
        var earliest: Date?
        for message in messages {
            let capabilities = resolve(for: message, in: conversation, as: selfUserID, policy: policy, now: now)
            for capability in capabilities {
                guard let window = policy.window(for: capability) else { continue }
                let expiry = message.date.addingTimeInterval(window)
                // `>=`, not `>`: the window boundary is inclusive, so a deadline landing exactly on
                // `now` is one the capability is still granted at. Dropping it would leave the row
                // actionable with no timer armed to take it away. The caller wakes a beat after the
                // deadline rather than on it, so keeping this instant cannot re-arm on itself.
                guard expiry >= now else { continue }
                if let current = earliest, current <= expiry { continue }
                earliest = expiry
            }
        }
        return earliest
    }
}
