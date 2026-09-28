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

        #expect(resolver.url(for: photo(isRedacted: true), canReact: true) { _ in } == nil)
        #expect(resolver.url(for: photo(isRedacted: false), canReact: false) { _ in } == nil)

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

        #expect(resolver.url(for: photo, canReact: false) { _ in } == nil)

        let resolved = await withCheckedContinuation { continuation in
            let immediate = resolver.url(for: photo, canReact: true) { continuation.resume(returning: $0) }
            #expect(immediate == nil)
            // A second dequeue while the first fetch is in flight does not start another.
            #expect(resolver.url(for: photo, canReact: true) { _ in } == nil)
        }
        #expect(resolved == url)

        #expect(resolver.url(for: photo, canReact: true) { _ in } == url)
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

        #expect(resolver.thumbnailURL(for: .media(thumbnailBlobID: nil), canReact: true) { _ in } == nil)
        #expect(resolver.thumbnailURL(for: .media(thumbnailBlobID: blobID), canReact: false) { _ in } == nil)
        #expect(resolver.thumbnailURL(for: .text, canReact: true) { _ in } == nil)
        #expect(resolver.thumbnailURL(for: .unavailable, canReact: true) { _ in } == nil)

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
            let immediate = resolver.thumbnailURL(for: .media(thumbnailBlobID: blobID), canReact: true) {
                continuation.resume(returning: $0)
            }
            #expect(immediate == nil)
        }
        #expect(resolved == url)

        #expect(resolver.url(for: photo(isRedacted: false), canReact: true) { _ in } == url)
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

        #expect(await resolver.thumbnailURL(for: .media(thumbnailBlobID: nil), canReact: true) == nil)
        #expect(spy.calls.isEmpty)

        #expect(await resolver.thumbnailURL(for: .media(thumbnailBlobID: blobID), canReact: true) == url)
        #expect(await resolver.thumbnailURL(for: .media(thumbnailBlobID: blobID), canReact: true) == url)
        #expect(spy.calls == [blobID])
    }

    @Test("Every caller waiting on one fetch hears when it lands")
    func everyWaiterIsCalledBack() async {
        let url = url
        let resolver = ChatMediaURLResolver { _ in url }
        let photo = photo(isRedacted: false)

        let (row, quote) = await withCheckedContinuation { continuation in
            var row: URL?
            let immediate = resolver.url(for: photo, canReact: true) { row = $0 }
            #expect(immediate == nil)
            _ = resolver.thumbnailURL(for: .media(thumbnailBlobID: blobID), canReact: true) { quote in
                continuation.resume(returning: (row, quote))
            }
        }
        #expect(row == url)
        #expect(quote == url)
    }
}
