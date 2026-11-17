//
//  ProfileAvatarStoreTests.swift
//  FlipcashTests
//

import Foundation
import UIKit
import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("ProfileAvatarStore")
struct ProfileAvatarStoreTests {

    private typealias AvatarSubject = ProfileAvatarStore.AvatarSubject

    /// A suspension the test releases by hand, so a fetch can be held mid-flight while the callers
    /// around it are cancelled. Not cancellation-aware: the fetch under test checks cancellation
    /// itself, the way `URLSession` does.
    @MainActor
    private final class Gate {
        private var waiters: [CheckedContinuation<Void, Never>] = []
        private var isOpen = false

        func wait() async {
            guard !isOpen else { return }
            await withCheckedContinuation { waiters.append($0) }
        }

        func open() {
            isOpen = true
            for waiter in waiters { waiter.resume() }
            waiters = []
        }
    }

    @MainActor
    private final class Counter {
        private(set) var value = 0
        func increment() { value += 1 }
    }

    /// A real image, since the store keeps only bytes that decode as one.
    private static let bytes = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).pngData { context in
        UIColor.red.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    /// What CloudFront answers an expired signed URL with.
    private static let accessDenied = Data(
        #"<?xml version="1.0" encoding="UTF-8"?><Error><Code>AccessDenied</Code><Message>Access denied</Message></Error>"#.utf8
    )

    private static func reply(_ data: Data, status: Int = 200, for url: URL) -> (Data, URLResponse) {
        (data, HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }

    private static func picture() -> ProfilePicture {
        let blobID = BlobID(uuid: UUID())
        return ProfilePicture(blobID: blobID, thumbnailBlobID: blobID)
    }

    private static func cache() -> BlobCache {
        BlobCache(
            directory: URL.temporaryDirectory.appendingPathComponent(UUID().uuidString),
            limitBytes: 1 << 20
        )
    }

    /// The callers are SwiftUI `.task`s, cancelled when their view is covered or its id changes —
    /// which happens on the way into a tip DM. A fetch cancelled with the caller that started it
    /// stored nothing, and the screen kept the blurhash for as long as it was up.
    @Test("A cancelled caller does not cancel the fetch")
    func cancelledCallerStillStoresBytes() async {
        let userID = UUID()
        let picture = Self.picture()
        let started = Gate()
        let release = Gate()

        let store = ProfileAvatarStore(
            cache: Self.cache(),
            mintURL: { _, _ in URL(string: "https://example.test/avatar")! },
            fetch: { url in
                started.open()
                await release.wait()
                try Task.checkCancellation()
                return Self.reply(Self.bytes, for: url)
            }
        )

        let caller = Task { await store.load(userID: userID, picture: picture) }
        await started.wait()

        caller.cancel()
        release.open()
        await caller.value

        #expect(store.data(for: userID) == Self.bytes)
    }

    /// A caller that arrived mid-fetch used to be turned away with nothing, and had no way to learn
    /// the fetch it skipped had failed — so a cancelled first caller left every later one empty.
    @Test("A caller arriving mid-fetch joins it")
    func laterCallerJoinsTheFetchInFlight() async {
        let userID = UUID()
        let picture = Self.picture()
        let started = Gate()
        let release = Gate()
        let fetches = Counter()

        let store = ProfileAvatarStore(
            cache: Self.cache(),
            mintURL: { _, _ in URL(string: "https://example.test/avatar")! },
            fetch: { url in
                fetches.increment()
                started.open()
                await release.wait()
                try Task.checkCancellation()
                return Self.reply(Self.bytes, for: url)
            }
        )

        let first = Task { await store.load(userID: userID, picture: picture) }
        await started.wait()

        let second = Task { () -> Data? in
            await store.load(userID: userID, picture: picture)
            return store.data(for: userID)
        }
        // Everything here is main-actor isolated, so one yield runs `second` up to its first
        // suspension — the point where it either joins the fetch or gives up on it.
        await Task.yield()

        first.cancel()
        release.open()

        #expect(await second.value == Self.bytes)
        #expect(fetches.value == 1)
    }

    /// The banner shows the original, not the avatar-sized rendition the same picture carries.
    @Test("A cover loads the original blob, independently of the avatar")
    func coverLoadsOriginalAndCachesApartFromAvatar() async {
        let userID = UUID()
        let picture = ProfilePicture(
            blobID: BlobID(uuid: UUID()),
            thumbnailBlobID: BlobID(uuid: UUID())
        )
        let minted = Counter()
        var mintedBlobs: [BlobID] = []
        var mintedContexts: [BlobAccessContext] = []

        let store = ProfileAvatarStore(
            cache: Self.cache(),
            coverCache: Self.cache(),
            mintURL: { blobID, subject in
                mintedBlobs.append(blobID)
                mintedContexts.append(subject.accessContext)
                minted.increment()
                return URL(string: "https://example.test/\(blobID)")!
            },
            fetch: { url in Self.reply(Self.bytes, for: url) }
        )

        await store.load(.cover(userID), picture: picture)

        #expect(mintedBlobs == [picture.blobID])
        #expect(mintedContexts == [.userProfile(userID)])
        #expect(store.data(for: AvatarSubject.cover(userID)) == Self.bytes)
        #expect(store.data(for: userID) == nil)

        await store.load(.user(userID), picture: picture)

        #expect(mintedBlobs == [picture.blobID, picture.thumbnailBlobID])
        #expect(store.data(for: userID) == Self.bytes)
        #expect(minted.value == 2)
    }

    /// A full-size cover in the avatar pool would evict thumbnails, which the pools are split to prevent.
    @Test("A cover is written to the cover pool, not the avatar pool")
    func coverUsesItsOwnPool() async {
        let userID = UUID()
        let picture = ProfilePicture(blobID: BlobID(uuid: UUID()), thumbnailBlobID: BlobID(uuid: UUID()))
        let avatarCache = Self.cache()
        let coverCache = Self.cache()

        let store = ProfileAvatarStore(
            cache: avatarCache,
            coverCache: coverCache,
            mintURL: { _, _ in URL(string: "https://example.test/cover")! },
            fetch: { url in Self.reply(Self.bytes, for: url) }
        )

        await store.load(.cover(userID), picture: picture)

        #expect(coverCache.holds(picture.blobID))
        #expect(!avatarCache.holds(picture.blobID))

        await store.load(.user(userID), picture: picture)

        #expect(avatarCache.holds(picture.thumbnailBlobID))
        #expect(!coverCache.holds(picture.thumbnailBlobID))
    }

    /// A group's cover is the chat's blob, so it must authorize through the chat, not a member.
    @Test("A group cover loads the original blob under the chat's context, into the cover pool")
    func groupCoverLoadsOriginalUnderChatContext() async {
        let conversationID = ConversationID(data: Data(repeating: 7, count: 32))
        let picture = ProfilePicture(blobID: BlobID(uuid: UUID()), thumbnailBlobID: BlobID(uuid: UUID()))
        let avatarCache = Self.cache()
        let coverCache = Self.cache()
        var mintedBlobs: [BlobID] = []
        var mintedContexts: [BlobAccessContext] = []

        let store = ProfileAvatarStore(
            cache: avatarCache,
            coverCache: coverCache,
            mintURL: { blobID, subject in
                mintedBlobs.append(blobID)
                mintedContexts.append(subject.accessContext)
                return URL(string: "https://example.test/\(blobID)")!
            },
            fetch: { url in Self.reply(Self.bytes, for: url) }
        )

        await store.load(.groupCover(conversationID), picture: picture)

        #expect(mintedBlobs == [picture.blobID])
        #expect(mintedContexts == [.chatProfile(conversationID)])
        #expect(store.data(for: AvatarSubject.groupCover(conversationID)) == Self.bytes)
        #expect(store.data(for: AvatarSubject.chat(conversationID)) == nil)
        #expect(coverCache.holds(picture.blobID))
        #expect(!avatarCache.holds(picture.blobID))
    }

    /// Bytes already on disk are the common case at launch, and paying for a round trip there would
    /// put a blurhash on screen for the length of one.
    @Test("Bytes already on disk need no fetch")
    func diskHitSkipsTheFetch() async {
        let userID = UUID()
        let picture = Self.picture()
        let cache = Self.cache()
        cache.write(Self.bytes, for: picture.thumbnailBlobID)

        let store = ProfileAvatarStore(
            cache: cache,
            mintURL: { _, _ in Issue.record("Minted a URL for bytes already on disk"); return nil },
            fetch: { url in Issue.record("Fetched bytes already on disk"); return Self.reply(Data(), for: url) }
        )

        await store.load(userID: userID, picture: picture)

        #expect(store.data(for: userID) == Self.bytes)
    }

    // MARK: - Failed downloads -

    /// A signed URL can expire between minting and fetching, and CloudFront answers with a 403 and an
    /// XML body. Stored as the picture, that body drew nothing until the cache evicted it.
    @Test("A 403 mints a fresh URL once and caches only the image")
    func expiredURLIsRemintedOnce() async {
        let userID = UUID()
        let picture = Self.picture()
        let cache = Self.cache()
        let minted = Counter()

        let store = ProfileAvatarStore(
            cache: cache,
            mintURL: { _, _ in
                minted.increment()
                return URL(string: "https://example.test/avatar/\(minted.value)")!
            },
            fetch: { url in
                url.lastPathComponent == "1"
                    ? Self.reply(Self.accessDenied, status: 403, for: url)
                    : Self.reply(Self.bytes, for: url)
            }
        )

        await store.load(userID: userID, picture: picture)

        #expect(minted.value == 2)
        #expect(store.data(for: userID) == Self.bytes)
        #expect(cache.data(for: picture.thumbnailBlobID) == Self.bytes)
    }

    @Test("A second 403 gives up without caching anything")
    func repeated403CachesNothing() async {
        let userID = UUID()
        let picture = Self.picture()
        let cache = Self.cache()
        let minted = Counter()

        let store = ProfileAvatarStore(
            cache: cache,
            mintURL: { _, _ in
                minted.increment()
                return URL(string: "https://example.test/avatar")!
            },
            fetch: { url in Self.reply(Self.accessDenied, status: 403, for: url) }
        )

        await store.load(userID: userID, picture: picture)

        #expect(minted.value == 2)
        #expect(store.data(for: userID) == nil)
        #expect(!cache.holds(picture.thumbnailBlobID))
    }

    /// Only an expired signature is fixed by a fresh URL; any other error status would fail again.
    @Test("A non-403 error status is not retried and caches nothing")
    func otherErrorStatusIsNotRetried() async {
        let userID = UUID()
        let picture = Self.picture()
        let cache = Self.cache()
        let minted = Counter()

        let store = ProfileAvatarStore(
            cache: cache,
            mintURL: { _, _ in
                minted.increment()
                return URL(string: "https://example.test/avatar")!
            },
            fetch: { url in Self.reply(Data("Service Unavailable".utf8), status: 503, for: url) }
        )

        await store.load(userID: userID, picture: picture)

        #expect(minted.value == 1)
        #expect(store.data(for: userID) == nil)
        #expect(!cache.holds(picture.thumbnailBlobID))
    }

    @Test("A 200 whose body is not an image caches nothing")
    func nonImageBodyIsNotCached() async {
        let userID = UUID()
        let picture = Self.picture()
        let cache = Self.cache()

        let store = ProfileAvatarStore(
            cache: cache,
            mintURL: { _, _ in URL(string: "https://example.test/avatar")! },
            fetch: { url in Self.reply(Data("<html>captive portal</html>".utf8), for: url) }
        )

        await store.load(userID: userID, picture: picture)

        #expect(store.data(for: userID) == nil)
        #expect(!cache.holds(picture.thumbnailBlobID))
    }

    /// Devices already hold error bodies cached under avatar blob ids, and a disk hit never fetched,
    /// so those avatars would stay broken until eviction or logout.
    @Test("Cached bytes that are not an image are fetched again")
    func poisonedEntryIsRefetched() async {
        let userID = UUID()
        let picture = Self.picture()
        let cache = Self.cache()
        cache.write(Self.accessDenied, for: picture.thumbnailBlobID)

        let store = ProfileAvatarStore(
            cache: cache,
            mintURL: { _, _ in URL(string: "https://example.test/avatar")! },
            fetch: { url in Self.reply(Self.bytes, for: url) }
        )

        await store.load(userID: userID, picture: picture)

        #expect(store.data(for: userID) == Self.bytes)
        #expect(cache.data(for: picture.thumbnailBlobID) == Self.bytes)
    }

    @Test("Cached bytes that are not an image are evicted even when the refetch fails")
    func poisonedEntryIsEvictedWhenRefetchFails() async {
        let userID = UUID()
        let picture = Self.picture()
        let cache = Self.cache()
        cache.write(Self.accessDenied, for: picture.thumbnailBlobID)

        let store = ProfileAvatarStore(
            cache: cache,
            mintURL: { _, _ in URL(string: "https://example.test/avatar")! },
            fetch: { _ in throw URLError(.notConnectedToInternet) }
        )

        await store.load(userID: userID, picture: picture)

        #expect(store.data(for: userID) == nil)
        #expect(!cache.holds(picture.thumbnailBlobID))
    }
}
