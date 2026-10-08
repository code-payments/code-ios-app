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
    /// local-network name. Pass `host(of:)`, which keeps an IPv6 literal's brackets.
    public static func isEligibleHost(_ host: String) -> Bool {
        let h = host.lowercased()
        if h.hasPrefix("[") || h.contains(":") || isIPv4(h) { return false }
        if h.hasSuffix(".") || isNumericLabels(h) { return false }
        if h == "localhost" || [".localhost", ".local", ".internal"].contains(where: h.hasSuffix) { return false }
        return h.contains(".")
    }

    /// Whether a preview may fetch `url`: `https`, an eligible host, and no port other than 443.
    public static func isFetchable(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = host(of: url) else { return false }
        return isEligibleHost(host) && (url.port ?? 443) == 443
    }

    /// The host every preview step uses: the URL's IDNA (punycode) form, lowercased. Nil when there
    /// is none or it carries a percent escape. `percentEncodedHost` is not this: Foundation hands back
    /// `b%C3%BCcher.example` there even for a URL written as `xn--bcher-kva.example`.
    public static func host(of url: URL) -> String? {
        guard let host = URLComponents(url: url, resolvingAgainstBaseURL: false)?.encodedHost?.lowercased(),
              !host.isEmpty, !host.contains("%"), host.allSatisfy(\.isASCII) else { return nil }
        return host
    }

    /// The memo key for `url`: scheme and host lowercased, fragment and `:443` dropped, path and
    /// query kept as written.
    public static func cacheKey(_ url: URL) -> String? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              let host = host(of: url) else { return nil }
        components.scheme = scheme
        components.encodedHost = host
        components.fragment = nil
        if components.port == 443 { components.port = nil }
        return components.string
    }

    /// Labels a system resolver reads as an IP literal (`127.1`, `0x7f.0.0.1`): decimal, or `0x` hex.
    private static func isNumericLabels(_ h: String) -> Bool {
        h.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { label in
            if label.hasPrefix("0x") { return label.dropFirst(2).allSatisfy(\.isHexDigit) }
            return !label.isEmpty && label.allSatisfy { $0.isASCII && $0.isNumber }
        }
    }

    private static func isIPv4(_ h: String) -> Bool {
        let parts = h.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy { $0.isASCII && $0.isNumber }
        }
    }
}
