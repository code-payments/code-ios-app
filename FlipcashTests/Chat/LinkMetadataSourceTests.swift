//
//  LinkMetadataSourceTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@Suite
struct LinkMetadataSourceTests {

    private static let page = Data("<html><head><title>Hello</title><meta property=\"og:image\" content=\"https://img.example.com/a.png\"></head></html>".utf8)

    @Test func parsesAnHTMLPage() async throws {
        let client = FakeClient(["https://example.com/": html(Self.page)])
        let state = try await source(client).metadata(for: URL(string: "https://example.com/")!)
        guard case .resolved(let resolved) = state else { Issue.record("\(state)"); return }
        #expect(resolved.title == "Hello")
        #expect(resolved.host == "example.com")
    }

    @Test func followsThreeRedirectsButNotFour() async throws {
        var chain = (0..<3).reduce(into: [String: PinnedResponse]()) { routes, i in
            routes["https://example.com/\(i)"] = redirect("/\(i + 1)")
        }
        chain["https://example.com/3"] = html(Self.page)
        let three = try await source(FakeClient(chain)).metadata(for: URL(string: "https://example.com/0")!)
        #expect(three != .none)

        chain["https://example.com/3"] = redirect("/4")
        chain["https://example.com/4"] = html(Self.page)
        let client = FakeClient(chain)
        let four = try await source(client).metadata(for: URL(string: "https://example.com/0")!)
        #expect(four == .none)
        #expect(client.requested == (0...3).map { "https://example.com/\($0)" })
    }

    @Test func redirectToAnIneligibleHostIsNone() async throws {
        let client = FakeClient(["https://example.com/": redirect("https://localhost/")])
        #expect(try await source(client).metadata(for: URL(string: "https://example.com/")!) == .none)
        #expect(client.requested == ["https://example.com/"])
    }

    @Test func redirectToHTTPIsNone() async throws {
        let client = FakeClient(["https://example.com/": redirect("http://example.com/")])
        #expect(try await source(client).metadata(for: URL(string: "https://example.com/")!) == .none)
    }

    @Test func percentEscapedHostIsNeverFetched() async throws {
        let client = FakeClient([:])
        #expect(try await source(client).metadata(for: URL(string: "https://ex%61mple.com/")!) == .none)
        #expect(client.requested.isEmpty)
    }

    @Test func nonIdentityEncodingIsNone() async throws {
        let client = FakeClient(["https://example.com/": html(Self.page, extra: ["content-encoding": "gzip"])])
        #expect(try await source(client).metadata(for: URL(string: "https://example.com/")!) == .none)
    }

    @Test func notHTMLIsNone() async throws {
        let client = FakeClient(["https://example.com/": PinnedResponse(status: 200, headers: ["content-type": "application/pdf"], body: Self.page, truncated: false)])
        #expect(try await source(client).metadata(for: URL(string: "https://example.com/")!) == .none)
    }

    @Test func clientErrorIsNone() async throws {
        let client = FakeClient(["https://example.com/": PinnedResponse(status: 404, headers: [:], body: Data(), truncated: false)])
        #expect(try await source(client).metadata(for: URL(string: "https://example.com/")!) == .none)
    }

    @Test func serverErrorThrows() async throws {
        let client = FakeClient(["https://example.com/": PinnedResponse(status: 503, headers: [:], body: Data(), truncated: false)])
        await #expect(throws: WebLinkHTTPStatus(code: 503)) {
            try await source(client).metadata(for: URL(string: "https://example.com/")!)
        }
    }

    @Test func flagOffThrowsWithoutFetching() async throws {
        let client = FakeClient([:])
        await #expect(throws: WebLinkPreviewsDisabled.self) {
            try await PinnedLinkMetadataSource(client: client, limiter: FetchLimiter(limit: 1), isEnabled: { false })
                .metadata(for: URL(string: "https://example.com/")!)
        }
        #expect(client.requested.isEmpty)
    }

    @Test func anImageOnDiskIsReadWithoutFetching() async {
        let disk = WebImageDiskCache(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let url = URL(string: "https://img.example.com/a.png")!
        disk.store(Data([9]), for: url)
        let client = FakeClient([:])
        #expect(await WebImageSource(client: client, limiter: FetchLimiter(limit: 1), disk: disk).data(for: url) == Data([9]))
        #expect(client.requested.isEmpty)
    }

    @Test func aFetchedImageIsWrittenToDiskAndAFailureIsNot() async {
        let disk = WebImageDiskCache(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let good = URL(string: "https://img.example.com/a.png")!
        let html = URL(string: "https://img.example.com/b.png")!
        let client = FakeClient([
            good.absoluteString: PinnedResponse(status: 200, headers: ["content-type": "image/png"], body: Data([1]), truncated: false),
            html.absoluteString: PinnedResponse(status: 200, headers: ["content-type": "text/html"], body: Data([2]), truncated: false),
        ])
        let source = WebImageSource(client: client, limiter: FetchLimiter(limit: 1), disk: disk)
        _ = await source.data(for: good)
        _ = await source.data(for: html)
        #expect(disk.data(for: good) == Data([1]))
        #expect(disk.data(for: html) == nil)
    }

    @Test func imageNeedsAnImageContentTypeAndFullBody() async {
        let bytes = Data([1, 2, 3])
        let ok = FakeClient(["https://img.example.com/a.png": PinnedResponse(status: 200, headers: ["content-type": "image/png"], body: bytes, truncated: false)])
        #expect(await WebImageSource(client: ok, limiter: FetchLimiter(limit: 1)).data(for: URL(string: "https://img.example.com/a.png")!) == bytes)

        let truncated = FakeClient(["https://img.example.com/a.png": PinnedResponse(status: 200, headers: ["content-type": "image/png"], body: bytes, truncated: true)])
        #expect(await WebImageSource(client: truncated, limiter: FetchLimiter(limit: 1)).data(for: URL(string: "https://img.example.com/a.png")!) == nil)

        let html = FakeClient(["https://img.example.com/a.png": PinnedResponse(status: 200, headers: ["content-type": "text/html"], body: bytes, truncated: false)])
        #expect(await WebImageSource(client: html, limiter: FetchLimiter(limit: 1)).data(for: URL(string: "https://img.example.com/a.png")!) == nil)

        let gzip = FakeClient(["https://img.example.com/a.png": PinnedResponse(status: 200, headers: ["content-type": "image/png", "content-encoding": "gzip"], body: bytes, truncated: false)])
        #expect(await WebImageSource(client: gzip, limiter: FetchLimiter(limit: 1)).data(for: URL(string: "https://img.example.com/a.png")!) == nil)
    }

    @Test func limiterHoldsConcurrencyToTheLimit() async throws {
        let limiter = FetchLimiter(limit: 2)
        let counter = Counter()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    try await limiter.run {
                        await counter.enter()
                        try await Task.sleep(for: .milliseconds(10))
                        await counter.leave()
                    }
                }
            }
            try await group.waitForAll()
        }
        #expect(await counter.peak == 2)
    }

    /// D12: a port other than 443 is never fetched, on the first URL or a hop.
    @Test func nonDefaultPortIsNone() async throws {
        let client = FakeClient(["https://example.com/": redirect("https://example.com:8443/")])
        #expect(try await source(client).metadata(for: URL(string: "https://example.com:6379/")!) == .none)
        #expect(client.requested.isEmpty)
        #expect(try await source(client).metadata(for: URL(string: "https://example.com/")!) == .none)
        #expect(client.requested == ["https://example.com/"])
    }

    /// D16: a relative Location keeps the current host, whatever its query holds.
    @Test func relativeLocationWithEscapesInItsQueryIsFollowed() async throws {
        let client = FakeClient([
            "https://example.com/": redirect("/redir?to=https://a%20b"),
            "https://example.com/redir?to=https://a%20b": html(Self.page),
        ])
        guard case .resolved = try await source(client).metadata(for: URL(string: "https://example.com/")!) else {
            Issue.record("expected a resolved card"); return
        }
    }

    @Test(arguments: ["//ex%61mple.org/x", "https:\\\\ex%61mple.org", "https://ex%61mple.org/"])
    func escapedOrBackslashLocationIsNone(_ location: String) async throws {
        let client = FakeClient(["https://example.com/": redirect(location)])
        #expect(try await source(client).metadata(for: URL(string: "https://example.com/")!) == .none)
        #expect(client.requested == ["https://example.com/"])
    }

    /// D17: every Content-Encoding value must be identity.
    @Test(arguments: ["identity, gzip", "", "identity, "])
    func anyNonIdentityOrEmptyEncodingTokenIsNone(_ encoding: String) async throws {
        let client = FakeClient(["https://example.com/": html(Self.page, extra: ["content-encoding": encoding])])
        #expect(try await source(client).metadata(for: URL(string: "https://example.com/")!) == .none)
    }

    /// D18: one deadline covers every hop, and running out throws so nothing is remembered.
    @Test func theDeadlineCoversTheWholeChain() async throws {
        let client = FakeClient([
            "https://example.com/": redirect("https://example.com/b"),
            "https://example.com/b": html(Self.page),
        ], delay: .milliseconds(150))
        await #expect(throws: URLError.self) {
            try await WebRedirects.follow(URL(string: "https://example.com/")!, client: client,
                                          accept: "text/html", maxBytes: 1024, deadline: .milliseconds(200))
        }
    }

    // MARK: - Helpers

    private func source(_ client: FakeClient) -> PinnedLinkMetadataSource {
        PinnedLinkMetadataSource(client: client, limiter: FetchLimiter(limit: 4), isEnabled: { true })
    }

    private func html(_ body: Data, extra: [String: String] = [:]) -> PinnedResponse {
        PinnedResponse(status: 200, headers: ["content-type": "text/html; charset=utf-8"].merging(extra) { $1 }, body: body, truncated: false)
    }

    private func redirect(_ location: String) -> PinnedResponse {
        PinnedResponse(status: 302, headers: ["location": location], body: Data(), truncated: false)
    }
}

private final class FakeClient: PinnedFetching, @unchecked Sendable {
    private let routes: [String: PinnedResponse]
    private let delay: Duration?
    private let lock = NSLock()
    private var _requested: [String] = []

    init(_ routes: [String: PinnedResponse], delay: Duration? = nil) {
        self.routes = routes
        self.delay = delay
    }

    var requested: [String] { lock.withLock { _requested } }

    func get(_ url: URL, accept: String, maxBytes: Int) async throws -> PinnedResponse {
        lock.withLock { _requested.append(url.absoluteString) }
        if let delay { try await Task.sleep(for: delay) }
        guard let response = routes[url.absoluteString] else { throw URLError(.cannotConnectToHost) }
        return response
    }
}

private actor Counter {
    private var open = 0
    private(set) var peak = 0

    func enter() {
        open += 1
        peak = max(peak, open)
    }

    func leave() {
        open -= 1
    }
}
