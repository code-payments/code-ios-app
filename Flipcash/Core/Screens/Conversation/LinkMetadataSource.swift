//
//  LinkMetadataSource.swift
//  Code
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore

/// The client implementation of the spec's LinkMetadataSource. A server RPC replaces it.
protocol LinkMetadataSource: Sendable {
    /// The preview for `url`; throws when the outcome should not be remembered.
    func metadata(for url: URL) async throws -> LinkCard.Web.State
}

/// Thrown while the `webLinkPreviews` flag is off, so nothing is fetched or remembered.
nonisolated struct WebLinkPreviewsDisabled: Error {}

/// A server error worth asking again later, so it is never remembered.
nonisolated struct WebLinkHTTPStatus: Error, Equatable {
    let code: Int
}

/// Fetches page heads through the pinned client under the shared redirect, size and concurrency caps.
nonisolated final class PinnedLinkMetadataSource: LinkMetadataSource {

    private let client: any PinnedFetching
    private let isEnabled: @Sendable () async -> Bool
    private let limiter: FetchLimiter

    init(client: any PinnedFetching = PinnedHTTPClient(),
         limiter: FetchLimiter = .shared,
         isEnabled: @escaping @Sendable () async -> Bool = { await MainActor.run { BetaFlags.shared.hasEnabled(.webLinkPreviews) } }) {
        self.client = client
        self.limiter = limiter
        self.isEnabled = isEnabled
    }

    func metadata(for url: URL) async throws -> LinkCard.Web.State {
        guard await isEnabled() else { throw WebLinkPreviewsDisabled() }
        return try await limiter.run {
            guard let (response, finalURL) = try await WebRedirects.follow(
                url, client: self.client, accept: "text/html,application/xhtml+xml", maxBytes: WebLinks.maxBodyBytes
            ) else { return .none }
            switch response.status {
            case 500...:
                throw WebLinkHTTPStatus(code: response.status)
            case 200..<300 where response.isHTML && response.isIdentityEncoded:
                return WebPageParser.parse(response.body, finalURL: finalURL).map(LinkCard.Web.State.resolved) ?? .none
            default:
                return .none
            }
        }
    }
}

/// Fetches a preview image under the page rules; every failure is nil, since an image is never
/// remembered as missing.
nonisolated final class WebImageSource: @unchecked Sendable {

    static let shared = WebImageSource()

    private let client: any PinnedFetching
    private let limiter: FetchLimiter
    // NSCache is thread-safe; it is the only mutable state here.
    private let cache = NSCache<NSURL, NSData>()

    init(client: any PinnedFetching = PinnedHTTPClient(), limiter: FetchLimiter = .shared) {
        self.client = client
        self.limiter = limiter
    }

    /// The image bytes at `url` if a previous fetch is still held in memory.
    func cached(for url: URL) -> Data? {
        cache.object(forKey: url as NSURL) as Data?
    }

    /// The image bytes at `url`, or nil when it cannot be fetched under the rules.
    func data(for url: URL) async -> Data? {
        if let hit = cache.object(forKey: url as NSURL) { return hit as Data }
        let data = try? await limiter.run { () -> Data? in
            guard let (response, _) = try await WebRedirects.follow(
                url, client: self.client, accept: "image/*", maxBytes: WebLinks.maxImageBytes
            ),
                (200..<300).contains(response.status),
                !response.truncated,
                response.isIdentityEncoded,
                response.headers["content-type"]?.lowercased().hasPrefix("image/") == true
            else { return nil }
            return response.body
        }
        guard let data = data ?? nil else { return nil }
        cache.setObject(data as NSData, forKey: url as NSURL)
        return data
    }
}

/// The redirect loop both sources share, the same as Android's `WebLinkLookup.fetch`.
nonisolated enum WebRedirects {

    /// The first non-redirect response and the URL it came from. Nil when a hop is not allowed, a
    /// `Location` is unusable, or the chain needs more than `WebLinks.maxRedirects` redirects.
    /// Every hop shares one `deadline` (D18); running out throws, so the outcome is not remembered.
    static func follow(_ start: URL, client: any PinnedFetching, accept: String, maxBytes: Int,
                       deadline: Duration = .seconds(2 * WebLinks.timeout)) async throws -> (PinnedResponse, URL)? {
        try await withThrowingTaskGroup(of: (PinnedResponse, URL)?.self) { group in
            group.addTask { try await hops(start, client: client, accept: accept, maxBytes: maxBytes) }
            group.addTask {
                try await Task.sleep(for: deadline)
                throw URLError(.timedOut)
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }

    private static func hops(_ start: URL, client: any PinnedFetching, accept: String, maxBytes: Int) async throws -> (PinnedResponse, URL)? {
        var current = start
        for _ in 0...WebLinks.maxRedirects {
            guard allowed(current) else { return nil }
            let response = try await client.get(current, accept: accept, maxBytes: maxBytes)
            guard (300..<400).contains(response.status) else { return (response, current) }
            guard let location = response.headers["location"],
                  let next = URL(string: location, relativeTo: current)?.absoluteURL else { return nil }
            current = next
        }
        return nil
    }

    static func allowed(_ url: URL) -> Bool {
        WebLinks.isFetchable(url)
    }
}

/// Holds open fetches to a fixed number; the rest wait their turn.
actor FetchLimiter {

    static let shared = FetchLimiter(limit: WebLinks.maxConcurrent)

    private let limit: Int
    private var open = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = limit
    }

    /// Runs `operation` once fewer than `limit` others are running.
    func run<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
        if open < limit {
            open += 1
        } else {
            await withCheckedContinuation { waiting.append($0) }
        }
        defer {
            if waiting.isEmpty { open -= 1 } else { waiting.removeFirst().resume() }
        }
        return try await operation()
    }
}

private extension PinnedResponse {
    /// D2: we ask for `identity`, so any other encoding is a body we will not decode.
    nonisolated var isIdentityEncoded: Bool {
        guard let encoding = headers["content-encoding"] else { return true }
        // D17: every token, including an empty one, must read `identity`.
        return encoding.split(separator: ",", omittingEmptySubsequences: false).allSatisfy {
            $0.trimmingCharacters(in: .whitespaces).lowercased() == "identity"
        }
    }
}
