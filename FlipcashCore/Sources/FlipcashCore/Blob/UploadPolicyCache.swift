//
//  UploadPolicyCache.swift
//  FlipcashCore
//

import Foundation

/// Holds the last fetched `UploadPolicy` until its TTL lapses or the server
/// reports a different version.
///
/// In memory only, so a cold launch fetches once.
actor UploadPolicyCache {

    private struct Entry {
        let owner: PublicKey
        let policy: UploadPolicy
        let expiresAt: ContinuousClock.Instant?
    }

    private let now: @Sendable () -> ContinuousClock.Instant
    private var entry: Entry?
    private var inFlight: (owner: PublicKey, task: Task<UploadPolicy, Error>)?

    init(now: @escaping @Sendable () -> ContinuousClock.Instant = { .now }) {
        self.now = now
    }

    /// Returns the cached policy for `owner`, or the result of `fetch` when
    /// there is none still valid.
    ///
    /// Concurrent callers share one fetch, and a failed fetch is not cached.
    func policy(for owner: KeyPair, fetch: @escaping @Sendable () async throws -> UploadPolicy) async throws -> UploadPolicy {
        let key = owner.publicKey

        if let entry, entry.owner == key, entry.expiresAt.map({ now() < $0 }) ?? true {
            return entry.policy
        }

        if let inFlight, inFlight.owner == key {
            return try await inFlight.task.value
        }

        let task = Task { try await fetch() }
        inFlight = (key, task)
        defer {
            if inFlight?.owner == key {
                inFlight = nil
            }
        }

        let policy = try await task.value
        entry = Entry(owner: key, policy: policy, expiresAt: policy.ttl.map { now().advanced(by: $0) })
        return policy
    }

    /// Drops the cached policy when `version` differs from it — the server
    /// echoes the version in force on a policy-driven denial.
    func observe(version: String) {
        if let entry, entry.policy.version != version {
            self.entry = nil
        }
    }
}
