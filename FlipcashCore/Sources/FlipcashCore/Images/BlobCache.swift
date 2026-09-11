//
//  BlobCache.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// Blob bytes on disk, keyed by blob id.
///
/// A blob is immutable — a user who changes their profile picture gets a new id — so a hit never
/// needs revalidating and an entry never goes stale. That is what the URL-keyed HTTP cache cannot
/// do here: `blobDownloadURL` mints a fresh signed URL on every fetch, so the same bytes arrive
/// under a different key each time and every launch re-downloads them.
///
/// It lives in the App Group container so the notification extension and the app are looking at the
/// same bytes: the extension can warm an avatar on push arrival and the app draws it at first paint.
///
/// Best-effort throughout. A failed read or write costs a re-download, never a broken screen.
///
/// ## One instance per kind of blob
///
/// Each kind gets its own directory and its own ceiling — see ``profilePictures``. The budgets are
/// separate because the sizes are: an avatar thumbnail is tens of kilobytes and a full-size chat
/// image is single-digit megabytes, so one shared pool would let a single scroll through an
/// image-heavy conversation evict every avatar on the device. The next launch would be back to
/// blurhashes, which is the problem this cache exists to fix.
public final class BlobCache: @unchecked Sendable {

    /// The App Group shared by the app and both notification extensions.
    public static let appGroup = NotificationPreviewCache.appGroup

    /// Profile-picture thumbnails, for the signed-in user and for everyone they see.
    ///
    /// Roughly 300 of them. Avatars accumulate for every counterparty the user ever encounters, so
    /// the directory needs a ceiling; the coldest entries go first.
    public static let profilePictures = BlobCache(name: "Avatars", limitBytes: 24 * 1024 * 1024)

    /// The parent of every kind's directory.
    ///
    /// Having one lets ``clearAll()`` delete the lot without a registry of kinds to keep in sync. A
    /// kind left out of such a registry would leave other people's photographs on disk through a
    /// logout, and nothing would surface the omission.
    private static var rootDirectory: URL {
        let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: BlobCache.appGroup)
            ?? URL.cachesDirectory
        return container.appendingPathComponent("Blobs", isDirectory: true)
    }

    private let directory: URL
    private let limitBytes: Int
    private let fileManager = FileManager.default

    /// Serializes eviction against concurrent writes. Blobs are fetched from several screens at
    /// once, and two overlapping evictions would each size the directory before the other's delete.
    private let lock = NSLock()

    /// - Parameters:
    ///   - directory: where the bytes go. Injected so tests run against a temporary directory —
    ///     `containerURL(forSecurityApplicationGroupIdentifier:)` resolves differently on macOS,
    ///     where this package's tests run, than it does on a device.
    ///   - limitBytes: the ceiling for the whole directory.
    public init(directory: URL, limitBytes: Int) {
        self.directory = directory
        self.limitBytes = limitBytes
    }

    /// One kind's cache, in its own subdirectory of the App Group container.
    private convenience init(name: String, limitBytes: Int) {
        self.init(
            directory: BlobCache.rootDirectory.appendingPathComponent(name, isDirectory: true),
            limitBytes: limitBytes
        )
    }

    // MARK: - Reading -

    /// The cached bytes for a blob, or nil on a miss.
    ///
    /// A hit touches the file's modification date, which is what eviction orders by — so the
    /// entries backing the screen the user just left survive a round of eviction.
    public func data(for blobID: BlobID) -> Data? {
        let url = fileURL(for: blobID)
        guard let data = try? Data(contentsOf: url) else { return nil }
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return data
    }

    /// Whether the blob's bytes are already on disk, without reading them.
    public func holds(_ blobID: BlobID) -> Bool {
        fileManager.fileExists(atPath: fileURL(for: blobID).path)
    }

    // MARK: - Writing -

    /// Stores the bytes for a blob, evicting the coldest entries if that puts the directory over
    /// its limit. Best-effort.
    ///
    /// A blob larger than the whole budget is not stored at all: writing it would evict everything
    /// else and then itself, leaving the caller to re-download it on every read.
    public func write(_ data: Data, for blobID: BlobID) {
        guard data.count <= limitBytes else { return }

        lock.lock()
        defer { lock.unlock() }

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: fileURL(for: blobID), options: .atomic)
        } catch {
            return
        }

        evictDownToLimit()
    }

    /// Deletes every blob this cache holds.
    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        try? fileManager.removeItem(at: directory)
    }

    /// Deletes every cached blob of every kind. Call on logout: these are other people's
    /// photographs sitting unencrypted in a container the next account on the device reads from.
    public static func clearAll() {
        try? FileManager.default.removeItem(at: rootDirectory)
    }

    // MARK: - Internal -

    /// `ID.description` is the blob's 32 hex characters, which is already a valid file name.
    private func fileURL(for blobID: BlobID) -> URL {
        directory.appendingPathComponent(blobID.description)
    }

    /// Deletes least-recently-used entries until the directory fits. Caller holds `lock`.
    private func evictDownToLimit() {
        let keys: [URLResourceKey] = [.contentAccessDateKey, .contentModificationDateKey, .fileSizeKey]
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys, options: .skipsHiddenFiles
        ) else { return }

        var entries: [(url: URL, date: Date, size: Int)] = contents.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  let size = values.fileSize
            else { return nil }
            return (url, values.contentModificationDate ?? .distantPast, size)
        }

        var total = entries.reduce(0) { $0 + $1.size }
        guard total > limitBytes else { return }

        // Coldest first.
        entries.sort { $0.date < $1.date }

        for entry in entries where total > limitBytes {
            try? fileManager.removeItem(at: entry.url)
            total -= entry.size
        }
    }
}
