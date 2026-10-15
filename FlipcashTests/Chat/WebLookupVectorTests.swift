//
//  WebLookupVectorTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

/// Runs the `lookups` vectors in link_metadata.json through the real source and response reader.
@Suite("WebLookupVectors")
struct WebLookupVectorTests {

    private final class BundleToken {}

    struct Card: Decodable, Equatable {
        let title: String
        let description: String?
        let imageUrl: String?
        let host: String
    }

    struct Entry: Decodable {
        let key: String
        let state: String
        let card: Card?
    }

    struct Response: Decodable {
        let url: String
        let status: Int
        let html: String?
        let contentType: String?
        let location: String?
        let fillBytes: Int?
    }

    struct Lookup: Decodable, CustomTestStringConvertible {
        let name: String
        let url: String
        let cachedBefore: [Entry]
        let responses: [Response]
        let fetches: [String]
        let result: String
        let card: Card?
        let cached: [Entry]

        var testDescription: String { name }
    }

    private struct Fixture: Decodable { let lookups: [Lookup] }

    /// Every lookup except those that start from a remembered home answer: the sender fetches
    /// fresh each time, so it holds none.
    static let lookups: [Lookup] = {
        let bundle = Bundle(for: BundleToken.self)
        guard let url = bundle.url(forResource: "link_metadata", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let fixture = try? JSONDecoder().decode(Fixture.self, from: data) else { return [] }
        return fixture.lookups.filter { $0.cachedBefore.isEmpty }
    }()

    @Test func fixtureIsLoaded() {
        #expect(Self.lookups.count == 18)
    }

    @Test(arguments: lookups)
    func looksUpLikeTheFixture(_ lookup: Lookup) async throws {
        let client = ScriptedClient(lookup.responses)
        let source = PinnedLinkMetadataSource(client: client, limiter: FetchLimiter(limit: 4))
        let url = try #require(URL(string: lookup.url))

        let page: LinkCard.Web.Resolved?
        var failed = false
        do {
            page = try await source.metadata(for: url)
        } catch {
            page = nil
            failed = true
        }

        #expect(client.requested == lookup.fetches)
        #expect(client.overread.isEmpty, "read past the cap: \(client.overread)")

        switch lookup.result {
        case "failure":
            #expect(failed)
        case "none":
            #expect(!failed)
            #expect(page == nil)
        default:
            #expect(Self.card(page) == lookup.card)
        }
    }

    static func card(_ page: LinkCard.Web.Resolved?) -> Card? {
        page.map { Card(title: $0.title, description: $0.description,
                        imageUrl: $0.imageURL?.absoluteString, host: $0.host) }
    }
}

/// Serves each scripted response as raw HTTP/1.1 bytes through the real reader, 16 KiB at a time.
private final class ScriptedClient: PinnedFetching, @unchecked Sendable {
    private static let chunk = 16 * 1024

    private let responses: [String: WebLookupVectorTests.Response]
    private let lock = NSLock()
    private var _requested: [String] = []
    private var _overread: [String] = []

    init(_ responses: [WebLookupVectorTests.Response]) {
        self.responses = Dictionary(responses.map { ($0.url, $0) }, uniquingKeysWith: { $1 })
    }

    var requested: [String] { lock.withLock { _requested } }
    /// URLs read more than one chunk past the cap, or past the head's end when reads stop there.
    var overread: [String] { lock.withLock { _overread } }

    func get(_ url: URL, accept: String, maxBytes: Int, stopsAtHeadEnd: Bool) async throws -> PinnedResponse {
        lock.withLock { _requested.append(url.absoluteString) }
        guard let scripted = responses[url.absoluteString] else { throw URLError(.cannotConnectToHost) }

        let (wire, headEnd) = Self.wire(scripted)
        // Every lookup fetch is a page, so every one must stop at the head's end (P23b).
        let limit = min(maxBytes, headEnd ?? .max) + Self.chunk + 1024
        var reader = HTTP1ResponseReader(maxBytes: maxBytes, stopsAtHeadEnd: stopsAtHeadEnd)
        var offset = 0
        while offset < wire.count {
            let end = min(offset + Self.chunk, wire.count)
            if case .done(let response) = try reader.feed(wire.subdata(in: offset..<end)) {
                if end > limit { lock.withLock { _overread.append(url.absoluteString) } }
                return response
            }
            offset = end
        }
        return try reader.finish()
    }

    /// The response bytes, and the offset into them just past the first `</head`, if any.
    private static func wire(_ scripted: WebLookupVectorTests.Response) -> (Data, Int?) {
        var body = scripted.html ?? ""
        if let fill = scripted.fillBytes {
            body = body.replacingOccurrences(of: "<!--FILL-->", with: "<script>" + String(repeating: "x", count: fill - 17) + "</script>")
        }
        let bytes = Data(body.utf8)
        var head = "HTTP/1.1 \(scripted.status) Status\r\n"
        if let type = scripted.contentType ?? (scripted.html != nil ? "text/html; charset=utf-8" : nil) {
            head += "Content-Type: \(type)\r\n"
        }
        if let location = scripted.location { head += "Location: \(location)\r\n" }
        head += "Content-Length: \(bytes.count)\r\n\r\n"
        let headEnd = bytes.range(of: Data("</head".utf8)).map { Data(head.utf8).count + $0.upperBound }
        return (Data(head.utf8) + bytes, headEnd)
    }
}
