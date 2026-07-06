//
//  LinkPreview.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// A web link found in a message, ready to render as a preview card. `bubbleText` is the message text
/// with the previewed (trailing) URL removed and whitespace-trimmed — the bubble renders this instead
/// of the raw text, so the link isn't shown twice (once as text, once as the card). An empty
/// `bubbleText` means the message was nothing but the link, so the text bubble is hidden entirely.
public struct LinkPreview: Hashable, Sendable, Codable {
    public let url: URL
    public let bubbleText: String

    public init(url: URL, bubbleText: String) {
        self.url = url
        self.bubbleText = bubbleText
    }
}
