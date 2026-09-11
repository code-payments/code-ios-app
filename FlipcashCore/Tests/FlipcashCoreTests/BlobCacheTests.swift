//
//  BlobCacheTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
@testable import FlipcashCore

@Suite("Blob cache")
struct BlobCacheTests {

    private func cache(limitBytes: Int = 1 << 20) -> BlobCache {
        BlobCache(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("blobs-\(UUID().uuidString)", isDirectory: true),
            limitBytes: limitBytes
        )
    }

    private func blob(_ byte: UInt8) -> BlobID {
        BlobID(data: Data(repeating: byte, count: 16))
    }

    // MARK: - Round trip -

    @Test func writtenBytesReadBack() {
        let cache = cache()
        cache.write(Data([1, 2, 3]), for: blob(1))

        #expect(cache.data(for: blob(1)) == Data([1, 2, 3]))
    }

    @Test func missReturnsNil() {
        #expect(cache().data(for: blob(1)) == nil)
    }

    @Test func blobsDoNotCollide() {
        let cache = cache()
        cache.write(Data([1]), for: blob(1))
        cache.write(Data([2]), for: blob(2))

        #expect(cache.data(for: blob(1)) == Data([1]))
        #expect(cache.data(for: blob(2)) == Data([2]))
    }

    /// The app and the notification extension are separate processes holding separate instances over
    /// the same App Group directory. A write is only useful if the other side can read it, so the
    /// bytes have to live on disk under a name derived from the blob id alone — no in-process index.
    @Test func anotherInstanceOverTheSameDirectoryReadsTheSameBytes() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("blobs-\(UUID().uuidString)", isDirectory: true)
        let writer = BlobCache(directory: directory, limitBytes: 1 << 20)
        let reader = BlobCache(directory: directory, limitBytes: 1 << 20)

        writer.write(Data([9, 9, 9]), for: blob(4))

        #expect(reader.data(for: blob(4)) == Data([9, 9, 9]))
    }

    // MARK: - Clearing -

    @Test func clearDropsEverything() {
        let cache = cache()
        cache.write(Data([1]), for: blob(1))
        cache.clear()

        #expect(cache.data(for: blob(1)) == nil)
    }

    /// Logout clears the cache and the account stays usable, so a write after one has to recreate the
    /// directory rather than silently failing for the rest of the process.
    @Test func writingAfterClearRecreatesTheCache() {
        let cache = cache()
        cache.write(Data([1]), for: blob(1))
        cache.clear()
        cache.write(Data([2]), for: blob(2))

        #expect(cache.data(for: blob(2)) == Data([2]))
    }

    // MARK: - Eviction -

    /// Avatars accumulate for every counterparty the user ever sees, so the directory needs a ceiling.
    @Test func writingPastTheLimitEvicts() {
        let cache = cache(limitBytes: 300)
        for byte in UInt8(1)...UInt8(6) {
            cache.write(Data(repeating: byte, count: 100), for: blob(byte))
        }

        let remaining = (UInt8(1)...UInt8(6)).filter { cache.data(for: blob($0)) != nil }
        #expect(remaining.count < 6)
    }

    /// Eviction takes the coldest entries, so the picture drawn on the screen the user just left is
    /// still there when they come back to it.
    @Test func evictionKeepsTheMostRecentlyUsed() {
        let cache = cache(limitBytes: 300)
        cache.write(Data(repeating: 1, count: 100), for: blob(1))
        cache.write(Data(repeating: 2, count: 100), for: blob(2))

        // Reading blob 1 makes blob 2 the coldest entry.
        _ = cache.data(for: blob(1))
        cache.write(Data(repeating: 3, count: 100), for: blob(3))
        cache.write(Data(repeating: 4, count: 100), for: blob(4))

        #expect(cache.data(for: blob(4)) == Data(repeating: 4, count: 100))
        #expect(cache.data(for: blob(1)) != nil)
    }

    /// A single blob larger than the whole budget must not evict itself into a permanent miss, or the
    /// caller re-downloads it on every read.
    @Test func anOversizedBlobIsNotCached() {
        let cache = cache(limitBytes: 100)
        cache.write(Data(repeating: 1, count: 500), for: blob(1))
        cache.write(Data(repeating: 2, count: 50), for: blob(2))

        #expect(cache.data(for: blob(2)) == Data(repeating: 2, count: 50))
    }

    // MARK: - Kinds -

    /// Each kind of blob gets its own directory and its own ceiling. Sharing one pool would let a
    /// scroll through an image-heavy conversation — megabytes apiece — evict every avatar on the
    /// device, which is the bug this cache exists to fix.
    @Test func oneKindOverItsLimitDoesNotEvictAnother() {
        let avatars = cache(limitBytes: 1 << 20)
        let images = cache(limitBytes: 4096)

        avatars.write(Data(repeating: 0xAA, count: 1024), for: blob(1))

        // Enough writes to push `images` well past its own ceiling.
        for byte in UInt8(10)...UInt8(20) {
            images.write(Data(repeating: byte, count: 2048), for: blob(byte))
        }

        #expect(avatars.data(for: blob(1))?.count == 1024)
    }
}
