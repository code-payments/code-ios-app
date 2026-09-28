//
//  UploadPolicyTests.swift
//  FlipcashCoreTests
//

import Foundation
import Synchronization
import Testing
import FlipcashAPI
@testable import FlipcashCore

@Suite("Upload policy")
struct UploadPolicyTests {

    // MARK: - Proto mapping -

    @Test("Maps version, TTL, and constraints in policy order")
    func mapsProto() {
        let policy = UploadPolicy(Self.proto(version: "v7", ttlSeconds: 300))

        #expect(policy.version == "v7")
        #expect(policy.ttl == .seconds(300))
        #expect(policy.constraints.map(\.pattern) == ["image/jpeg", "image/*", "*/*"])
        #expect(policy.constraints[0].maxSizeBytes == 5_000_000)
        #expect(policy.constraints[0].image == .init(maxWidth: 2048, maxHeight: 2048, maxPixels: 4_000_000))
    }

    /// An opaque-blob entry sets no `kind`, and reading `.image` off it would
    /// hand back zeroes that read as "unbounded" rather than "not an image".
    @Test("An entry without image bounds maps to no image constraints")
    func opaqueEntryHasNoImageConstraints() {
        let policy = UploadPolicy(Self.proto(version: "v7", ttlSeconds: 300))

        #expect(policy.constraints[2].image == nil)
    }

    @Test("An unset TTL maps to nil, not zero")
    func unsetTTLIsNil() {
        var proto = Self.proto(version: "v7", ttlSeconds: 300)
        proto.clearTtl()

        #expect(UploadPolicy(proto).ttl == nil)
    }

    @Test("Picks the first constraint whose pattern matches, in policy order")
    func constraintForMimeType() {
        let policy = UploadPolicy(Self.proto(version: "v7", ttlSeconds: 300))

        #expect(policy.constraint(for: "image/jpeg")?.pattern == "image/jpeg")
        #expect(policy.constraint(for: "image/png")?.pattern == "image/*")
        #expect(policy.constraint(for: "video/mp4")?.pattern == "*/*")
    }

    // MARK: - Access context -

    /// `chatProfile` authorizes only a chat's current picture; message media
    /// must go through the general chat scope or every read is denied.
    @Test("Chat message media reads through the chat scope, not the chat profile")
    func chatMessageUsesChatScope() {
        let conversationID = ConversationID(data: Data(repeating: 7, count: 32))

        #expect(BlobAccessContext.chatMessage(conversationID).proto.scope == .chat(conversationID.proto))
        #expect(BlobAccessContext.chatProfile(conversationID).proto.scope == .chatProfile(conversationID.proto))
    }

    // MARK: - Cache -

    @Test("A second request is served from the cache")
    func cachesAcrossCalls() async throws {
        let cache = UploadPolicyCache()
        let fetches = Mutex(0)
        let owner = try Self.owner()

        _ = try await cache.policy(for: owner) { fetches.withLock { $0 += 1 }; return Self.policy("v1") }
        let second = try await cache.policy(for: owner) { fetches.withLock { $0 += 1 }; return Self.policy("v2") }

        #expect(second.version == "v1")
        #expect(fetches.withLock { $0 } == 1)
    }

    @Test("Concurrent requests share one fetch")
    func coalescesConcurrentFetches() async throws {
        let cache = UploadPolicyCache()
        let fetches = Mutex(0)
        let owner = try Self.owner()

        let versions = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<5 {
                group.addTask {
                    try await cache.policy(for: owner) {
                        fetches.withLock { $0 += 1 }
                        try await Task.sleep(for: .milliseconds(20))
                        return Self.policy("v1")
                    }.version
                }
            }
            return try await group.reduce(into: []) { $0.append($1) }
        }

        #expect(versions == Array(repeating: "v1", count: 5))
        #expect(fetches.withLock { $0 } == 1)
    }

    @Test("A different version echoed by the server forces a re-fetch")
    func differentVersionInvalidates() async throws {
        let cache = UploadPolicyCache()
        let owner = try Self.owner()

        _ = try await cache.policy(for: owner) { Self.policy("v1") }
        await cache.observe(version: "v2")
        let refreshed = try await cache.policy(for: owner) { Self.policy("v2") }

        #expect(refreshed.version == "v2")
    }

    @Test("The cached version echoed back keeps the cache")
    func sameVersionKeepsCache() async throws {
        let cache = UploadPolicyCache()
        let owner = try Self.owner()

        _ = try await cache.policy(for: owner) { Self.policy("v1") }
        await cache.observe(version: "v1")
        let kept = try await cache.policy(for: owner) { Self.policy("v2") }

        #expect(kept.version == "v1")
    }

    @Test("An expired TTL forces a re-fetch")
    func expiredTTLRefetches() async throws {
        let now = Mutex(ContinuousClock.now)
        let cache = UploadPolicyCache(now: { now.withLock { $0 } })
        let owner = try Self.owner()

        _ = try await cache.policy(for: owner) { Self.policy("v1", ttl: .seconds(60)) }

        now.withLock { $0 = $0.advanced(by: .seconds(59)) }
        #expect(try await cache.policy(for: owner) { Self.policy("v2") }.version == "v1")

        now.withLock { $0 = $0.advanced(by: .seconds(1)) }
        #expect(try await cache.policy(for: owner) { Self.policy("v2") }.version == "v2")
    }

    /// The policy is "the constraints in force for the caller", and the client
    /// outlives a logout.
    @Test("A different owner does not see another owner's policy")
    func keyedByOwner() async throws {
        let cache = UploadPolicyCache()

        _ = try await cache.policy(for: try Self.owner()) { Self.policy("v1") }
        let other = try await cache.policy(for: try Self.owner()) { Self.policy("v2") }

        #expect(other.version == "v2")
    }

    @Test("A failed fetch is not cached")
    func failureIsNotCached() async throws {
        let cache = UploadPolicyCache()
        let owner = try Self.owner()

        await #expect(throws: ErrorBlob.self) {
            _ = try await cache.policy(for: owner) { throw ErrorBlob.uploadDenied }
        }
        #expect(try await cache.policy(for: owner) { Self.policy("v1") }.version == "v1")
    }

    // MARK: - Fixtures -

    private static func owner() throws -> KeyPair {
        try #require(KeyPair.generate())
    }

    private static func policy(_ version: String, ttl: Duration? = nil) -> UploadPolicy {
        UploadPolicy(version: version, ttl: ttl, constraints: [])
    }

    private static func proto(version: String, ttlSeconds: Int64) -> Flipcash_Blob_V1_UploadPolicy {
        .with {
            $0.version = .with { $0.value = version }
            $0.ttl = .with { $0.seconds = ttlSeconds }
            $0.mimeTypeConstraints = [
                .with {
                    $0.mimeTypePattern = "image/jpeg"
                    $0.maxSizeBytes = 5_000_000
                    $0.image = .with {
                        $0.maxWidth = 2048
                        $0.maxHeight = 2048
                        $0.maxPixels = 4_000_000
                    }
                },
                .with {
                    $0.mimeTypePattern = "image/*"
                    $0.maxSizeBytes = 10_000_000
                    $0.image = .with { $0.maxWidth = 4096 }
                },
                .with {
                    $0.mimeTypePattern = "*/*"
                    $0.maxSizeBytes = 1_000_000
                },
            ]
        }
    }
}
