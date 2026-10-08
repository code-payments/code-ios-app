//
//  WebLinks.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// The fetch rules for web link previews, held to `link_metadata.json` so both apps agree.
public nonisolated enum WebLinks {

    public static let maxBodyBytes = 512 * 1024
    public static let maxImageBytes = 2 * 1024 * 1024
    public static let maxRedirects = 3
    public static let maxConcurrent = 4
    public static let timeout: TimeInterval = 5
    public static let resolvedTTL: TimeInterval = 168 * 3600
    public static let emptyTTL: TimeInterval = 24 * 3600
    public static let userAgent = "Mozilla/5.0 (compatible; FlipcashLinkPreview/1.0)"

    /// Whether a preview may fetch from `host`. IP literals never may, nor may a single label or a
    /// local-network name. Pass the raw host from `URLComponents.percentEncodedHost`, which keeps an
    /// IPv6 literal's brackets.
    public static func isEligibleHost(_ host: String) -> Bool {
        let h = host.lowercased()
        if h.hasPrefix("[") || h.contains(":") || isIPv4(h) { return false }
        if h == "localhost" || [".localhost", ".local", ".internal"].contains(where: h.hasSuffix) { return false }
        return h.contains(".")
    }

    /// The memo key for `url`: scheme and host lowercased, fragment and `:443` dropped, path and
    /// query kept as written.
    public static func cacheKey(_ url: URL) -> String? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              let host = components.percentEncodedHost?.lowercased() else { return nil }
        components.scheme = scheme
        components.percentEncodedHost = host
        components.fragment = nil
        if components.port == 443 { components.port = nil }
        return components.string
    }

    private static func isIPv4(_ h: String) -> Bool {
        let parts = h.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy { $0.isASCII && $0.isNumber }
        }
    }
}
