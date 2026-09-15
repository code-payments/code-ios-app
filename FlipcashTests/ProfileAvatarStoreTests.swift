//
//  ProfileAvatarStoreTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("ProfileAvatarStore")
struct ProfileAvatarStoreTests {

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

    private static let bytes = Data([1, 2, 3, 4])

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
            fetch: { _ in
                started.open()
                await release.wait()
                try Task.checkCancellation()
                return Self.bytes
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
            fetch: { _ in
                fetches.increment()
                started.open()
                await release.wait()
                try Task.checkCancellation()
                return Self.bytes
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
            fetch: { _ in Issue.record("Fetched bytes already on disk"); return Data() }
        )

        await store.load(userID: userID, picture: picture)

        #expect(store.data(for: userID) == Self.bytes)
    }
}
