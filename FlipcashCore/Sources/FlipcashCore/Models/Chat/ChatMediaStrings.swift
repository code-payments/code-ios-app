//
//  ChatMediaStrings.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// The words a photo message is summarised in wherever it cannot be drawn: a reply's quote, the chat
/// list, Spotlight, and notifications. The copy is the fixture's `strings` section, shared with Android.
public enum ChatMediaStrings {

    /// A quote's snippet for a photo: its caption, or "Photo" when it has none.
    public static func quoteSnippet(caption: String?) -> String {
        nonEmpty(caption) ?? "Photo"
    }

    /// A one-line preview of a photo: the camera glyph ahead of its caption, or ahead of "Photo".
    public static func listPreview(caption: String?) -> String {
        "📷 " + quoteSnippet(caption: caption)
    }

    // The transcript draws no caption bubble for an empty caption, so neither does a preview.
    private static func nonEmpty(_ caption: String?) -> String? {
        guard let caption, !caption.isEmpty else { return nil }
        return caption
    }
}
