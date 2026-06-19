//
//  ChatItem.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// A single rendered row in the transcript: either a message bubble or a centered date header.
/// A separator carries no sender or grouping, so it's a distinct case rather than a message with
/// unused fields. The whole transcript is driven by `[ChatItem]`.
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
