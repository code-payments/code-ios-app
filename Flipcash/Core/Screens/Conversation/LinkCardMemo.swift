//
//  LinkCardMemo.swift
//  Flipcash
//

import Foundation
import FlipcashCore
import FlipcashStore

/// What the resolver has already answered about a link, readable without awaiting it.
///
/// ``LinkCardResolver`` memoizes for the whole session, but its queries live behind an actor, and a
/// card view paints the moment it is configured. So a link looked at once already had an answer the
/// card could not have in time: it would shimmer its way to a value it was holding all along.
///
/// This is the same answers on the main actor, where first paint can read them. The resolver stays
/// the one thing that *makes* an answer; this only remembers what came back, so the two cannot
/// disagree about a link — a re-ask lands here only when it lands there.
///
/// Container-scoped like the resolver, and grows with the links a session has looked at. A state is
/// two enum cases and a handful of short strings, and it is bounded by the cash and token links the
/// reader actually scrolled past, so there is nothing here worth evicting.
///
/// Web answers are the exception to "nothing worth evicting": each carries the time it landed and
/// reads as nil once past its TTL, and they persist in the store's `linkPreview` table so a relaunch
/// does not fetch the page again. The rows have Android's shape and key, which is what keeps the two
/// apps' caches readable the same way.
@MainActor
final class LinkCardMemo {

    /// Keyed by ``LinkCard/resolutionKey``, which is what the resolver memoizes on.
    private(set) var states: [String: LinkCard.State] = [:]

    private var webAnswers: [String: (state: LinkCard.Web.State, at: Date)] = [:]
    private let store: (any LinkPreviewStoring)?
    private let images: WebImageDiskCache?
    private let now: @Sendable () -> Date
    private var loaded: Bool
    private var loadWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    /// A memo with no store keeps web answers for the session only. `images` is the disk store
    /// whose files go when the rows pointing at them are replaced or expire (P22c).
    init(store: (any LinkPreviewStoring)? = nil, images: WebImageDiskCache? = nil, now: @escaping @Sendable () -> Date = Date.init) {
        self.store = store
        self.images = images
        self.now = now
        self.loaded = store == nil
        if let store { load(from: store) }
    }

    /// Remembers what the resolver answered for `key`.
    ///
    /// Always an overwrite, never a merge: a re-ask exists precisely because the old answer went
    /// stale, so the newest answer is the only one worth keeping.
    func record(_ state: LinkCard.State, for key: String) {
        states[key] = state
    }

    /// Drops what is held about `key`, so the next look finds nothing and asks again.
    ///
    /// Paired with ``LinkCardResolver/invalidateCash(entropy:)`` — forgetting on one side alone
    /// would leave the two disagreeing about the link.
    func forget(_ key: String) {
        states[key] = nil
    }

    // MARK: - Web -

    /// The web answer held for `key`, or nil when there is none or it is past its TTL.
    func web(_ key: String) -> LinkCard.Web.State? {
        guard let held = webAnswers[key] else { return nil }
        let ttl = switch held.state {
        case .none:     WebLinks.emptyTTL
        case .resolved: WebLinks.resolvedTTL
        }
        return now().timeIntervalSince(held.at) <= ttl ? held.state : nil   // D8: exactly at the TTL still counts
    }

    /// Remembers a web answer and writes it through to the store. Failures never reach here.
    func recordWeb(_ state: LinkCard.Web.State, for key: String) {
        let at = now()
        let images = images
        if let replaced = Self.imageURL(of: webAnswers[key]?.state), replaced != Self.imageURL(of: state) {
            Task.detached(priority: .utility) { images?.remove(replaced) }
        }
        if let kept = Self.imageURL(of: state) {
            Task.detached(priority: .utility) { images?.touch(kept) }
        }
        webAnswers[key] = (state, at)
        guard let store else { return }
        let json = StoredWeb(state).encoded
        Task.detached(priority: .utility) {
            try? store.upsertLinkPreview(key: key, json: json, updatedAt: at)
        }
    }

    /// Returns once the stored answers are loaded, or after 500 ms, whichever comes first.
    func awaitLoaded() async {
        guard !loaded else { return }
        let id = UUID()
        await withCheckedContinuation { continuation in
            loadWaiters[id] = continuation
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(500))
                self?.loadWaiters.removeValue(forKey: id)?.resume()
            }
        }
    }

    private func load(from store: any LinkPreviewStoring) {
        let cutoff = now().addingTimeInterval(-WebLinks.resolvedTTL)
        Task.detached(priority: .utility) { [weak self, images] in
            let rows = (try? store.linkPreviews(since: cutoff)) ?? []
            try? store.deleteLinkPreviews(before: cutoff)
            images?.removeAll(before: cutoff)
            await self?.finishLoad(rows)
        }
    }

    private static func imageURL(of state: LinkCard.Web.State?) -> URL? {
        guard case .resolved(let page) = state else { return nil }
        return page.imageURL
    }

    private func finishLoad(_ rows: [LinkPreviewRow]) {
        for row in rows where webAnswers[row.key] == nil {
            guard let state = StoredWeb.decode(row.json)?.state else { continue }
            webAnswers[row.key] = (state, row.updatedAt)
        }
        loaded = true
        loadWaiters.values.forEach { $0.resume() }
        loadWaiters = [:]
    }
}

/// Where web answers persist. `Database` is the real one.
nonisolated protocol LinkPreviewStoring: Sendable {
    func linkPreviews(since: Date) throws -> [LinkPreviewRow]
    func upsertLinkPreview(key: String, json: Data, updatedAt: Date) throws
    func deleteLinkPreviews(before: Date) throws
}

extension Database: LinkPreviewStoring {}

/// Android's persisted shape: every field optional, and a null `title` means the host had nothing.
nonisolated struct StoredWeb: Codable, Equatable {
    var title: String?
    var description: String?
    var imageUrl: String?
    var host: String?

    init(_ state: LinkCard.Web.State) {
        switch state {
        case .none:
            break
        case .resolved(let resolved):
            title = resolved.title
            description = resolved.description
            imageUrl = resolved.imageURL?.absoluteString
            host = resolved.host
        }
    }

    var state: LinkCard.Web.State? {
        guard let title else { return LinkCard.Web.State.none }
        guard let host else { return nil }
        return .resolved(.init(title: title, description: description, imageURL: imageUrl.flatMap(URL.init(string:)), host: host))
    }

    /// D8: all four keys are written, nulls included, as Android writes them.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(description, forKey: .description)
        try container.encode(imageUrl, forKey: .imageUrl)
        try container.encode(host, forKey: .host)
    }

    var encoded: Data { (try? JSONEncoder().encode(self)) ?? Data() }

    static func decode(_ data: Data) -> StoredWeb? {
        try? JSONDecoder().decode(StoredWeb.self, from: data)
    }
}
