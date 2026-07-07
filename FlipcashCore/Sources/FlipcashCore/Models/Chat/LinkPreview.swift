//
//  LinkPreview.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// A web link found in a message's text — marks the message as link-bearing so it renders in a
/// tappable-text bubble.
public struct LinkPreview: Hashable, Sendable, Codable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }
}
