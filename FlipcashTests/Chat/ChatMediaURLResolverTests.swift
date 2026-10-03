//
//  ChatMediaURLResolverTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
import FlipcashCore
@testable import FlipcashUI

@Suite("Chat photo URL resolver")
@MainActor
struct ChatMediaURLResolverTests {

    private let blobID = BlobID(data: Data([1]))
    private let url = URL(string: "https://example.com/a.jpg")!

    /// Records every blob the resolver asks for.
    @MainActor
    private final class FetchSpy {
        var calls: [BlobID] = []
    }

    private func photo(isRedacted: Bool) -> ChatMediaContent {
        ChatMediaContent(blobID: blobID, width: 100, height: 100, blurhash: nil, caption: nil, isRedacted: isRedacted)
    }

    @Test("A BlurHash-only row never fetches")
    func blurhashOnlyRowNeverFetches() async {
        let spy = FetchSpy()
        let url = url
        let resolver = ChatMediaURLResolver { id in
            spy.calls.append(id)
            return url
        }

        #expect(resolver.location(for: photo(isRedacted: true), canReact: true) { _ in }?.url == nil)
        #expect(resolver.location(for: photo(isRedacted: false), canReact: false) { _ in }?.url == nil)

        // Give any stray fetch task a chance to run before asserting none did.
        await Task.yield()
        #expect(spy.calls.isEmpty)
    }

    @Test("Joining fetches once, then serves from the cache")
    func joiningFetchesOnceThenServesFromCache() async {
        let spy = FetchSpy()
        let url = url
        let resolver = ChatMediaURLResolver { id in
            spy.calls.append(id)
            return url
        }
        let photo = photo(isRedacted: false)

        #expect(resolver.location(for: photo, canReact: false) { _ in }?.url == nil)

        let resolved = await withCheckedContinuation { continuation in
            let immediate = resolver.location(for: photo, canReact: true) { continuation.resume(returning: $0.url) }
            #expect(immediate == nil)
            // A second dequeue while the first fetch is in flight does not start another.
            #expect(resolver.location(for: photo, canReact: true) { _ in }?.url == nil)
        }
        #expect(resolved == url)

        #expect(resolver.location(for: photo, canReact: true) { _ in }?.url == url)
        #expect(spy.calls == [blobID])
    }

    @Test("A quote's thumbnail never fetches for a redacted original, a previewer, or a non-photo")
    func quoteThumbnailNeverFetchesWhenBlurhashOnly() async {
        let spy = FetchSpy()
        let url = url
        let resolver = ChatMediaURLResolver { id in
            spy.calls.append(id)
            return url
        }

        #expect(resolver.thumbnailLocation(for: .media(thumbnailBlobID: nil, sealed: nil), canReact: true) { _ in }?.url == nil)
        #expect(resolver.thumbnailLocation(for: .media(thumbnailBlobID: blobID, sealed: nil), canReact: false) { _ in }?.url == nil)
        #expect(resolver.thumbnailLocation(for: .text, canReact: true) { _ in }?.url == nil)
        #expect(resolver.thumbnailLocation(for: .unavailable, canReact: true) { _ in }?.url == nil)

        await Task.yield()
        #expect(spy.calls.isEmpty)
    }

    @Test("A quote's thumbnail shares the photo row's cached URL")
    func quoteThumbnailSharesTheRowCache() async {
        let spy = FetchSpy()
        let url = url
        let resolver = ChatMediaURLResolver { id in
            spy.calls.append(id)
            return url
        }

        let resolved = await withCheckedContinuation { continuation in
            let immediate = resolver.thumbnailLocation(for: .media(thumbnailBlobID: blobID, sealed: nil), canReact: true) {
                continuation.resume(returning: $0.url)
            }
            #expect(immediate == nil)
        }
        #expect(resolved == url)

        #expect(resolver.location(for: photo(isRedacted: false), canReact: true) { _ in }?.url == url)
        #expect(spy.calls == [blobID])
    }

    @Test("The composer's reply strip waits for the thumbnail, and never fetches a redacted one")
    func awaitedThumbnail() async {
        let spy = FetchSpy()
        let url = url
        let resolver = ChatMediaURLResolver { id in
            spy.calls.append(id)
            return url
        }

        #expect(await resolver.thumbnailLocation(for: .media(thumbnailBlobID: nil, sealed: nil), canReact: true)?.url == nil)
        #expect(spy.calls.isEmpty)

        #expect(await resolver.thumbnailLocation(for: .media(thumbnailBlobID: blobID, sealed: nil), canReact: true)?.url == url)
        #expect(await resolver.thumbnailLocation(for: .media(thumbnailBlobID: blobID, sealed: nil), canReact: true)?.url == url)
        #expect(spy.calls == [blobID])
    }

    @Test("Every caller waiting on one fetch hears when it lands")
    func everyWaiterIsCalledBack() async {
        let url = url
        let resolver = ChatMediaURLResolver { _ in url }
        let photo = photo(isRedacted: false)

        let (row, quote) = await withCheckedContinuation { continuation in
            var row: URL?
            let immediate = resolver.location(for: photo, canReact: true) { row = $0.url }
            #expect(immediate == nil)
            _ = resolver.thumbnailLocation(for: .media(thumbnailBlobID: blobID, sealed: nil), canReact: true) { quote in
                continuation.resume(returning: (row, quote.url))
            }
        }
        #expect(row == url)
        #expect(quote == url)
    }

    @Test("An encrypted photo waits on the chat's decryption, fetches it once, and decrypts with its blob")
    func encryptedPhotoDecrypts() async throws {
        let url = url
        let sealed = SealedBlob(senderID: UserID(), plaintextSize: 3)
        let decryptCalls = FetchSpy()
        let resolver = ChatMediaURLResolver(
            fetch: { _ in url },
            decrypt: {
                decryptCalls.calls.append(BlobID(data: Data()))
                return { blob, blobID, sealed in Data(blob.reversed()) + blobID.data + Data([UInt8(sealed.plaintextSize)]) }
            }
        )
        let sealedPhoto = ChatMediaContent(blobID: blobID, width: 1, height: 1, blurhash: nil, caption: nil, isRedacted: false, sealed: sealed)

        let location = await withCheckedContinuation { continuation in
            let immediate = resolver.location(for: sealedPhoto, canReact: true) { continuation.resume(returning: $0) }
            #expect(immediate == nil)
        }
        #expect(location.url == url)
        let decrypt = try #require(location.decrypt)
        #expect(try decrypt(Data([1, 2])) == Data([2, 1, 1, 3]))

        let cached = try #require(resolver.location(for: sealedPhoto, canReact: true) { _ in })
        #expect(cached.decrypt != nil)
        #expect(await resolver.thumbnailLocation(for: .media(thumbnailBlobID: blobID, sealed: sealed), canReact: true)?.decrypt != nil)
        #expect(decryptCalls.calls.count == 1)
        #expect(resolver.location(for: photo(isRedacted: false), canReact: true) { _ in }?.decrypt == nil)
    }

    @Test("An encrypted photo stays on its BlurHash while the chat's key is unknown")
    func encryptedPhotoWithoutKey() async {
        let url = url
        let resolver = ChatMediaURLResolver(fetch: { _ in url }, decrypt: { nil })
        let sealed = SealedBlob(senderID: UserID(), plaintextSize: 3)
        let photo = ChatMediaContent(blobID: blobID, width: 1, height: 1, blurhash: nil, caption: nil, isRedacted: false, sealed: sealed)

        let location = await resolver.thumbnailLocation(for: .media(thumbnailBlobID: blobID, sealed: sealed), canReact: true)
        #expect(location == nil)
        #expect(resolver.location(for: photo, canReact: true) { _ in } == nil)
    }
}
