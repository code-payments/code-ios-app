//
//  PinnedHTTPClientTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Network
import Testing
import FlipcashCore

@Suite("PinnedHTTPClient")
struct PinnedHTTPClientTests {

    @Test func resolverPicksThePublicAddress() async throws {
        let private1 = try #require(IPv4Address("10.0.0.1"))
        let public1 = try #require(IPv4Address("93.184.215.14"))
        let resolver = PublicAddressResolver(lookup: { _ in [private1, public1] })
        let address = try await resolver.resolve("example.com")
        #expect(address.rawValue == public1.rawValue)
    }

    @Test func resolverThrowsWhenEveryAnswerIsPrivate() async throws {
        let private1 = try #require(IPv4Address("10.0.0.1"))
        let loopback = try #require(IPv6Address("::1"))
        let resolver = PublicAddressResolver(lookup: { _ in [private1, loopback] })
        await #expect(throws: NoPublicAddress.self) { try await resolver.resolve("example.com") }
    }

    @Test func requestBytesAreExact() throws {
        let url = try #require(URL(string: "https://Example.com/a/b?x=1&y=%20z#frag"))
        let expected = "GET /a/b?x=1&y=%20z HTTP/1.1\r\n"
            + "Host: example.com\r\n"
            + "User-Agent: \(WebLinks.userAgent)\r\n"
            + "Accept: text/html\r\n"
            + "Accept-Encoding: identity\r\n"
            + "Connection: close\r\n\r\n"
        #expect(PinnedHTTPClient.requestBytes(for: url, accept: "text/html") == Data(expected.utf8))
    }

    @Test func requestBytesUseRootPathAndShowANonDefaultPort() throws {
        let url = try #require(URL(string: "https://example.com:8443"))
        let text = String(decoding: PinnedHTTPClient.requestBytes(for: url, accept: "*/*"), as: UTF8.self)
        #expect(text.hasPrefix("GET / HTTP/1.1\r\nHost: example.com:8443\r\n"))
        #expect(!text.lowercased().contains("cookie"))
        #expect(!text.lowercased().contains("authorization"))
    }

    @Test func requestBytesUseThePunycodeHost() throws {
        let url = try #require(URL(string: "https://bücher.example/"))
        let text = String(decoding: PinnedHTTPClient.requestBytes(for: url, accept: "*/*"), as: UTF8.self)
        #expect(text.contains("Host: xn--bcher-kva.example\r\n"))
    }

    @Test func nonHTTPSIsNotAllowed() async throws {
        let client = PinnedHTTPClient(resolver: PublicAddressResolver(lookup: { _ in
            Issue.record("resolved"); return []
        }))
        await #expect(throws: NotAllowed.self) {
            try await client.get(try #require(URL(string: "http://example.com/")), accept: "*/*", maxBytes: 10)
        }
    }

    // MARK: - Network (opt in) -

    private static let networkEnabled = ProcessInfo.processInfo.environment["PINNED_HTTP_NETWORK_TESTS"] == "1"

    @Test(.enabled(if: networkEnabled, "set PINNED_HTTP_NETWORK_TESTS=1"))
    func fetchesExampleDotCom() async throws {
        let response = try await PinnedHTTPClient().get(
            try #require(URL(string: "https://example.com/")), accept: "text/html", maxBytes: WebLinks.maxBodyBytes
        )
        #expect(response.status == 200)
        #expect(String(decoding: response.body, as: UTF8.self).contains("<title>"))
    }

    @Test(.enabled(if: networkEnabled, "set PINNED_HTTP_NETWORK_TESTS=1"))
    func rejectsACertificateForAnotherHost() async throws {
        await #expect(throws: (any Error).self) {
            try await PinnedHTTPClient().get(
                try #require(URL(string: "https://wrong.host.badssl.com/")), accept: "text/html", maxBytes: WebLinks.maxBodyBytes
            )
        }
    }
}
