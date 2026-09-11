//
//  ProfilePictureCache.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// Profile-picture bytes on disk, keyed by blob id.
///
/// A blob is immutable — a user who changes their picture gets a new id — so a hit never needs
/// revalidating, and the entry never goes stale. That is what the URL-keyed HTTP cache cannot do
/// here: `blobDownloadURL` mints a fresh signed URL on every fetch, so the same picture arrives
/// under a different key each time and every launch re-downloads it.
///
/// It lives in the App Group container so the notification extension and the app are looking at the
/// same bytes: the extension can warm an avatar on push arrival and the app draws it at first paint.
///
/// Best-effort throughout. A failed read or write costs a re-download, never a broken screen.
public final class ProfilePictureCache: @unchecked Sendable {

    /// The App Group shared by the app and both notification extensions.
    public static let appGroup = NotificationPreviewCache.appGroup

    /// The process-wide instance, in the App Group container.
    public static let shared = ProfilePictureCache()

    /// Roughly 300 avatar thumbnails. Avatars accumulate for every counterparty the user ever sees,
    /// so the directory needs a ceiling; the coldest entries go first.
    public static let defaultLimitBytes = 24 * 1024 * 1024

    private let directory: URL
    private let limitBytes: Int
    private let fileManager = FileManager.default

    /// Serializes eviction against concurrent writes. Avatars are fetched from several screens at
    /// once, and two overlapping evictions would each size the directory before the other's delete.
    private let lock = NSLock()

    /// - Parameters:
    ///   - directory: where the bytes go. Injected so tests run against a temporary directory —
    ///     `containerURL(forSecurityApplicationGroupIdentifier:)` resolves differently on macOS,
    ///     where this package's tests run, than it does on a device.
    ///   - limitBytes: the ceiling for the whole directory.
    public init(directory: URL, limitBytes: Int = ProfilePictureCache.defaultLimitBytes) {
        self.directory = directory
        self.limitBytes = limitBytes
    }

    private convenience init() {
        let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: ProfilePictureCache.appGroup)
            ?? URL.cachesDirectory
        self.init(directory: container.appendingPathComponent("Avatars", isDirectory: true))
    }

    // MARK: - Reading -

    /// The cached bytes for a blob, or nil on a miss.
    ///
    /// A hit touches the file's modification date, which is what eviction orders by — so the
    /// pictures on the screen the user just left survive a round of eviction.
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

    /// Deletes every cached picture. Call on logout: the bytes are other users' photographs sitting
    /// unencrypted in a container the next account on the device would read from.
    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        try? fileManager.removeItem(at: directory)
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
