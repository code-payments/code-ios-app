//
//  WebImageDiskCache.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import CryptoKit
import Foundation
import FlipcashCore

/// Preview images kept on disk across launches, in a directory of their own (P22b, P22c).
///
/// Only bytes that already passed the image rules are written. A file's time is its row's: it is
/// restamped whenever the row is recorded again, so a file older than `WebLinks.resolvedTTL` belongs
/// to an expired row, reads as nil and is deleted. The whole store is held under ``capacity`` by
/// dropping the oldest files first.
nonisolated final class WebImageDiskCache: @unchecked Sendable {

    static let shared = WebImageDiskCache(
        directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LinkPreviewImages", isDirectory: true)
    )

    /// The most the store holds, in bytes.
    static let capacity = 20 * 1024 * 1024

    private let directory: URL
    private let capacity: Int
    private let now: @Sendable () -> Date
    // Serializes every file operation; the store has no other state.
    private let lock = NSLock()

    init(directory: URL, capacity: Int = WebImageDiskCache.capacity, now: @escaping @Sendable () -> Date = Date.init) {
        self.directory = directory
        self.capacity = capacity
        self.now = now
    }

    /// The bytes stored for `url`, or nil when there are none or they have outlived their row.
    func data(for url: URL) -> Data? {
        lock.withLock {
            let file = path(for: url)
            guard let written = modified(file) else { return nil }
            guard now().timeIntervalSince(written) <= WebLinks.resolvedTTL else {
                try? FileManager.default.removeItem(at: file)
                return nil
            }
            return try? Data(contentsOf: file)
        }
    }

    /// Stores `data` for `url`, then drops the oldest files until the store fits its capacity.
    func store(_ data: Data, for url: URL) {
        lock.withLock {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = path(for: url)
            guard (try? data.write(to: file, options: .atomic)) != nil else { return }
            try? FileManager.default.setAttributes([.modificationDate: now()], ofItemAtPath: file.path)
            trim()
        }
    }

    /// Restamps what is stored for `url` with the current time, as when the row pointing at it is
    /// recorded again, so the file lives exactly as long as its row (P22c).
    func touch(_ url: URL) {
        lock.withLock {
            let file = path(for: url)
            guard modified(file) != nil else { return }
            try? FileManager.default.setAttributes([.modificationDate: now()], ofItemAtPath: file.path)
        }
    }

    /// Deletes what is stored for `url`, as when the row that pointed at it is replaced.
    func remove(_ url: URL) {
        lock.withLock { try? FileManager.default.removeItem(at: path(for: url)) }
    }

    /// Deletes every file older than `cutoff`, as when the rows written before it are dropped.
    func removeAll(before cutoff: Date) {
        lock.withLock {
            for (file, written, _) in files() where written < cutoff {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    private func trim() {
        let all = files().sorted { $0.written < $1.written }
        var total = all.reduce(0) { $0 + $1.size }
        for (file, _, size) in all where total > capacity {
            try? FileManager.default.removeItem(at: file)
            total -= size
        }
    }

    private func files() -> [(file: URL, written: Date, size: Int)] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []
        return urls.compactMap { file in
            guard let values = try? file.resourceValues(forKeys: Set(keys)),
                  let written = values.contentModificationDate else { return nil }
            return (file, written, values.fileSize ?? 0)
        }
    }

    private func modified(_ file: URL) -> Date? {
        try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    // Keyed by the resolved image URL (P22c), hashed so any URL makes a safe file name.
    private func path(for url: URL) -> URL {
        let digest = CryptoKit.SHA256.hash(data: Data(url.absoluteString.utf8))
        return directory.appendingPathComponent(digest.map { String(format: "%02x", $0) }.joined())
    }
}
