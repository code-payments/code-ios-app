//
//  PinnedMessages.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// A chat's pins as fetched with `GetPinnedMessages`, kept current by `PinsChanged` updates.
///
/// Pins are held most recently pinned first. The server keeps a pin on a message deleted after it was
/// pinned; such a pin stays here, counts toward the cap, and is left out of ``visible``.
public struct PinnedMessages: Hashable, Sendable {

    /// Every pin, most recently pinned first, tombstones included.
    public private(set) var pins: [ConversationPin]

    /// The ``ConversationPinSummary/version`` the list is current as of.
    public private(set) var version: UInt64

    public init(pins: [ConversationPin], version: UInt64) {
        self.pins = pins
        self.version = version
    }

    /// What applying an update did.
    public enum Outcome: Equatable, Sendable {
        /// The update was the next version and carried its change, which is now applied.
        case applied
        /// The update is newer than the list but can't be applied in place; fetch the list again.
        case needsRefetch
        /// The list already reflects this version or a newer one.
        case stale
    }

    /// The pins a viewer sees: neither deleted nor missing their message.
    public var visible: [ConversationPin] {
        pins.filter { !$0.isDeleted && $0.message != nil }
    }

    /// The ids of every pinned message, tombstones included.
    public var messageIDs: Set<MessageID> {
        Set(pins.map(\.messageID))
    }

    /// Applies `change`, delivered with `summary`. Only the next version applies in place; a gap, or an
    /// update without its change, needs a refetch.
    public mutating func apply(_ change: ConversationPinChange?, summary: ConversationPinSummary) -> Outcome {
        guard summary.version > version else { return .stale }
        guard summary.version == version + 1, let change else { return .needsRefetch }
        switch change {
        case .pinned(let pin):
            guard pin.message != nil else { return .needsRefetch }
            pins.removeAll { $0.messageID == pin.messageID }
            pins.insert(pin, at: 0)
        case .unpinned(let messageID):
            pins.removeAll { $0.messageID == messageID }
        }
        version = summary.version
        return .applied
    }

    /// Replaces a pinned message's copy with `message`, after an edit or a delete. Returns whether a
    /// pin held it.
    @discardableResult
    public mutating func replace(_ message: ConversationMessage) -> Bool {
        guard let index = pins.firstIndex(where: { $0.messageID == message.id }) else { return false }
        let pin = pins[index]
        pins[index] = ConversationPin(messageID: pin.messageID, pinnedBy: pin.pinnedBy, pinnedAt: pin.pinnedAt, message: message)
        return true
    }

    /// The visible pin after `messageID`, stepping toward older pins and wrapping to the newest. The
    /// newest visible pin when `messageID` is nil or no longer visible.
    public func pin(after messageID: MessageID?) -> ConversationPin? {
        let visible = visible
        guard let messageID, let index = visible.firstIndex(where: { $0.messageID == messageID }) else {
            return visible.first
        }
        return visible[(index + 1) % visible.count]
    }

    /// The visible pin `messageID` names, or the newest visible pin when it names none.
    public func shown(_ messageID: MessageID?) -> ConversationPin? {
        let visible = visible
        return visible.first { $0.messageID == messageID } ?? visible.first
    }
}
