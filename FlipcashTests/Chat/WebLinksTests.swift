//
//  WebLinksTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing
import FlipcashCore

@Suite("WebLinks")
struct WebLinksTests {

    private final class BundleToken {}

    struct Fixture: Decodable {
        struct Host: Decodable { let host: String; let eligible: Bool; let note: String }
        struct CacheKey: Decodable { let url: String; let key: String }
        struct Limits: Decodable {
            let maxBodyBytes: Int
            let maxImageBytes: Int
            let maxRedirects: Int
            let timeoutSeconds: Int
            let maxConcurrent: Int
            let resolvedTtlHours: Int
            let emptyTtlHours: Int
        }
        let hosts: [Host]
        let cacheKeys: [CacheKey]
        let limits: Limits
    }

    private func loadFixture() throws -> Fixture {
        let bundle = Bundle(for: BundleToken.self)
        let url = try #require(bundle.url(forResource: "link_metadata", withExtension: "json"))
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    @Test func hostEligibilityMatchesTheFixture() throws {
        for row in try loadFixture().hosts {
            #expect(WebLinks.isEligibleHost(row.host) == row.eligible, "host `\(row.host)`: \(row.note)")
        }
    }

    @Test func cacheKeysMatchTheFixture() throws {
        for row in try loadFixture().cacheKeys {
            let url = try #require(URL(string: row.url))
            #expect(WebLinks.cacheKey(url) == row.key, "url `\(row.url)`")
        }
    }

    @Test func limitsMatchTheFixture() throws {
        let limits = try loadFixture().limits
        #expect(WebLinks.maxBodyBytes == limits.maxBodyBytes)
        #expect(WebLinks.maxImageBytes == limits.maxImageBytes)
        #expect(WebLinks.maxRedirects == limits.maxRedirects)
        #expect(WebLinks.timeout == TimeInterval(limits.timeoutSeconds))
        #expect(WebLinks.maxConcurrent == limits.maxConcurrent)
        #expect(WebLinks.resolvedTTL == TimeInterval(limits.resolvedTtlHours * 3600))
        #expect(WebLinks.emptyTTL == TimeInterval(limits.emptyTtlHours * 3600))
    }

    /// D13: names a system resolver reads as IP literals, and trailing-dot names, are never eligible.
    @Test(arguments: ["localhost.", "printer.local.", "example.com.", "127.1", "0x7f.0.0.1", "1.1.1.1.", "2130706433"])
    func numericAndTrailingDotHostsAreIneligible(_ host: String) {
        #expect(!WebLinks.isEligibleHost(host))
    }

    @Test(arguments: ["cafe.be", "0xide.com", "1password.com", "123.example"])
    func wordsThatLookHexAreStillEligible(_ host: String) {
        #expect(WebLinks.isEligibleHost(host))
    }

    /// D12: only the default https port is fetched.
    @Test func onlyPort443IsFetchable() throws {
        #expect(WebLinks.isFetchable(try #require(URL(string: "https://example.com/"))))
        #expect(WebLinks.isFetchable(try #require(URL(string: "https://example.com:443/"))))
        #expect(!WebLinks.isFetchable(try #require(URL(string: "https://example.com:6379/"))))
        #expect(!WebLinks.isFetchable(try #require(URL(string: "http://example.com/"))))
    }
}
