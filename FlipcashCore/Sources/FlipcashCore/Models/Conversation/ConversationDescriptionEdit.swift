//
//  ConversationDescriptionEdit.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import FlipcashAPI

/// What an `EditChat` call does to a group's description.
///
/// The wire distinguishes "leave it" (wrapper unset) from "clear it" (wrapper set with an empty
/// value); a bare `String?` would conflate the two with `""`, so the intent is spelled out.
public enum ConversationDescriptionEdit: Sendable, Equatable {
    /// Leave the description as it is.
    case unchanged
    /// Replace the description. An empty string is treated as ``clear``.
    case set(String)
    /// Remove the description.
    case clear
}

extension ConversationDescriptionEdit {
    /// The `EditChatRequest.description` wrapper, or `nil` to leave the field unset.
    var proto: Flipcash_Chat_V1_EditChatRequest.Description? {
        switch self {
        case .unchanged:
            nil
        case .set(let value):
            .with { $0.value = value }
        case .clear:
            .with { $0.value = "" }
        }
    }
}
