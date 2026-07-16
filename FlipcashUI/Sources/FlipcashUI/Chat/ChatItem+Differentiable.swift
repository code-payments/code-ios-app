//
//  ChatItem+Differentiable.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import DifferenceKit
import FlipcashCore

/// Drives ChatLayout's canonical `reload(using:)` diffing: identity by cell class + `id` (stable
/// across a re-group or receipt change), content equality by value (so a changed bubble
/// reconfigures). The cell class is part of identity because UIKit forbids reconfiguring an item
/// into a different cell class — a content change that lands in a different class (text ↔ cash,
/// a link gained or lost) must diff as delete+insert, never as an update.
extension ChatItem: Differentiable {
    public var differenceIdentifier: String { "\(cellReuseIdentifier):\(id)" }
    public func isContentEqual(to source: ChatItem) -> Bool { self == source }
}

extension ChatItem {
    /// The reuse identifier of the cell class this item renders with. Single source of truth for
    /// the item → cell-class decision: `cellForItemAt` dequeues by it, and `differenceIdentifier`
    /// folds it into identity, so the class dequeued at a position always matches the one the
    /// diff promised there.
    var cellReuseIdentifier: String {
        switch self {
        case .typingIndicator:
            ChatTypingIndicatorCell.reuseIdentifier
        case .profileCard:
            ChatProfileCardCell.reuseIdentifier
        case .dateSeparator:
            ChatDateSeparatorCell.reuseIdentifier
        case .message(let message):
            switch message.content {
            case .text:
                message.linkPreview != nil ? ChatLinkMessageCell.reuseIdentifier : ChatMessageCell.reuseIdentifier
            case .cash:
                ChatCashCardCell.reuseIdentifier
            }
        }
    }
}
