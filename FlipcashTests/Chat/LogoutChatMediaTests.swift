//
//  LogoutChatMediaTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import UIKit
import Kingfisher
@testable import FlipcashUI
@testable import Flipcash

/// Chat photos are cached decrypted, keyed by blob id, in two Kingfisher caches. Logout cleared
/// `BlobCache` but left both, so the next account on the device inherited the last one's photos.
///
/// The caches are process-wide and other suites write them in parallel, so this checks the entries
/// it seeded rather than that each cache is empty.
///
/// `logout()` also clears `CoinbaseOrderEmail.unverifiedEmail`, which
/// `EmailVerificationViewModelTests` reads across an `await`. The test is synchronous on the main
/// actor, so putting it back before returning hides the reset from every other main-actor test.
@MainActor
@Suite("Logout clears cached chat photos")
struct LogoutChatMediaTests {

    @Test("Logging out empties both chat photo caches, in memory and on disk")
    func logoutEmptiesChatPhotoCaches() throws {
        let key = "chat-media-test-\(UUID().uuidString)"
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { _ in }
        let data = try #require(image.pngData())
        let caches = [
            ("chat-media", ChatMediaImageSource.cache),
            ("chat-media-originals", ChatMediaImageSource.originals),
        ]

        for (_, cache) in caches {
            cache.memoryStorage.store(value: image, forKey: key)
            try cache.diskStorage.store(value: data, forKey: key)
            #expect(cache.memoryStorage.isCached(forKey: key))
            #expect(cache.diskStorage.isCached(forKey: key))
        }

        let priorEmail = CoinbaseOrderEmail.unverifiedEmail
        defer { CoinbaseOrderEmail.unverifiedEmail = priorEmail }

        SessionAuthenticator(container: .mock).logout()

        for (name, cache) in caches {
            #expect(!cache.memoryStorage.isCached(forKey: key), "\(name) memory")
            #expect(!cache.diskStorage.isCached(forKey: key), "\(name) disk")
        }
    }

    @Test("Logging out empties the URL caches photo downloads go through")
    func logoutEmptiesURLCaches() throws {
        let caches = [
            ("URLCache.shared", URLCache.shared),
            ("RemoteImageCache", RemoteImageCache.urlCache),
        ]
        let seeded = try caches.map { name, cache in (name, cache, try seed(cache, name: name)) }

        let priorEmail = CoinbaseOrderEmail.unverifiedEmail
        defer { CoinbaseOrderEmail.unverifiedEmail = priorEmail }

        SessionAuthenticator(container: .mock).logout()

        for (name, cache, request) in seeded {
            #expect(cache.cachedResponse(for: request) == nil, "\(name)")
        }
    }

    /// Stores a cacheable response in `cache`'s memory under a URL no other cache or test uses.
    /// Memory only, because with disk storage allowed the entry sometimes survived
    /// `removeAllCachedResponses()` when the test read it back straight afterwards.
    private func seed(_ cache: URLCache, name: String) throws -> URLRequest {
        let url = try #require(URL(string: "https://example.com/logout-test/\(UUID().uuidString)"))
        let response = try #require(HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Cache-Control": "max-age=3600"]
        ))
        let request = URLRequest(url: url)
        let cached = CachedURLResponse(response: response, data: Data([1, 2, 3]), storagePolicy: .allowedInMemoryOnly)
        cache.storeCachedResponse(cached, for: request)
        try #require(cache.cachedResponse(for: request) != nil, "\(name) seeded")
        return request
    }
}
