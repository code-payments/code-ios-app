//
//  ChatItem.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import DifferenceKit
import Foundation

/// A single rendered row in the transcript: a message bubble or a centered date header. A
/// separator carries no sender or grouping, so it's a distinct case rather than a message with
/// unused fields. The delivery line rides on its message (`ChatMessage.receipt`), not as its own
/// row. The whole transcript is driven by `[ChatItem]`.
public enum ChatItem: Hashable, Sendable, Identifiable {
    case message(ChatMessage)
    /// A centered day + time header, e.g. "Today 12:13 PM". `text` is already formatted.
    case dateSeparator(id: String, text: String)

    public var id: String {
        switch self {
        case .message(let message): message.id
        case .dateSeparator(let id, _): id
        }
    }
}

/// Drives ChatLayout's canonical `reload(using:)` diffing: identity by `id` (stable across a
/// re-group or receipt change), content equality by value (so a changed bubble reconfigures).
extension ChatItem: Differentiable {
    public var differenceIdentifier: String { id }
    public func isContentEqual(to source: ChatItem) -> Bool { self == source }
}
