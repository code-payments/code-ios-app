//
//  ChatMediaURLExpiryTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
import Kingfisher
import FlipcashCore
@testable import FlipcashUI

/// A minted photo URL is signed with a short life. These pin when the resolver stops handing one
/// out and mints again: before it expires, and once after the CDN refuses it.
@Suite("Chat photo URL expiry")
@MainActor
struct ChatMediaURLExpiryTests {

    private let blobID = BlobID(data: Data([7]))
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    /// Mints a new URL per call, each expiring `lifetime` after `clock.now` (nil for none).
    @MainActor
    private final class Minter {
        var clock: Date
        var lifetime: TimeInterval?
        private(set) var calls = 0

        init(clock: Date, lifetime: TimeInterval?) {
            self.clock = clock
            self.lifetime = lifetime
        }

        func mint(_: BlobID) -> BlobDownloadLink {
            calls += 1
            return BlobDownloadLink(
                url: URL(string: "https://cdn.example.invalid/photo?sig=\(calls)")!,
                expiresAt: lifetime.map { clock.addingTimeInterval($0) }
            )
        }
    }

    private func resolver(_ minter: Minter) -> ChatMediaURLResolver {
        ChatMediaURLResolver(fetch: { minter.mint($0) }, now: { minter.clock })
    }

    private var photo: ChatMediaContent {
        ChatMediaContent(blobID: blobID, width: 100, height: 100, blurhash: nil, caption: nil, isRedacted: false)
    }

    private func resolve(_ resolver: ChatMediaURLResolver) async -> ChatMediaLocation? {
        await resolver.location(for: photo, canReact: true)
    }

    // MARK: - Expiry -

    @Test("A URL still well inside its life is served from the cache")
    func freshURLIsReused() async {
        let minter = Minter(clock: start, lifetime: 300)
        let resolver = resolver(minter)

        let first = await resolve(resolver)
        minter.clock = start.addingTimeInterval(200)
        let second = await resolve(resolver)

        #expect(minter.calls == 1)
        #expect(second?.url == first?.url)
    }

    @Test("A URL within 30 seconds of expiring is minted again")
    func nearlyExpiredURLRemints() async {
        let minter = Minter(clock: start, lifetime: 300)
        let resolver = resolver(minter)

        let first = await resolve(resolver)
        minter.clock = start.addingTimeInterval(275)
        let second = await resolve(resolver)

        #expect(minter.calls == 2)
        #expect(second?.url != nil)
        #expect(second?.url != first?.url)
    }

    @Test("A URL that arrives already expired is still handed out, and not minted again at once")
    func alreadyExpiredURLDoesNotLoop() async {
        // A device clock ahead of the server's reads every expiry as past.
        let minter = Minter(clock: start, lifetime: -60)
        let resolver = resolver(minter)

        let first = await resolve(resolver)
        let second = await resolve(resolver)

        #expect(first?.url != nil)
        #expect(second?.url == first?.url)
        #expect(minter.calls == 1)
    }

    @Test("A URL that arrives already expired is minted again once its minimum life is up")
    func alreadyExpiredURLRemintsLater() async {
        let minter = Minter(clock: start, lifetime: -60)
        let resolver = resolver(minter)

        _ = await resolve(resolver)
        minter.clock = start.addingTimeInterval(31)
        _ = await resolve(resolver)

        #expect(minter.calls == 2)
    }

    @Test("A URL with no expiry never expires")
    func urlWithoutExpiryIsKept() async {
        let minter = Minter(clock: start, lifetime: nil)
        let resolver = resolver(minter)

        _ = await resolve(resolver)
        minter.clock = start.addingTimeInterval(86_400)
        _ = await resolve(resolver)

        #expect(minter.calls == 1)
    }

    // MARK: - Refusal -

    @Test("A refused URL is minted again once")
    func refusedURLRemintsOnce() async throws {
        let minter = Minter(clock: start, lifetime: 300)
        let resolver = resolver(minter)

        let first = try #require(await resolve(resolver))
        #expect(first.reportRefused())
        let second = try #require(await resolve(resolver))
        #expect(minter.calls == 2)
        #expect(second.url != first.url)

        // The URL minted for a refusal is refused too: something other than expiry is wrong, so
        // stop asking.
        #expect(!second.reportRefused())
        let third = await resolve(resolver)
        #expect(minter.calls == 2)
        #expect(third?.url == second.url)
    }

    @Test("A refusal of a URL already replaced leaves the new one alone")
    func staleRefusalKeepsTheNewURL() async throws {
        let minter = Minter(clock: start, lifetime: 300)
        let resolver = resolver(minter)

        let first = try #require(await resolve(resolver))
        minter.clock = start.addingTimeInterval(280)
        let second = try #require(await resolve(resolver))
        #expect(minter.calls == 2)

        #expect(!first.reportRefused())
        let third = await resolve(resolver)
        #expect(minter.calls == 2)
        #expect(third?.url == second.url)
    }

    // MARK: - Recognising a refusal -

    @Test("A 403 is a refusal on the plaintext and the sealed path, and nothing else is")
    func refusalIsA403() {
        let url = URL(string: "https://cdn.example.invalid/photo")!
        func status(_ code: Int) -> KingfisherError {
            .responseError(reason: .invalidHTTPStatusCode(
                response: HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: nil)!
            ))
        }
        func sealed(_ code: Int) -> KingfisherError {
            .imageSettingError(reason: .dataProviderError(
                provider: CachedOnlyProvider(cacheKey: "k"),
                error: ChatMediaHTTPError(status: code)
            ))
        }

        #expect(ChatMediaImageSource.isRefused(status(403)))
        #expect(ChatMediaImageSource.isRefused(sealed(403)))
        #expect(!ChatMediaImageSource.isRefused(status(404)))
        #expect(!ChatMediaImageSource.isRefused(sealed(500)))
    }
}
