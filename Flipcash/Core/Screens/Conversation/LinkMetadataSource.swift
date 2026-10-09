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
    /// The preview for `url`; throws when the outcome should not be remembered. A link that falls
    /// back to its site's home page reads and records that page's answer through `homes` (P24d).
    func metadata(for url: URL, homes: (any WebHomeAnswers)?) async throws -> LinkCard.Web.State
}

nonisolated extension LinkMetadataSource {
    /// The preview for `url`, with no remembered home-page answers to read or record.
    func metadata(for url: URL) async throws -> LinkCard.Web.State {
        try await metadata(for: url, homes: nil)
    }
}

/// The remembered answers for site home pages, which a fallback reads before fetching (P24d).
nonisolated protocol WebHomeAnswers: Sendable {
    /// The answer held for `home`, if it is still fresh.
    func answer(forHome home: URL) async -> LinkCard.Web.State?
    /// Remembers `state` as the answer for `home`.
    func record(_ state: LinkCard.Web.State, forHome home: URL) async
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

    func metadata(for url: URL, homes: (any WebHomeAnswers)?) async throws -> LinkCard.Web.State {
        guard await isEnabled() else { throw WebLinkPreviewsDisabled() }
        return try await limiter.run {
            // P24b: the link and its home-page fallback share one deadline and one redirect budget.
            try await WebRedirects.withDeadline(.seconds(2 * WebLinks.timeout)) {
                try await self.lookup(url, homes: homes)
            }
        }
    }

    private func lookup(_ url: URL, homes: (any WebHomeAnswers)?) async throws -> LinkCard.Web.State {
        var redirects = WebLinks.maxRedirects
        guard let (response, finalURL) = try await fetchPage(url, redirects: &redirects) else { return .none }
        switch try Self.read(response, from: finalURL) {
        case .resolved(let resolved): return .resolved(resolved)
        case .none: return .none
        case .fallBack: break
        }
        guard let home = Self.home(of: finalURL) else { return .none }
        if let known = await homes?.answer(forHome: home) { return known }
        // P24d: a home page past the shared redirect budget is no answer for the home key.
        guard let (homeResponse, homeURL) = try await fetchPage(home, redirects: &redirects) else { return .none }
        let state: LinkCard.Web.State = switch try Self.read(homeResponse, from: homeURL) {
        case .resolved(let resolved): .resolved(resolved)
        case .none, .fallBack: .none
        }
        await homes?.record(state, forHome: home)
        return state
    }

    private func fetchPage(_ url: URL, redirects: inout Int) async throws -> (PinnedResponse, URL)? {
        try await WebRedirects.hops(
            url, client: client, accept: "text/html,application/xhtml+xml",
            maxBytes: WebLinks.maxBodyBytes, stopsAtHeadEnd: true, redirects: &redirects
        )
    }

    private enum Page {
        case resolved(LinkCard.Web.Resolved)
        case none
        case fallBack
    }

    /// P24a: what one page response says. A server error throws so nothing is remembered.
    private static func read(_ response: PinnedResponse, from url: URL) throws -> Page {
        switch response.status {
        case 500...:
            throw WebLinkHTTPStatus(code: response.status)
        case 200..<300 where response.isHTML && response.isIdentityEncoded:
            return WebPageParser.parse(response.body, finalURL: url).map(Page.resolved) ?? .fallBack
        case 401, 403, 404:
            return .fallBack
        default:
            return .none
        }
    }

    /// `https://<host>/` for `url`, or nil when `url` already is its site's root (P24a).
    static func home(of url: URL) -> URL? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let host = components.percentEncodedHost, !host.isEmpty else { return nil }
        if (components.percentEncodedPath.isEmpty || components.percentEncodedPath == "/") && components.percentEncodedQuery == nil {
            return nil
        }
        var home = URLComponents()
        home.scheme = "https"
        home.percentEncodedHost = host
        home.path = "/"
        return home.url
    }
}

/// Fetches a preview image under the page rules; every failure is nil, since an image is never
/// remembered as missing.
nonisolated final class WebImageSource: @unchecked Sendable {

    static let shared = WebImageSource(disk: .shared)

    private let client: any PinnedFetching
    private let limiter: FetchLimiter
    // NSCache is thread-safe; it is the only mutable state here.
    private let cache = NSCache<NSURL, NSData>()
    private let disk: WebImageDiskCache?

    /// A source with no `disk` keeps images in memory only.
    init(client: any PinnedFetching = PinnedHTTPClient(), limiter: FetchLimiter = .shared, disk: WebImageDiskCache? = nil) {
        self.client = client
        self.limiter = limiter
        self.disk = disk
    }

    /// The image bytes at `url` if a previous fetch is still held in memory.
    func cached(for url: URL) -> Data? {
        cache.object(forKey: url as NSURL) as Data?
    }

    /// The image bytes at `url`, or nil when it cannot be fetched under the rules.
    func data(for url: URL) async -> Data? {
        if let hit = cache.object(forKey: url as NSURL) { return hit as Data }
        if let stored = disk?.data(for: url) {
            cache.setObject(stored as NSData, forKey: url as NSURL)
            return stored
        }
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
        disk?.store(data, for: url)
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
        try await withDeadline(deadline) {
            var redirects = WebLinks.maxRedirects
            return try await hops(start, client: client, accept: accept, maxBytes: maxBytes, stopsAtHeadEnd: false, redirects: &redirects)
        }
    }

    /// Runs `operation`, throwing `URLError(.timedOut)` once `deadline` passes.
    static func withDeadline<T: Sendable>(_ deadline: Duration, _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: deadline)
                throw URLError(.timedOut)
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }

    /// Follows redirects from `start`, spending them from `redirects`, which a later fetch in the
    /// same lookup keeps spending from (P24b).
    static func hops(_ start: URL, client: any PinnedFetching, accept: String, maxBytes: Int, stopsAtHeadEnd: Bool,
                     redirects: inout Int) async throws -> (PinnedResponse, URL)? {
        var current = start
        while true {
            guard allowed(current) else { return nil }
            let response = try await client.get(current, accept: accept, maxBytes: maxBytes, stopsAtHeadEnd: stopsAtHeadEnd)
            guard (300..<400).contains(response.status) else { return (response, current) }
            guard redirects > 0,
                  let location = response.headers["location"],
                  let next = URL(string: location, relativeTo: current)?.absoluteURL else { return nil }
            redirects -= 1
            current = next
        }
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
