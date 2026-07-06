import Testing
import Foundation
import LinkPresentation
@testable import FlipcashUI

@MainActor
@Suite("LinkMetadataCache")
struct LinkMetadataCacheTests {

    private func url(_ s: String) -> URL { URL(string: s)! }

    @Test("Concurrent requests for the same URL fetch once")
    func dedup_singleFetch() async {
        let fetcher = CountingFetcher()
        let cache = LinkMetadataCache(fetcher: fetcher)
        let u = url("https://apple.com")
        async let a = cache.metadata(for: u)
        async let b = cache.metadata(for: u)
        async let c = cache.metadata(for: u)
        _ = await (a, b, c)
        #expect(fetcher.callCount == 1)
    }

    @Test("A cached result is reused without refetching")
    func cacheHit_noRefetch() async {
        let fetcher = CountingFetcher()
        let cache = LinkMetadataCache(fetcher: fetcher)
        let u = url("https://apple.com")
        _ = await cache.metadata(for: u)
        let second = await cache.metadata(for: u)
        #expect(fetcher.callCount == 1)
        #expect(second?.value.url == u)
    }

    @Test("A failed fetch returns nil and is not cached, so a later request retries")
    func failure_notCached() async {
        let fetcher = CountingFetcher(shouldFail: true)
        let cache = LinkMetadataCache(fetcher: fetcher)
        let u = url("https://apple.com")
        let first = await cache.metadata(for: u)
        let second = await cache.metadata(for: u)
        #expect(first == nil)
        #expect(second == nil)
        #expect(fetcher.callCount == 2)
    }

    @Test("Metadata with no image or icon provider returns no hero image, without touching the network")
    func image_noProvider_returnsNil() async {
        let cache = LinkMetadataCache(fetcher: CountingFetcher())
        let u = url("https://apple.com")
        let metadata = LPLinkMetadata()
        metadata.url = u
        let image = await cache.image(for: u, from: metadata)
        #expect(image == nil)
    }
}

private final class CountingFetcher: LinkMetadataFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var _callCount = 0
    let shouldFail: Bool

    var callCount: Int { lock.withLock { _callCount } }

    init(shouldFail: Bool = false) { self.shouldFail = shouldFail }

    func fetch(_ url: URL) async throws -> SendableLinkMetadata {
        lock.withLock { _callCount += 1 }
        if shouldFail { throw URLError(.badServerResponse) }
        let metadata = LPLinkMetadata()
        metadata.url = url
        metadata.originalURL = url
        metadata.title = "Example"
        return SendableLinkMetadata(metadata)
    }
}
